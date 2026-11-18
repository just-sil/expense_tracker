import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../database/local_database.dart';

/// Bridges to the native ExpenseNotificationListener, which queues
/// payment notifications (bank SMS, UPI apps, card alerts) while the
/// app is closed. Imported entries become ordinary pending expenses
/// and get parsed by the laptop on the next sync.
class NotificationService {
  static const _channel =
      MethodChannel('expense_tracker/notifications');

  bool get isSupported => Platform.isAndroid;

  Future<bool> isEnabled() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('isEnabled') ?? false;
  }

  Future<void> openSettings() async {
    if (!isSupported) return;
    await _channel.invokeMethod('openSettings');
  }

  /// Moves queued notifications into the local database.
  /// Returns how many expenses were added.
  Future<int> importQueued() async {
    if (!isSupported) return 0;

    final raw = await _channel.invokeMethod<String>('drain');
    if (raw == null || raw.isEmpty) return 0;

    final items = jsonDecode(raw) as List<dynamic>;

    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final app = map['app'] as String? ?? '';
      final text = map['text'] as String? ?? '';
      final postedAt = map['posted_at'] as int?;

      await LocalDatabase.instance.addExpenseLog(
        rawText: app.isEmpty ? text : '[$app] $text',
        createdAt: postedAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(postedAt),
        source: 'notification',
      );
    }

    return items.length;
  }
}
