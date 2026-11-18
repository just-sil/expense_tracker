package com.example.expense_tracker

import android.app.Notification
import android.content.Context
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

        enqueue(applicationContext, sbn.packageName, appLabel(sbn.packageName), text, sbn.postTime)
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
        private const val DEDUPE_WINDOW_MS = 10 * 60 * 1000L

        private val amountPattern = Regex(
            """(₹|\bRs\.?|\bINR)\s?\d[\d,]*(\.\d+)?|\d[\d,]*(\.\d+)?\s?(₹|\bRs\b|\bINR\b)""",
            RegexOption.IGNORE_CASE,
        )

        private val debitPattern = Regex(
            """\b(debited|debit|paid|spent|sent|purchase[d]?|withdrawn|withdrawal|payment of|paying|txn of|charged|auto-?pay)\b""",
            RegexOption.IGNORE_CASE,
        )

        private val ignorePattern = Regex(
            """\b(otp|one[- ]time password|credited|received|refund(ed)?|cashback|request(ed)? (money|₹)|collect request|will be debited|due on|due date|bill generated|statement|failed|declined|reversed|offer|win|get up to)\b""",
            RegexOption.IGNORE_CASE,
        )

        fun looksLikeExpense(text: String): Boolean {
            if (text.length < 8) return false
            if (!amountPattern.containsMatchIn(text)) return false
            if (!debitPattern.containsMatchIn(text)) return false
            if (ignorePattern.containsMatchIn(text)) return false
            return true
        }

        @Synchronized
        fun enqueue(
            context: Context,
            pkg: String,
            label: String,
            text: String,
            postTime: Long,
        ) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

            // The same alert often shows up twice (bank app + SMS) or gets
            // re-posted when updated; drop repeats of the same amount line.
            val key = normalize(text)
            val now = System.currentTimeMillis()
            val recent = JSONObject(prefs.getString(KEY_RECENT, "{}") ?: "{}")
            val pruned = JSONObject()
            recent.keys().forEach { k ->
                val t = recent.optLong(k)
                if (now - t < DEDUPE_WINDOW_MS) pruned.put(k, t)
            }
            if (pruned.has(key)) return
            pruned.put(key, now)

            val queue = JSONArray(prefs.getString(KEY_QUEUE, "[]") ?: "[]")
            queue.put(
                JSONObject()
                    .put("package", pkg)
                    .put("app", label)
                    .put("text", text)
                    .put("posted_at", postTime),
            )

            prefs.edit()
                .putString(KEY_QUEUE, queue.toString())
                .putString(KEY_RECENT, pruned.toString())
                .commit()
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
