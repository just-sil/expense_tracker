import 'dart:convert';

import 'package:http/http.dart' as http;

import '../database/local_database.dart';

class SyncService {
  // Tried in order. The first is reachable over USB after
  // running `adb reverse tcp:5000 tcp:5000` on the laptop;
  // the second is the laptop's IP on the local Wi-Fi.
  static const List<String> serverUrls = [
    'http://127.0.0.1:5000',
    'http://192.168.0.198:5000',
  ];

  Future<String> _findServer() async {
    for (final url in serverUrls) {
      try {
        final response = await http
            .get(Uri.parse('$url/api/health'))
            .timeout(const Duration(seconds: 2));

        if (response.statusCode == 200) {
          return url;
        }
      } catch (_) {
        // Try the next address.
      }
    }

    throw Exception(
      'Laptop server not reachable over USB or Wi-Fi',
    );
  }

  Future<void> syncPendingExpenses() async {
    final pending =
        await LocalDatabase.instance.getPendingLogs();

    if (pending.isEmpty) return;

    // Fails before touching any entry, so nothing is
    // marked failed just because the laptop is offline.
    final serverUrl = await _findServer();

    for (final expense in pending) {
      try {
        await _syncExpense(serverUrl, expense);
      } catch (e) {
        await LocalDatabase.instance.markAsFailed(
          expense['id'] as int,
          e.toString(),
        );
      }
    }
  }

  Future<void> _syncExpense(
    String serverUrl,
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