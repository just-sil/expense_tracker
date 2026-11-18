import 'dart:convert';

import 'package:http/http.dart' as http;

import '../database/local_database.dart';

class SyncService {
  // YOUR LAPTOP IP
  static const String serverUrl =
      'http://192.168.0.198:5000';

  Future<void> syncPendingExpenses() async {
    final pending =
        await LocalDatabase.instance.getPendingLogs();

    for (final expense in pending) {
      try {
        await _syncExpense(expense);
      } catch (e) {
        await LocalDatabase.instance.markAsFailed(
          expense['id'] as int,
          e.toString(),
        );
      }
    }
  }

  Future<void> _syncExpense(
    Map<String, dynamic> expense,
  ) async {
    final id = expense['id'] as int;

    final response = await http.post(
      Uri.parse(
        '$serverUrl/api/sync',
      ),

      headers: {
        'Content-Type':
            'application/json',
      },

      body: jsonEncode({
        'raw_text':
            expense['raw_text'],

        'created_at':
            expense['created_at'],
      }),
    );

    if (response.statusCode != 201) {
      throw Exception(
        'Server error '
        '${response.statusCode}: '
        '${response.body}',
      );
    }

    final data =
        jsonDecode(response.body);

    if (data['success'] != true) {
      throw Exception(
        data['error'] ??
            'Sync failed',
      );
    }

    final serverId =
        data['server_id'];

    if (serverId == null) {
      throw Exception(
        'Server did not return server_id',
      );
    }

    // Keep the server's parsed values locally so
    // the summary tab can show real totals offline.
    final parsed =
        data['expense'] as Map<String, dynamic>?;

    await LocalDatabase.instance
        .markAsSynced(
      id,
      serverId as int,
      amount:
          (parsed?['amount'] as num?)?.toDouble(),
      category:
          parsed?['category'] as String?,
      expenseDate:
          parsed?['date']?.toString(),
    );
  }
}