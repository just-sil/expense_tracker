import 'dart:io';

import 'package:flutter/material.dart';

import '../models/expense_entry.dart';
import '../util/categories.dart';
import '../util/format.dart';

/// What the user picked in the details sheet.
enum ExpenseAction { edit, delete, screenshot }

/// Amount as shown in lists: "₹24", "~₹120" (estimated), "—".
String amountLabel(ExpenseEntry e) {
  final amount = e.amount;
  if (amount == null) return '—';
  return e.isEstimated ? '~${formatMoney(amount)}' : formatMoney(amount);
}

/// One expense in a list.
class ExpenseTile extends StatelessWidget {
  final ExpenseEntry entry;
  final VoidCallback? onTap;

  /// Show the date instead of just the time (for lists that
  /// span several days without day headers).
  final bool showDate;

  const ExpenseTile({
    super.key,
    required this.entry,
    this.onTap,
    this.showDate = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final e = entry;

    final when = showDate
        ? '${dayLabel(e.spentAt)}, ${timeLabel(e.spentAt)}'
        : timeLabel(e.spentAt);

    final String status;
    Color? statusColor;
    if (e.isFailed) {
      status = 'Couldn\'t read · tap for details';
      statusColor = colors.error;
    } else if (e.isPending) {
      status = 'Waiting to sync · $when';
    } else {
      status = '${e.category} · $when';
    }

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: e.isFailed
          ? CategoryAvatar(
              category: null,
              overrideIcon: Icons.error_outline,
              overrideColor: colors.error,
            )
          : CategoryAvatar(category: e.category),
      title: Text(
        e.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          if (e.fromNotification) ...[
            Icon(
              Icons.notifications_none,
              size: 14,
              color: theme.textTheme.bodySmall?.color,
            ),
            const SizedBox(width: 3),
            if (e.sourceApp != null && !e.isFailed)
              Text('${e.sourceApp} · '),
          ],
          if (e.screenshotPath != null) ...[
            Icon(
              Icons.image_outlined,
              size: 14,
              color: theme.textTheme.bodySmall?.color,
            ),
            const SizedBox(width: 3),
          ],
          Expanded(
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: statusColor == null
                  ? null
                  : TextStyle(color: statusColor),
            ),
          ),
        ],
      ),
      trailing: Text(
        amountLabel(e),
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: e.isEstimated ? theme.textTheme.bodySmall?.color : null,
        ),
      ),
    );
  }
}

/// Bottom sheet with everything about one expense.
Future<ExpenseAction?> showExpenseDetails(
  BuildContext context,
  ExpenseEntry e,
) {
  return showModalBottomSheet<ExpenseAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final amount = e.amount;

      Widget row(IconData icon, String label, String value, {Color? color}) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: color ?? theme.hintColor),
              const SizedBox(width: 12),
              SizedBox(
                width: 84,
                child: Text(label, style: TextStyle(color: theme.hintColor)),
              ),
              Expanded(
                child: Text(value, style: TextStyle(color: color)),
              ),
            ],
          ),
        );
      }

      final String statusText;
      if (e.isFailed) {
        statusText = e.friendlyError;
      } else if (e.isPending) {
        statusText = 'Waiting to sync. The laptop will fill in the '
            'category and exact amount.';
      } else {
        statusText = 'Synced';
      }

      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  e.isFailed
                      ? CategoryAvatar(
                          category: null,
                          overrideIcon: Icons.error_outline,
                          overrideColor: colors.error,
                          radius: 24,
                        )
                      : CategoryAvatar(category: e.category, radius: 24),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          amount == null
                              ? 'No amount yet'
                              : (e.isEstimated ? '~' : '') + formatMoney(amount),
                          style: theme.textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(e.title, style: theme.textTheme.titleMedium),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              row(Icons.category_outlined, 'Category', e.category),
              row(
                Icons.event_outlined,
                'Date',
                '${dayLabel(e.spentAt)}, ${timeLabel(e.createdAt)}',
              ),
              if (e.rawText.isNotEmpty)
                row(Icons.notes, 'You wrote', e.rawText),
              row(
                e.fromNotification
                    ? Icons.notifications_none
                    : Icons.edit_note,
                'Added',
                e.fromNotification
                    ? 'From a ${e.sourceApp ?? 'payment'} notification'
                    : 'By you',
              ),
              row(
                e.isFailed
                    ? Icons.error_outline
                    : e.isPending
                        ? Icons.cloud_upload_outlined
                        : Icons.cloud_done_outlined,
                'Status',
                statusText,
                color: e.isFailed ? colors.error : null,
              ),
              if (e.screenshotPath != null) ...[
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(context, ExpenseAction.screenshot),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(e.screenshotPath!),
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(
                        height: 48,
                        child: Center(child: Text('Screenshot not found')),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.pop(context, ExpenseAction.delete),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.error,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          Navigator.pop(context, ExpenseAction.edit),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
