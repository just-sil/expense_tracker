package com.example.expense_tracker

import android.app.Notification
import android.content.Context
import android.os.SystemClock
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject

/**
 * Watches posted notifications for payment / debit messages
 * (bank SMS, UPI apps, card alerts) and queues them. The Flutter
 * side drains the queue into the local expense log, where the
 * normal laptop sync parses them with Ollama.
 *
 * Queuing instead of writing to SQLite directly keeps this service
 * independent of the Dart-owned schema and works while the app
 * is closed.
 */
class ExpenseNotificationListener : NotificationListenerService() {

    override fun onListenerConnected() {
        super.onListenerConnected()
        // After a reboot or app update the system reconnects us and apps
        // re-post their still-unread notifications. Open a short window in
        // which an exact repeat of any recently logged text is treated as
        // a repost rather than a new payment.
        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putLong(KEY_CONNECTED_AT, System.currentTimeMillis())
            .apply()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName == packageName) return
        if (sbn.isOngoing) return

        val notification = sbn.notification
        // Skip group summaries; the individual messages arrive separately.
        if (notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return

        val extras = notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val body = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString().orEmpty()

        val text = listOf(title, body)
            .filter { it.isNotBlank() }
            .joinToString(": ")
            .trim()

        if (!looksLikeExpense(text)) return

        // `when` is the app's own timestamp for the event (for SMS, when the
        // message arrived) and survives re-posts, unlike postTime.
        val now = System.currentTimeMillis()
        val eventTime = notification.`when`
            .takeIf { it in 1..(now + 60_000) }
            ?: sbn.postTime

        enqueue(applicationContext, sbn.packageName, appLabel(sbn.packageName), text, eventTime)
    }

    private fun appLabel(pkg: String): String = try {
        val info = packageManager.getApplicationInfo(pkg, 0)
        packageManager.getApplicationLabel(info).toString()
    } catch (_: Exception) {
        pkg
    }

