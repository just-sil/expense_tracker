import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/local_database.dart';
import '../util/format.dart';

/// Settings that several screens read and edit, kept in the
/// local `settings` table and exposed as notifiers so every
/// screen updates when one changes them.
class AppSettings {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  static const String _limitKey = 'daily_limit';
  static const String _hideNotificationTipKey = 'hide_notification_tip';

  /// Daily spending limit; null when not set.
  final ValueNotifier<double?> dailyLimit = ValueNotifier(null);

  /// True once the user dismissed the auto-log suggestion.
  final ValueNotifier<bool> hideNotificationTip = ValueNotifier(false);

  Future<void> load() async {
    final db = LocalDatabase.instance;
    final limit = await db.getSetting(_limitKey);
    dailyLimit.value = limit == null ? null : double.tryParse(limit);
    hideNotificationTip.value =
        await db.getSetting(_hideNotificationTipKey) == 'true';
  }

  Future<void> setDailyLimit(double? value) async {
    await LocalDatabase.instance.setSetting(_limitKey, value?.toString());
    dailyLimit.value = value;
  }

  Future<void> setHideNotificationTip(bool value) async {
    await LocalDatabase.instance.setSetting(
      _hideNotificationTipKey,
      value ? 'true' : null,
    );
    hideNotificationTip.value = value;
  }

  /// Dialog to set, change or remove the daily limit.
  Future<void> editDailyLimit(BuildContext context) async {
    final current = dailyLimit.value;
    final controller = TextEditingController(
      text: current == null ? '' : formatNumber(current).replaceAll(',', ''),
    );

    String? errorText;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void save() {
            final text = controller.text.trim();
            final parsed = double.tryParse(text);
            if (parsed == null || parsed <= 0) {
              setDialogState(() => errorText = 'Enter an amount above 0');
              return;
            }
            Navigator.pop(context, text);
          }

          return AlertDialog(
            title: const Text('Daily limit'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              onSubmitted: (_) => save(),
              decoration: InputDecoration(
                prefixText: '₹ ',
                hintText: '300',
                errorText: errorText,
                helperText: 'Unspent money rolls over to the rest of '
                    'the week. Resets every Monday.',
                helperMaxLines: 2,
              ),
            ),
            actions: [
              if (current != null)
                TextButton(
                  onPressed: () => Navigator.pop(context, ''),
                  child: const Text('Remove'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(onPressed: save, child: const Text('Save')),
            ],
          );
        },
      ),
    );

    // Not disposed here: the dialog's closing animation
    // still renders the TextField. It is garbage-collected.

    if (result == null) return; // cancelled

    await setDailyLimit(result.isEmpty ? null : double.parse(result));
  }
}
