import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'database/local_database.dart';
import 'screens/summary_screen.dart';
import 'services/notification_service.dart';
import 'services/sync_service.dart';

void main() {
  runApp(const ExpenseApp());
}

class ExpenseApp extends StatelessWidget {
  const ExpenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Chillara',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
        ),
        useMaterial3: true,
      ),
      home: const ExpenseHomePage(),
    );
  }
}

class ExpenseHomePage extends StatefulWidget {
  const ExpenseHomePage({super.key});

  @override
  State<ExpenseHomePage> createState() =>
      _ExpenseHomePageState();
}

class _ExpenseHomePageState
    extends State<ExpenseHomePage>
    with WidgetsBindingObserver {
  final TextEditingController textController =
      TextEditingController();

  final ImagePicker imagePicker = ImagePicker();

  final SyncService syncService = SyncService();

  final NotificationService notificationService =
      NotificationService();

  bool notificationsEnabled = false;

  List<Map<String, dynamic>> logs = [];

  String? selectedScreenshot;

  bool loading = true;
  bool saving = false;
  bool syncing = false;

  int currentTab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadLogs();
    importNotifications();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pick up payments seen while the app was in the
    // background, and re-check access after the user
    // returns from the system settings screen.
    if (state == AppLifecycleState.resumed) {
      importNotifications();
    }
  }

  // --------------------------------------------------
  // IMPORT EXPENSES FROM NOTIFICATIONS
  // --------------------------------------------------

  Future<void> importNotifications() async {
    if (!notificationService.isSupported) return;

    try {
      final enabled =
          await notificationService.isEnabled();
      final added =
          await notificationService.importQueued();

      if (!mounted) return;

      setState(() {
        notificationsEnabled = enabled;
      });

      if (added > 0) {
        await loadLogs();

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Added $added expense(s) from notifications',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Notification import failed: $e');
    }
  }

  // --------------------------------------------------
  // LOAD LOCAL EXPENSES
  // --------------------------------------------------

  Future<void> loadLogs() async {
    final data =
        await LocalDatabase.instance.getExpenseLogs();

    if (!mounted) return;

    setState(() {
      logs = data;
      loading = false;
    });
  }

  // --------------------------------------------------
  // PICK SCREENSHOT
  // --------------------------------------------------

  Future<void> pickScreenshot() async {
    final image = await imagePicker.pickImage(
      source: ImageSource.gallery,
    );

    if (image == null) return;

    final directory =
        await getApplicationDocumentsDirectory();

    final screenshotsDirectory = Directory(
      '${directory.path}/screenshots',
    );

    if (!await screenshotsDirectory.exists()) {
      await screenshotsDirectory.create(
        recursive: true,
      );
    }

    final filename =
        '${DateTime.now().millisecondsSinceEpoch}.jpg';

    final savedFile = await File(image.path).copy(
      '${screenshotsDirectory.path}/$filename',
    );

    if (!mounted) return;

    setState(() {
      selectedScreenshot = savedFile.path;
    });
  }

  // --------------------------------------------------
  // SAVE EXPENSE LOCALLY
  // --------------------------------------------------

  Future<void> saveExpense() async {
    final text = textController.text.trim();

    if (text.isEmpty && selectedScreenshot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter an expense or add a screenshot',
          ),
        ),
      );

      return;
    }

    setState(() {
      saving = true;
    });

    try {
      await LocalDatabase.instance.addExpenseLog(
        rawText: text,
        screenshotPath: selectedScreenshot,
      );

      textController.clear();

      if (!mounted) return;

      setState(() {
        selectedScreenshot = null;
      });

      await loadLogs();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Expense saved locally',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
        });
      }
    }
  }

  // --------------------------------------------------
  // SYNC WITH LAPTOP
  // --------------------------------------------------

  Future<void> syncExpenses() async {
    if (syncing) return;

    setState(() {
      syncing = true;
    });

    try {
      await importNotifications();
      await syncService.syncPendingExpenses();

      await loadLogs();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sync completed',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sync failed: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          syncing = false;
        });
      }
    }
  }

  // --------------------------------------------------
  // CHANGE LAPTOP ADDRESS (long-press Sync)
  // --------------------------------------------------

  Future<void> editServerAddress() async {
    final current = await syncService.getLanUrl();

    // Show just "ip" or "ip:port" for editing.
    final uri = Uri.parse(current);
    final initial = uri.port == SyncService.defaultPort
        ? uri.host
        : '${uri.host}:${uri.port}';

    if (!mounted) return;

    final controller =
        TextEditingController(text: initial);

    String? errorText;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void save() {
            final url = SyncService.normalizeAddress(
              controller.text,
            );

            if (url == null) {
              setDialogState(() {
                errorText =
                    'Enter an IP like 192.168.0.198';
              });
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
                labelText: 'Computer IP',
                hintText: '192.168.0.198',
                helperText:
                    'Port ${SyncService.defaultPort} is '
                    'used if you leave it out. USB sync '
                    'is always tried first.',
                helperMaxLines: 3,
                errorText: errorText,
                border: const OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  SyncService.defaultLanUrl,
                ),
                child: const Text('Reset'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: save,
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    // Not disposed here: the dialog's closing animation
    // still renders the TextField. It is garbage-collected.

    if (result == null) return;

    await syncService.setLanUrl(result);

    final reachable =
        await SyncService.isReachable(result);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          reachable
              ? 'Saved. Laptop found at $result'
              : 'Saved $result, but the laptop is not '
                  'answering there right now',
        ),
      ),
    );
  }

  // --------------------------------------------------
  // DELETE EXPENSE
  // --------------------------------------------------

  Future<void> deleteExpense(
    Map<String, dynamic> expense,
  ) async {
    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Delete expense?',
          ),
          content: const Text(
            'This will permanently remove this '
            'expense from your phone.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              child: const Text(
                'Delete',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final id = expense['id'] as int;

    final screenshotPath =
        expense['screenshot_path'] as String?;

    await LocalDatabase.instance.deleteExpense(
      id,
    );

    // Delete screenshot from phone too.
    if (screenshotPath != null) {
      final file = File(
        screenshotPath,
      );

      if (await file.exists()) {
        await file.delete();
      }
    }

    await loadLogs();
  }

  // --------------------------------------------------
  // SHOW SCREENSHOT
  // --------------------------------------------------

  void showScreenshot(String path) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: const Text(
              'Screenshot',
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.file(
                File(path),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------
  // BUILD
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Chillara',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          // Long-press opens the laptop address dialog.
          // (No tooltip: it would also claim long-press.)
          GestureDetector(
            onLongPress: editServerAddress,
            child: IconButton(
              onPressed:
                  syncing ? null : syncExpenses,
              icon: syncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.sync,
                    ),
            ),
          ),
        ],
      ),

      body: SafeArea(
        child: IndexedStack(
          index: currentTab,
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                buildInputCard(),

                const SizedBox(height: 20),

                buildSyncCard(),

                if (notificationService.isSupported &&
                    !notificationsEnabled) ...[
                  const SizedBox(height: 12),
                  buildNotificationCard(),
                ],

                const SizedBox(height: 24),

                const Text(
                  'Expense Log',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 12),

                buildExpenseList(),
              ],
            ),

            SummaryScreen(logs: logs),
          ],
        ),
      ),

      bottomNavigationBar: NavigationBar(
        selectedIndex: currentTab,
        onDestinationSelected: (index) {
          setState(() {
            currentTab = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Expenses',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Summary',
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------
  // INPUT CARD
  // --------------------------------------------------

  Widget buildInputCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),

        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [
            const Text(
              'Add an expense',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: textController,
              maxLines: 4,

              decoration:
                  const InputDecoration(
                hintText:
                    'Example: spent 25 on tea break',

                border:
                    OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 12),

            if (selectedScreenshot != null)
              buildSelectedScreenshot(),

            OutlinedButton.icon(
              onPressed: pickScreenshot,

              icon: const Icon(
                Icons.image_outlined,
              ),

              label: const Text(
                'Add Screenshot',
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,

              child: FilledButton.icon(
                onPressed:
                    saving ? null : saveExpense,

                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.save,
                      ),

                label: Text(
                  saving
                      ? 'Saving...'
                      : 'Save Expense',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------
  // SYNC CARD
  // --------------------------------------------------

  Widget buildSyncCard() {
    final pendingCount = logs
        .where(
          (expense) =>
              expense['sync_status'] == 'pending' ||
              expense['sync_status'] == 'failed',
        )
        .length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),

        child: Row(
          children: [
            const Icon(
              Icons.cloud_outlined,
              size: 32,
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,

                children: [
                  const Text(
                    'Laptop Sync',
                    style: TextStyle(
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    pendingCount == 0
                        ? 'Everything is synced'
                        : '$pendingCount expense(s) waiting to sync',
                  ),
                ],
              ),
            ),

            FilledButton(
              onPressed:
                  syncing ? null : syncExpenses,

              onLongPress: editServerAddress,

              child: syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Sync',
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------
  // NOTIFICATION ACCESS CARD
  // --------------------------------------------------

  Widget buildNotificationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(
              Icons.notifications_active_outlined,
              size: 32,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    'Auto-log from notifications',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Read payment alerts from bank and '
                    'UPI apps. Nothing leaves your phone '
                    'except to your laptop on sync.',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed:
                  notificationService.openSettings,
              child: const Text('Enable'),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------
  // SELECTED SCREENSHOT
  // --------------------------------------------------

  Widget buildSelectedScreenshot() {
    return Padding(
      padding:
          const EdgeInsets.only(bottom: 12),

      child: Stack(
        children: [
          ClipRRect(
            borderRadius:
                BorderRadius.circular(12),

            child: Image.file(
              File(selectedScreenshot!),

              height: 160,
              width: double.infinity,

              fit: BoxFit.cover,
            ),
          ),

          Positioned(
            top: 8,
            right: 8,

            child: CircleAvatar(
              child: IconButton(
                icon: const Icon(
                  Icons.close,
                ),

                onPressed: () {
                  setState(() {
                    selectedScreenshot =
                        null;
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------
  // EXPENSE LIST
  // --------------------------------------------------

  Widget buildExpenseList() {
    if (loading) {
      return const Center(
        child: Padding(
          padding:
              EdgeInsets.all(30),

          child:
              CircularProgressIndicator(),
        ),
      );
    }

    if (logs.isEmpty) {
      return const Card(
        child: Padding(
          padding:
              EdgeInsets.all(30),

          child: Center(
            child: Text(
              'No expenses yet',
              style: TextStyle(
                color: Colors.grey,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: logs.map(
        (expense) {
          final screenshotPath =
              expense['screenshot_path']
                  as String?;

          final status =
              expense['sync_status']
                  as String;

          final rawText =
              expense['raw_text']
                  as String;

          final fromNotification =
              expense['source'] ==
                  'notification';

          return Card(
            margin:
                const EdgeInsets.only(
              bottom: 10,
            ),

            child: ListTile(
              leading: Icon(
                screenshotPath != null
                    ? Icons.image
                    : fromNotification
                        ? Icons.notifications_outlined
                        : Icons.receipt_long,
              ),

              title: Text(
                rawText.isEmpty
                    ? 'Screenshot expense'
                    : rawText,
              ),

              subtitle: Row(
                children: [
                  statusIcon(status),

                  const SizedBox(
                    width: 5,
                  ),

                  Text(status),
                ],
              ),

              trailing:
                  PopupMenuButton<String>(
                itemBuilder: (context) {
                  return [
                    if (screenshotPath !=
                        null)
                      const PopupMenuItem(
                        value: 'image',
                        child: Text(
                          'View screenshot',
                        ),
                      ),

                    const PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'Delete',
                      ),
                    ),
                  ];
                },

                onSelected: (value) {
                  if (value ==
                      'image') {
                    showScreenshot(
                      screenshotPath!,
                    );
                  }

                  if (value ==
                      'delete') {
                    deleteExpense(
                      expense,
                    );
                  }
                },
              ),
            ),
          );
        },
      ).toList(),
    );
  }

  // --------------------------------------------------
  // STATUS ICON
  // --------------------------------------------------

  Widget statusIcon(String status) {
    switch (status) {
      case 'synced':
        return const Icon(
          Icons.cloud_done,
          size: 18,
        );

      case 'failed':
        return const Icon(
          Icons.error_outline,
          size: 18,
        );

      case 'processing':
        return const Icon(
          Icons.sync,
          size: 18,
        );

      default:
        return const Icon(
          Icons.cloud_upload_outlined,
          size: 18,
        );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    textController.dispose();

    super.dispose();
  }
}