import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../services/sync_service.dart';
import '../state/app_settings.dart';
import '../util/format.dart';

/// Asks for the laptop's Wi-Fi address and saves it.
/// Returns true if an address was saved.
Future<bool> editLaptopAddress(
  BuildContext context,
  SyncService syncService,
) async {
  final current = await syncService.getLanUrl();

  // Show just "ip" or "ip:port" for editing.
  final uri = Uri.parse(current);
  final initial = uri.port == SyncService.defaultPort
      ? uri.host
      : '${uri.host}:${uri.port}';

  if (!context.mounted) return false;

  final controller = TextEditingController(text: initial);
  String? errorText;

  final result = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        void save() {
          final url = SyncService.normalizeAddress(controller.text);
          if (url == null) {
            setDialogState(() => errorText = 'Enter an IP like 192.168.0.198');
            return;
          }
          Navigator.pop(context, url);
        }

        return AlertDialog(
          title: const Text('Laptop address'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            onSubmitted: (_) => save(),
            decoration: InputDecoration(
              labelText: 'Laptop IP on your Wi-Fi',
              hintText: '192.168.0.198',
              helperText: 'Port ${SyncService.defaultPort} is used if you '
                  'leave it out. USB is always tried first.',
              helperMaxLines: 3,
              errorText: errorText,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, SyncService.defaultLanUrl),
              child: const Text('Reset'),
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

  if (result == null) return false;

  await syncService.setLanUrl(result);

  final reachable = await SyncService.isReachable(result);

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          reachable
              ? 'Saved. Laptop found at ${Uri.parse(result).host}'
              : 'Saved, but the laptop isn\'t answering there right now',
        ),
      ),
    );
  }
  return true;
}

class SettingsScreen extends StatefulWidget {
  final SyncService syncService;
  final NotificationService notificationService;

  const SettingsScreen({
    super.key,
    required this.syncService,
    required this.notificationService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  String? lanUrl;
  bool? notificationsOn;

  /// null = not checked, '' = checking, else a result line.
  String? connection;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Android's notification access screen.
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final url = await widget.syncService.getLanUrl();
    final on = widget.notificationService.isSupported
        ? await widget.notificationService.isEnabled()
        : null;
    if (!mounted) return;
    setState(() {
      lanUrl = url;
      notificationsOn = on;
    });
  }

  Future<void> _checkConnection() async {
    setState(() => connection = '');
    final type = await widget.syncService.connectionType();
    if (!mounted) return;
    setState(() {
      connection = type == null
          ? 'Not reachable. Make sure the backend is running and the '
              'phone is on the same Wi-Fi, or plugged in over USB.'
          : 'Connected over $type';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
          child: Text(
            text,
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.primary),
          ),
        );

    final host = lanUrl == null ? '…' : Uri.parse(lanUrl!).host;
    final port = lanUrl == null ? null : Uri.parse(lanUrl!).port;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          header('Laptop sync'),
          ListTile(
            leading: const Icon(Icons.computer_outlined),
            title: const Text('Laptop address'),
            subtitle: Text(
              port == null || port == SyncService.defaultPort
                  ? host
                  : '$host:$port',
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              if (await editLaptopAddress(context, widget.syncService)) {
                await _load();
                setState(() => connection = null);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.wifi_tethering),
            title: const Text('Check connection'),
            subtitle: connection == null
                ? const Text('USB is tried first, then Wi-Fi')
                : connection!.isEmpty
                    ? const Text('Checking…')
                    : Text(connection!),
            trailing: connection == ''
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: connection == '' ? null : _checkConnection,
          ),
          header('Budget'),
          ValueListenableBuilder<double?>(
            valueListenable: AppSettings.instance.dailyLimit,
            builder: (context, limit, _) => ListTile(
              leading: const Icon(Icons.savings_outlined),
              title: const Text('Daily limit'),
              subtitle: Text(
                limit == null
                    ? 'Not set'
                    : '${formatMoney(limit)} a day · '
                        '${formatMoney(limit * 7)} a week',
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => AppSettings.instance.editDailyLimit(context),
            ),
          ),
          if (widget.notificationService.isSupported) ...[
            header('Auto-log'),
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Payment notifications'),
              subtitle: Text(
                notificationsOn == true
                    ? 'On. Bank and UPI payment alerts are added '
                        'as expenses.'
                    : 'Off. Turn on to add bank and UPI payments '
                        'automatically.',
              ),
              trailing: Text(
                notificationsOn == true ? 'On' : 'Turn on',
                style: TextStyle(color: theme.colorScheme.primary),
              ),
              onTap: widget.notificationService.openSettings,
            ),
          ],
          header('Privacy'),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Your data stays with you'),
            subtitle: Text(
              'Expenses are saved on this phone and synced only to '
              'your own laptop. No accounts, no cloud.',
            ),
          ),
        ],
      ),
    );
  }
}
