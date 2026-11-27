import 'dart:convert';

import 'package:http/http.dart' as http;

import '../database/local_database.dart';

/// Thrown when neither USB nor the saved Wi-Fi address
/// answers. Nothing was changed.
class LaptopNotFoundException implements Exception {
  final String lanUrl;

  LaptopNotFoundException(this.lanUrl);

  @override
  String toString() =>
      'Laptop not reachable over USB or at $lanUrl.';
}

/// Outcome of one sync run.
class SyncResult {
  final int synced;
  final int failed;

  const SyncResult({this.synced = 0, this.failed = 0});

  bool get nothingToDo => synced == 0 && failed == 0;
}

class SyncService {
  // Reachable over USB after running
  // `adb reverse tcp:5000 tcp:5000` on the laptop.
  static const String usbUrl = 'http://127.0.0.1:5000';

  // Used until an address is saved from the app
  // (long-press the Sync button).
  static const String defaultLanUrl =
      'http://192.168.0.198:5000';

  static const int defaultPort = 5000;

  static const String _lanUrlKey = 'server_url';

  /// The laptop's Wi-Fi address, as saved in settings.
  Future<String> getLanUrl() async {
    return await LocalDatabase.instance
            .getSetting(_lanUrlKey) ??
        defaultLanUrl;
  }

  Future<void> setLanUrl(String url) async {
    await LocalDatabase.instance.setSetting(
      _lanUrlKey,
      url,
    );
  }

  /// Turns "192.168.0.5", "192.168.0.5:8000" or
  /// "http://192.168.0.5:5000/" into a base URL.
  /// Returns null if the input isn't a usable address.
  static String? normalizeAddress(String input) {
    var text = input.trim();

    if (text.isEmpty) return null;

    if (!text.contains('://')) {
      text = 'http://$text';
    }

    final uri = Uri.tryParse(text);

    if (uri == null ||
        uri.host.isEmpty ||
        !(uri.scheme == 'http' ||
            uri.scheme == 'https')) {
      return null;
    }

    final port = uri.hasPort ? uri.port : defaultPort;

    return '${uri.scheme}://${uri.host}:$port';
  }

  /// True if a backend answers at [url].
  static Future<bool> isReachable(String url) async {
    try {
      final response = await http
          .get(Uri.parse('$url/api/health'))
          .timeout(const Duration(seconds: 2));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Tries USB first, then the saved Wi-Fi address.
  Future<String> _findServer() async {
    final lanUrl = await getLanUrl();

    for (final url in [usbUrl, lanUrl]) {
      if (await isReachable(url)) {
        return url;
      }
    }

    throw LaptopNotFoundException(lanUrl);
  }

  /// Which way the laptop answers right now: 'USB',
  /// 'Wi-Fi', or null when it doesn't.
  Future<String?> connectionType() async {
    if (await isReachable(usbUrl)) return 'USB';
    if (await isReachable(await getLanUrl())) return 'Wi-Fi';
    return null;
  }

  /// Sends every pending/failed entry to the laptop.
  /// [onProgress] gets (done, total) before each entry.
  /// Throws [LaptopNotFoundException] before touching any
  /// entry, so nothing is marked failed just because the
  /// laptop is offline.
  Future<SyncResult> syncPendingExpenses({
    void Function(int done, int total)? onProgress,
  }) async {
    final pending =
        await LocalDatabase.instance.getPendingLogs();

    if (pending.isEmpty) return const SyncResult();

    final serverUrl = await _findServer();

    var synced = 0;
    var failed = 0;

    for (final expense in pending) {
      onProgress?.call(synced + failed, pending.length);
      try {
        await _syncExpense(serverUrl, expense);
        synced++;
      } catch (e) {
        failed++;
        await LocalDatabase.instance.markAsFailed(
          expense['id'] as int,
          e.toString(),
        );
      }
    }

    return SyncResult(synced: synced, failed: failed);
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

        // Present for rewritten entries, so the server
        // updates the existing row instead of adding one.
        if (expense['server_id'] != null)
          'server_id': expense['server_id'],
      }),
    ).timeout(
      // Parsing takes seconds; this only stops a hung
      // laptop from leaving sync spinning forever.
      const Duration(seconds: 120),
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
      description:
          parsed?['description'] as String?,
    );
  }
}