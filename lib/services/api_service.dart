import 'dart:convert';
import 'package:http/http.dart' as http;

class Expense {
  final int id;
  final double amount;
  final String category;
  final String description;
  final String date;
  final String createdAt;

  Expense({
    required this.id,
    required this.amount,
    required this.category,
    required this.description,
    required this.date,
    required this.createdAt,
  });

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: json['id'],
      amount: (json['amount'] as num).toDouble(),
      category: json['category'],
      description: json['description'] ?? '',
      date: json['date'],
      createdAt: json['created_at'],
    );
  }
}

class ApiService {
  // Flask backend
  static const String baseUrl = 'http://192.168.68.121:5000/api';

  /// Get all expenses
  Future<List<Expense>> getExpenses() async {
    final response = await http.get(
      Uri.parse('$baseUrl/expenses'),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load expenses: ${response.statusCode}',
      );
    }

    final List<dynamic> data = jsonDecode(response.body);

    return data
        .map((json) => Expense.fromJson(json))
        .toList();
  }

  /// Add an expense
  Future<Expense> addExpense({
    required double amount,
    required String category,
    required String description,
    required String date,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/expenses'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'amount': amount,
        'category': category,
        'description': description,
        'date': date,
      }),
    );

    if (response.statusCode != 201) {
      throw Exception(
        'Failed to save expense: ${response.statusCode}\n'
        '${response.body}',
      );
    }

    final data = jsonDecode(response.body);

    // Backend currently returns only id/message.
    // Fetch the newly saved expense from the server.
    final expenses = await getExpenses();

    return expenses.firstWhere(
      (expense) => expense.id == data['id'],
    );
  }
}