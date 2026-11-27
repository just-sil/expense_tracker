import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../database/local_database.dart';
import '../models/expense_entry.dart';
import '../services/notification_service.dart';
import '../services/sync_service.dart';
import '../state/app_settings.dart';
import '../util/format.dart';
import '../widgets/expense_tile.dart';
import 'settings_screen.dart';
import 'summary_screen.dart';

class ExpenseHomePage extends StatefulWidget {
  const ExpenseHomePage({super.key});

  @override
  State<ExpenseHomePage> createState() => _ExpenseHomePageState();
}

class _ExpenseHomePageState extends State<ExpenseHomePage>
    with WidgetsBindingObserver {
  final TextEditingController textController = TextEditingController();
  final FocusNode inputFocus = FocusNode();

  final ImagePicker imagePicker = ImagePicker();
  final SyncService syncService = SyncService();
  final NotificationService notificationService = NotificationService();

  bool notificationsEnabled = true;

  List<ExpenseEntry> entries = [];

  String? selectedScreenshot;

  bool loading = true;
  bool syncing = false;

  /// "Syncing 2 of 5…" while a sync runs.
  String? syncProgress;

  /// True while an automatic sync runs. It stays invisible
  /// until the laptop is found and entries start moving.
  bool silentRun = false;

  /// Whether to show sync activity in the UI.
  bool get showSyncing => syncing && (!silentRun || syncProgress != null);

  int currentTab = 0;

  /// Non-null while the search box is open.
  String? searchQuery;
  final TextEditingController searchController = TextEditingController();

  int get pendingCount => entries.where((e) => e.isPending).length;
  int get failedCount => entries.where((e) => e.isFailed).length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    textController.addListener(() => setState(() {}));
    _start();
  }

  Future<void> _start() async {
    await AppSettings.instance.load();
    await loadLogs();
    await importNotifications();
    await syncExpenses(silent: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pick up payments seen while the app was in the
    // background, re-check notification access after the
    // user returns from system settings, and quietly sync
    // if the laptop is around.
    if (state == AppLifecycleState.resumed) {
      importNotifications().then((_) => syncExpenses(silent: true));
    }
  }

  // --------------------------------------------------
  // DATA
  // --------------------------------------------------

  Future<void> loadLogs() async {
    final data = await LocalDatabase.instance.getExpenseLogs();
    if (!mounted) return;
    setState(() {
      entries = ExpenseEntry.fromRows(data);
      loading = false;
    });
  }

  Future<void> importNotifications() async {
    if (!notificationService.isSupported) return;

    try {
      final enabled = await notificationService.isEnabled();
      final added = await notificationService.importQueued();

      if (!mounted) return;
      setState(() => notificationsEnabled = enabled);

      if (added > 0) {
        await loadLogs();
        _toast('Added ${plural(added, 'payment')} from notifications');
      }
    } catch (e) {
      debugPrint('Notification import failed: $e');
    }
  }

  void _toast(String text, {SnackBarAction? action}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(text), action: action));
  }

  // --------------------------------------------------
  // ADD
  // --------------------------------------------------

  Future<void> pickScreenshot() async {
    final image = await imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    final directory = await getApplicationDocumentsDirectory();
    final screenshots = Directory('${directory.path}/screenshots');
    if (!await screenshots.exists()) {
      await screenshots.create(recursive: true);
    }

    final saved = await File(
      image.path,
    ).copy('${screenshots.path}/${DateTime.now().millisecondsSinceEpoch}.jpg');

    if (!mounted) return;
    setState(() => selectedScreenshot = saved.path);
    inputFocus.requestFocus();
  }

  Future<void> saveFromComposer() async {
    final text = textController.text.trim();

    if (text.isEmpty) {
      _toast(
        selectedScreenshot == null
            ? 'Type an expense, like 24 tea'
            : 'Add what it was for and the amount, like 120 lunch',
      );
      inputFocus.requestFocus();
      return;
    }

    final screenshot = selectedScreenshot;
    textController.clear();
    setState(() => selectedScreenshot = null);

    await addExpense(text, screenshotPath: screenshot);
  }

  /// Saves an entry, offers Undo, then syncs quietly once
  /// the Undo window has passed.
  Future<void> addExpense(String text, {String? screenshotPath}) async {
    HapticFeedback.lightImpact();
    final id = await LocalDatabase.instance.addExpenseLog(
      rawText: text,
      screenshotPath: screenshotPath,
    );
    await loadLogs();

    if (!mounted) return;

    final amount = amountFromText(text);
    var undone = false;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger
        .showSnackBar(
          SnackBar(
            content: Text(
              amount == null ? 'Saved' : 'Saved ${formatMoney(amount)}',
            ),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () async {
                undone = true;
                await LocalDatabase.instance.deleteExpense(id);
                await loadLogs();
                if (screenshotPath != null) {
                  final file = File(screenshotPath);
                  if (await file.exists()) await file.delete();
                }
              },
            ),
          ),
        )
        .closed
        .then((_) {
          if (!undone) syncExpenses(silent: true);
        });
  }

  // --------------------------------------------------
  // SYNC
  // --------------------------------------------------

  /// [silent] runs are automatic: no messages, and nothing
  /// on screen unless the laptop answers (then the list
  /// just updates).
  Future<void> syncExpenses({bool silent = false}) async {
    if (syncing) return;
    if (silent && pendingCount == 0) return;

    setState(() {
      syncing = true;
      silentRun = silent;
      syncProgress = null;
    });

    try {
      if (!silent) await importNotifications();

      final result = await syncService.syncPendingExpenses(
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() => syncProgress = 'Syncing ${done + 1} of $total…');
        },
      );

      if (silent) return;

      if (result.nothingToDo) {
        _toast('Everything is already synced');
      } else if (result.failed == 0) {
        _toast('Synced ${plural(result.synced, 'expense')}');
      } else {
        _toast(
          'Synced ${result.synced} · ${result.failed} couldn\'t be read. '
          'Tap one to see why.',
        );
      }
    } on LaptopNotFoundException {
      if (!silent) {
        _toast(
          'Laptop not found. Check it\'s on the same Wi-Fi '
          'or plugged in.',
          action: SnackBarAction(label: 'Settings', onPressed: openSettings),
        );
      }
    } catch (e) {
      if (!silent) _toast('Sync failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          syncing = false;
          syncProgress = null;
        });
        await loadLogs();
      }
    }
  }

  Future<void> openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          syncService: syncService,
          notificationService: notificationService,
        ),
      ),
    );
    importNotifications();
  }

  // --------------------------------------------------
  // EDIT / DELETE
  // --------------------------------------------------

  Future<void> openEntry(ExpenseEntry entry) async {
    final action = await showExpenseDetails(context, entry);
    if (!mounted || action == null) return;

    switch (action) {
      case ExpenseAction.edit:
        await editExpense(entry);
      case ExpenseAction.delete:
        await deleteExpense(entry);
      case ExpenseAction.screenshot:
        showScreenshot(entry.screenshotPath!);
    }
  }

  Future<void> editExpense(ExpenseEntry entry) async {
    final controller = TextEditingController(text: entry.rawText);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit expense'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.pop(context, controller.text.trim()),
          decoration: const InputDecoration(
            hintText: 'e.g. 60 lunch with Ali',
            helperText: 'The laptop reads it again on the next sync.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    // Not disposed here: the dialog's closing animation
    // still renders the TextField. It is garbage-collected.

    if (result == null || !mounted) return;

    if (result.isEmpty) {
      _toast('Text can\'t be empty');
      return;
    }
    if (result == entry.rawText) return;

    await LocalDatabase.instance.rewriteExpense(entry.id, result);
    await loadLogs();
    _toast('Updated');
    syncExpenses(silent: true);
  }

  /// Deletes at once and offers Undo. The screenshot file is
  /// removed only once Undo is no longer possible.
  Future<void> deleteExpense(ExpenseEntry entry) async {
    final row = Map<String, dynamic>.from(entry.row);

    setState(() => entries.removeWhere((e) => e.id == entry.id));
    await LocalDatabase.instance.deleteExpense(entry.id);

    if (!mounted) return;

    var undone = false;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger
        .showSnackBar(
          SnackBar(
            content: Text('Deleted ${entry.title}'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () async {
                undone = true;
                await LocalDatabase.instance.restoreExpense(row);
                await loadLogs();
              },
            ),
          ),
        )
        .closed
        .then((_) async {
          final path = entry.screenshotPath;
          if (undone || path == null) return;
          final file = File(path);
          if (await file.exists()) await file.delete();
        });

    await loadLogs();
  }

  void showScreenshot(String path) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Screenshot')),
          body: Center(
            child: InteractiveViewer(
              child: Image.file(File(path), fit: BoxFit.contain),
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
        leading: searchQuery == null
            ? null
            : IconButton(
                tooltip: 'Close search',
                icon: const Icon(Icons.arrow_back),
                onPressed: _closeSearch,
              ),
        title: searchQuery == null
            ? const Text(
                'Chillara',
                style: TextStyle(fontWeight: FontWeight.bold),
              )
            : TextField(
                controller: searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search expenses',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => searchQuery = v),
              ),
        actions: searchQuery != null
            ? [
                if (searchQuery!.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      searchController.clear();
                      setState(() => searchQuery = '');
                    },
                  ),
              ]
            : [
                if (currentTab == 0 && entries.isNotEmpty)
                  IconButton(
                    tooltip: 'Search',
                    icon: const Icon(Icons.search),
                    onPressed: () => setState(() => searchQuery = ''),
                  ),
                // Long-press is a shortcut to the laptop address.
                GestureDetector(
                  onLongPress: () => editLaptopAddress(context, syncService),
                  child: IconButton(
                    tooltip: 'Sync with laptop',
                    onPressed: syncing ? null : () => syncExpenses(),
                    icon: showSyncing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Badge(
                            isLabelVisible: pendingCount > 0,
                            label: Text('$pendingCount'),
                            child: const Icon(Icons.sync),
                          ),
                  ),
                ),
                IconButton(
                  tooltip: 'Settings',
                  onPressed: openSettings,
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: currentTab,
          children: [
            _buildExpensesTab(),
            SummaryScreen(entries: entries, onEntryTap: openEntry),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentTab,
        onDestinationSelected: (index) {
          FocusScope.of(context).unfocus();
          if (index != 0) _closeSearch();
          setState(() => currentTab = index);
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

  void _closeSearch() {
    searchController.clear();
    setState(() => searchQuery = null);
  }

  /// Matches the title, the original text or the category.
  bool _matches(ExpenseEntry e, String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return true;
    return e.title.toLowerCase().contains(q) ||
        e.rawText.toLowerCase().contains(q) ||
        e.category.toLowerCase().contains(q);
  }

  Widget _buildExpensesTab() {
    final searching = searchQuery != null;
    final visible = searching
        ? entries.where((e) => _matches(e, searchQuery!)).toList()
        : entries;

    final groups = <DateTime, List<ExpenseEntry>>{};
    final sorted = [...visible]..sort((a, b) => b.spentAt.compareTo(a.spentAt));
    for (final e in sorted) {
      groups.putIfAbsent(e.day, () => []).add(e);
    }

    final quick = _quickAddTexts();

    return RefreshIndicator(
      onRefresh: () => syncExpenses(),
      child: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverList.list(
              children: searching
                  ? [_buildSearchSummary(visible)]
                  : [
                      _buildComposer(),
                      if (quick.isNotEmpty) _buildQuickAdd(quick),
                      if (showSyncing || pendingCount > 0) ...[
                        const SizedBox(height: 12),
                        _buildSyncBanner(),
                      ],
                      if (notificationService.isSupported &&
                          !notificationsEnabled)
                        ValueListenableBuilder<bool>(
                          valueListenable:
                              AppSettings.instance.hideNotificationTip,
                          builder: (context, hidden, _) => hidden
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: _buildNotificationTip(),
                                ),
                        ),
                      const SizedBox(height: 8),
                    ],
            ),
          ),
          if (searching && visible.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Center(
                  child: Text(
                    searchQuery!.trim().isEmpty
                        ? 'Type to search by name, note or category'
                        : 'Nothing matches "${searchQuery!.trim()}"',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else if (loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (entries.isEmpty)
            SliverToBoxAdapter(child: _buildEmptyState())
          else
            for (final group in groups.entries) ...[
              SliverToBoxAdapter(
                child: _DayHeader(day: group.key, entries: group.value),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < group.value.length; i++) ...[
                          if (i > 0) const Divider(height: 1, indent: 72),
                          _buildDismissibleTile(group.value[i]),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _buildSearchSummary(List<ExpenseEntry> found) {
    if (searchQuery!.trim().isEmpty || found.isEmpty) {
      return const SizedBox.shrink();
    }
    final total = found.fold<double>(0, (s, e) => s + (e.amount ?? 0));
    final estimated = found.any((e) => e.isEstimated && e.amount != null);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Text(
        '${plural(found.length, 'match', 'matches')} · '
        '${estimated ? '~' : ''}${formatMoney(total)}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

  Widget _buildDismissibleTile(ExpenseEntry e) {
    final colors = Theme.of(context).colorScheme;

    return Dismissible(
      key: ValueKey('expense-${e.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: colors.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Icon(Icons.delete_outline, color: colors.onErrorContainer),
      ),
      onDismissed: (_) => deleteExpense(e),
      child: ExpenseTile(entry: e, onTap: () => openEntry(e)),
    );
  }

  /// Frequent manual entries from the last 60 days, for
  /// one-tap re-logging. Most used first.
  List<String> _quickAddTexts() {
    final cutoff = DateTime.now().subtract(const Duration(days: 60));
    final counts = <String, int>{};
    final display = <String, String>{};
    final lastUsed = <String, DateTime>{};

    for (final e in entries) {
      if (e.fromNotification || e.createdAt.isBefore(cutoff)) continue;
      final text = e.rawText.trim();
      if (text.isEmpty || text.length > 30 || amountFromText(text) == null) {
        continue;
      }
      final key = text.toLowerCase();
      counts[key] = (counts[key] ?? 0) + 1;
      display.putIfAbsent(key, () => text);
      final prev = lastUsed[key];
      if (prev == null || e.createdAt.isAfter(prev)) {
        lastUsed[key] = e.createdAt;
      }
    }

    final keys = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : lastUsed[b]!.compareTo(lastUsed[a]!);
      });

    return keys.take(6).map((k) => display[k]!).toList();
  }

  Widget _buildComposer() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = textController.text.trim();
    final amount = amountFromText(text);

    Widget? hint;
    if (text.isNotEmpty) {
      hint = amount == null
          ? Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: colors.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Add an amount, like "120 lunch"',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.error,
                    ),
                  ),
                ),
              ],
            )
          : Text(
              '${formatMoney(amount)} · category and date are filled in on sync',
              style: theme.textTheme.bodySmall,
            );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: textController,
                    focusNode: inputFocus,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => saveFromComposer(),
                    decoration: InputDecoration(
                      hintText: 'What did you spend?',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      suffixIcon: IconButton(
                        tooltip: 'Attach a screenshot',
                        icon: Icon(
                          selectedScreenshot == null
                              ? Icons.add_photo_alternate_outlined
                              : Icons.image,
                        ),
                        onPressed: pickScreenshot,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  tooltip: 'Save',
                  onPressed: saveFromComposer,
                  icon: const Icon(Icons.arrow_upward),
                ),
              ],
            ),
            if (selectedScreenshot != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(selectedScreenshot!),
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Screenshot attached')),
                  IconButton(
                    tooltip: 'Remove screenshot',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => selectedScreenshot = null),
                  ),
                ],
              ),
            ],
            if (hint != null) ...[const SizedBox(height: 4), hint],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAdd(List<String> texts) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: texts.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) => ActionChip(
            avatar: const Icon(Icons.replay, size: 16),
            label: Text(texts[i]),
            tooltip: 'Add "${texts[i]}" again',
            onPressed: () => addExpense(texts[i]),
          ),
        ),
      ),
    );
  }

  Widget _buildSyncBanner() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final failed = failedCount;
    final pending = pendingCount;

    final String text;
    if (showSyncing) {
      text = syncProgress ?? 'Looking for your laptop…';
    } else if (failed > 0 && failed == pending) {
      text = '${plural(failed, 'entry', 'entries')} couldn\'t be read';
    } else {
      text = failed > 0
          ? '$pending to sync · $failed couldn\'t be read'
          : '$pending waiting to sync';
    }

    return Card(
      margin: EdgeInsets.zero,
      color: failed > 0 && !showSyncing
          ? colors.errorContainer
          : colors.secondaryContainer,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
            child: Row(
              children: [
                Icon(
                  showSyncing
                      ? Icons.sync
                      : failed > 0
                      ? Icons.error_outline
                      : Icons.cloud_upload_outlined,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(text)),
                TextButton(
                  onPressed: syncing ? null : () => syncExpenses(),
                  child: Text(failed > 0 ? 'Retry' : 'Sync now'),
                ),
              ],
            ),
          ),
          if (showSyncing) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }

  Widget _buildNotificationTip() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.notifications_active_outlined),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Log UPI and bank payments automatically',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(left: 36, top: 4),
              child: Text(
                'Chillara reads payment alerts on this phone. '
                'They go only to your laptop on sync.',
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () =>
                      AppSettings.instance.setHideNotificationTip(true),
                  child: const Text('Not now'),
                ),
                TextButton(
                  onPressed: notificationService.openSettings,
                  child: const Text('Turn on'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
      child: Column(
        children: [
          Icon(
            Icons.currency_rupee,
            size: 56,
            color: theme.colorScheme.primary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 16),
          Text('No expenses yet', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Type what you spent the way you\'d say it: '
            '"24 tea", "petrol 500", "120 lunch yesterday". '
            'It\'s saved on your phone right away.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    textController.dispose();
    searchController.dispose();
    inputFocus.dispose();
    super.dispose();
  }
}

/// "Today ............ ₹553" above each day's card.
class _DayHeader extends StatelessWidget {
  final DateTime day;
  final List<ExpenseEntry> entries;

  const _DayHeader({required this.day, required this.entries});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = entries.fold<double>(0, (s, e) => s + (e.amount ?? 0));
    final estimated = entries.any((e) => e.isEstimated && e.amount != null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              dayLabel(day),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Text(
            '${estimated ? '~' : ''}${formatMoney(total)}',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.hintColor,
            ),
          ),
        ],
      ),
    );
  }
}
