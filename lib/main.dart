import 'package:flutter/material.dart';

import 'database/database_provider.dart';
import 'database/database.dart';
import 'services/ollama_service.dart';

final database = createDatabase();
final ollama = OllamaService();

void main() {
  runApp(const ExpenseTrackerApp());
}

class ExpenseTrackerApp extends StatelessWidget {
  const ExpenseTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Offline Expense Tracker',
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

class _ExpenseHomePageState extends State<ExpenseHomePage> {
  final TextEditingController messageController =
      TextEditingController();

  ParsedExpense? pendingExpense;

  List<Expense> expenses = [];

  bool analyzing = false;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    loadExpenses();
  }

  Future<void> loadExpenses() async {
    final data = await database.getAllExpenses();

    setState(() {
      expenses = data.reversed.toList();
    });
  }

  Future<void> analyzeExpense() async {
    final message = messageController.text.trim();

    if (message.isEmpty) return;

    setState(() {
      analyzing = true;
      pendingExpense = null;
    });

    try {
      final expense = await ollama.analyzeExpense(message);

      setState(() {
        pendingExpense = expense;
      });
    } catch (e) {
      showError(e.toString());
    } finally {
      setState(() {
        analyzing = false;
      });
    }
  }

  Future<void> saveExpense() async {
    final expense = pendingExpense;

    if (expense == null) return;

    setState(() {
      saving = true;
    });

    try {
      await database.addExpense(
        amount: expense.amount,
        category: expense.category,
        description: expense.description,
        date: expense.date,
      );

      messageController.clear();

      setState(() {
        pendingExpense = null;
      });

      await loadExpenses();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Expense saved'),
          ),
        );
      }
    } catch (e) {
      showError(e.toString());
    } finally {
      setState(() {
        saving = false;
      });
    }
  }

  void showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Expense Tracker',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 850,
          ),

          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              buildSummary(),

              const SizedBox(height: 24),

              buildInput(),

              const SizedBox(height: 20),

              if (pendingExpense != null)
                buildDetectedExpense(),

              const SizedBox(height: 30),

              buildRecentExpenses(),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildSummary() {
    final total = expenses.fold<double>(
      0,
      (sum, expense) => sum + expense.amount,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total recorded',
                    style: TextStyle(
                      color: Colors.grey,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    '₹${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'Transactions',
                  style: TextStyle(
                    color: Colors.grey,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  '${expenses.length}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget buildInput() {
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
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: messageController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText:
                    'Example: Spent ₹177 on food yesterday',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    analyzing ? null : analyzeExpense,
                icon: analyzing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(
                  analyzing
                      ? 'Analyzing...'
                      : 'Analyze with Qwen',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildDetectedExpense() {
    final expense = pendingExpense!;

    return Card(
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest,

      child: Padding(
        padding: const EdgeInsets.all(20),

        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome,
                ),

                const SizedBox(width: 8),

                const Text(
                  'Detected Expense',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            Text(
              '₹${expense.amount.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            buildDetail(
              Icons.category,
              'Category',
              expense.category,
            ),

            buildDetail(
              Icons.description,
              'Description',
              expense.description,
            ),

            buildDetail(
              Icons.calendar_today,
              'Date',
              expense.date,
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        pendingExpense = null;
                      });
                    },
                    child: const Text('Discard'),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: FilledButton(
                    onPressed:
                        saving ? null : saveExpense,
                    child: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget buildDetail(
    IconData icon,
    String title,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 10,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
          ),

          const SizedBox(width: 10),

          Text(
            '$title: ',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),

          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  Widget buildRecentExpenses() {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Expenses',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 12),

        if (expenses.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No expenses yet',
                  style: TextStyle(
                    color: Colors.grey,
                  ),
                ),
              ),
            ),
          ),

        ...expenses.map(
          (expense) => Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Icon(
                  getCategoryIcon(
                    expense.category,
                  ),
                ),
              ),

              title: Text(
                expense.description ??
                    expense.category,
              ),

              subtitle: Text(
                '${expense.category} • ${expense.date}',
              ),

              trailing: Text(
                '₹${expense.amount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  IconData getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'food':
        return Icons.restaurant;

      case 'transport':
        return Icons.directions_bus;

      case 'shopping':
        return Icons.shopping_bag;

      case 'bills':
        return Icons.receipt_long;

      case 'entertainment':
        return Icons.movie;

      case 'education':
        return Icons.school;

      case 'health':
        return Icons.health_and_safety;

      default:
        return Icons.payments;
    }
  }

  @override
  void dispose() {
    messageController.dispose();
    database.close();

    super.dispose();
  }
}