    companion object {
        const val PREFS = "notification_expenses"
        const val KEY_QUEUE = "queue"
        const val KEY_RECENT = "recent"
        const val KEY_SEEN = "seen"
        const val KEY_SEEN_TEXT = "seen_text"
        const val KEY_CONNECTED_AT = "connected_at"
        private const val MINUTE = 60 * 1000L
        private const val DAY = 24 * 60 * MINUTE
        private const val DEDUPE_WINDOW_MS = 10 * MINUTE
        private const val SEEN_RETENTION_MS = 30 * DAY
        private const val TEXT_RETENTION_MS = 7 * DAY
        private const val REPOST_WINDOW_MS = 5 * MINUTE
        // Anything this old is a resurfaced notification, not a new payment.
        private const val MAX_EVENT_AGE_MS = 1 * DAY

        private val amountPattern = Regex(
            """(₹|\bRs\.?|\bINR)\s?\d[\d,]*(\.\d+)?|\d[\d,]*(\.\d+)?\s?(₹|\bRs\b|\bINR\b)""",
            RegexOption.IGNORE_CASE,
        )

        private val debitPattern = Regex(
            """\b(debited|debit|paid|spent|sent|purchase[d]?|withdrawn|withdrawal|payment of|paying|txn of|charged|auto-?pay)\b""",
            RegexOption.IGNORE_CASE,
        )

        // Money coming in. Used to decide direction when a message
        // mentions both sides ("debited from your a/c ... credited to X").
        private val creditPattern = Regex(
            """\b(credited|credit of|received|deposited|added to)\b""",
            RegexOption.IGNORE_CASE,
        )

        // Phrases that only ever describe money you received, e.g.
        // "Mridhul paid you ₹1.00", "You have received Rs 500",
        // "Rs 500 credited to your a/c". These always win.
        private val incomingPattern = Regex(
            """\b(paid you|sent you|transferred to you|you('ve| have)? received|received (rs\.?|inr|₹)|received from|credited (to|in|into) your|has been credited|is credited|money received|payment received)\b""",
            RegexOption.IGNORE_CASE,
        )

        // Not a completed payment at all.
        private val ignorePattern = Regex(
            """\b(otp|one[- ]time password|refund(ed)?|cashback|request(ed)? (money|₹)|collect request|requested|will be debited|due on|due date|bill generated|statement|failed|declined|reversed|offer|win|get up to)\b""",
            RegexOption.IGNORE_CASE,
        )

        fun looksLikeExpense(text: String): Boolean {
            if (text.length < 8) return false
            if (!amountPattern.containsMatchIn(text)) return false
            if (ignorePattern.containsMatchIn(text)) return false
            if (incomingPattern.containsMatchIn(text)) return false

            val debit = debitPattern.find(text) ?: return false
            val credit = creditPattern.find(text)

            // Both sides mentioned: the first one describes your account.
            if (credit != null && credit.range.first < debit.range.first) {
                return false
            }

            return true
        }

        @Synchronized
        fun enqueue(
            context: Context,
            pkg: String,
            label: String,
            text: String,
            eventTime: Long,
        ) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val now = System.currentTimeMillis()

            if (now - eventTime > MAX_EVENT_AGE_MS) return

            // 1. Exact identity: same app, same text, same event time.
            //    Catches re-posts after reboot, app updates and edits.
            val seen = pruned(prefs, KEY_SEEN, now, SEEN_RETENTION_MS)
            val identity = "$pkg|$eventTime|${text.hashCode()}"
            if (seen.has(identity)) return

            // 2. Right after (re)connecting, some apps re-post with a fresh
            //    timestamp. An exact text repeat in that window is a repost.
            val seenText = pruned(prefs, KEY_SEEN_TEXT, now, TEXT_RETENTION_MS)
            val textKey = "$pkg|${text.hashCode()}"
            val connectedAt = prefs.getLong(KEY_CONNECTED_AT, 0L)
            val justConnected = now - connectedAt < REPOST_WINDOW_MS
            // A notification from before this boot can't be new either.
            val bootTime = now - SystemClock.elapsedRealtime()
            if (seenText.has(textKey) && (justConnected || eventTime < bootTime)) return

            // 3. Same alert from two sources (bank app + SMS) within minutes.
            val recent = pruned(prefs, KEY_RECENT, now, DEDUPE_WINDOW_MS)
            val fuzzy = normalize(text)
            if (recent.has(fuzzy)) return

            seen.put(identity, now)
            seenText.put(textKey, now)
            recent.put(fuzzy, now)

            val queue = JSONArray(prefs.getString(KEY_QUEUE, "[]") ?: "[]")
            queue.put(
                JSONObject()
                    .put("package", pkg)
                    .put("app", label)
                    .put("text", text)
                    .put("posted_at", eventTime),
            )

            prefs.edit()
                .putString(KEY_QUEUE, queue.toString())
                .putString(KEY_SEEN, seen.toString())
                .putString(KEY_SEEN_TEXT, seenText.toString())
                .putString(KEY_RECENT, recent.toString())
                .commit()
        }

        /** Loads a key -> timestamp map, dropping entries older than [maxAge]. */
        private fun pruned(
            prefs: android.content.SharedPreferences,
            key: String,
            now: Long,
            maxAge: Long,
        ): JSONObject {
            val stored = try {
                JSONObject(prefs.getString(key, "{}") ?: "{}")
            } catch (_: Exception) {
                JSONObject()
            }
            val result = JSONObject()
            stored.keys().forEach { k ->
                val t = stored.optLong(k)
                if (now - t < maxAge) result.put(k, t)
            }
            return result
        }

        @Synchronized
        fun drain(context: Context): String {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val queue = prefs.getString(KEY_QUEUE, "[]") ?: "[]"
            prefs.edit().putString(KEY_QUEUE, "[]").commit()
            return queue
        }

        private fun normalize(text: String): String {
            val amount = amountPattern.find(text)?.value
                ?.filter { it.isDigit() || it == '.' }
                .orEmpty()
            // Amount + a coarse fingerprint of the words.
            val words = text.lowercase().replace(Regex("[^a-z ]"), " ")
                .split(' ').filter { it.length > 3 }.take(6).joinToString(" ")
            return "$amount|$words"
        }
    }
}
