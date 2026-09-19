import 'dart:convert';
import 'package:http/http.dart' as http;

class ParsedExpense {
  final double amount;
  final String category;
  final String description;
  final String date;

  ParsedExpense({
    required this.amount,
    required this.category,
    required this.description,
    required this.date,
  });
}

class OllamaService {
  static const String apiUrl =
      'http://192.168.68.121:11434/api/chat';

  Future<ParsedExpense> analyzeExpense(String message) async {
    final now = DateTime.now();

    final currentDate =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    final response = await http.post(
      Uri.parse(apiUrl),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'qwen3:8b',
        'stream': false,
        'think': false,
        'messages': [
          {
            'role': 'system',
            'content': '''
You are an expense extraction system.

Today's date is $currentDate.

Extract the expense from the user's message.

Return ONLY valid JSON.
Do not use markdown.
Do not explain anything.

Required format:

{
  "amount": 0,
  "category": "Food",
  "description": "string",
  "date": "YYYY-MM-DD"
}

Allowed categories:
Food
Transport
Shopping
Bills
Entertainment
Education
Health
Other

Rules:
- amount must be a number
- date must be YYYY-MM-DD
- Resolve words like today, yesterday and tomorrow using today's date
- If the category is unclear, use Other
- Keep the description short
''',
          },
          {
            'role': 'user',
            'content': message,
          },
        ],
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Ollama returned ${response.statusCode}: ${response.body}',
      );
    }

    final data = jsonDecode(response.body);

    String content = data['message']['content'];

    // Remove markdown code fences if Qwen happens to add them.
    content = content
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();

    // Find the JSON object if Qwen adds any unwanted text.
    final start = content.indexOf('{');
    final end = content.lastIndexOf('}');

    if (start == -1 || end == -1 || end <= start) {
      throw Exception(
        'Qwen did not return valid JSON:\n$content',
      );
    }

    content = content.substring(start, end + 1);

    final json = jsonDecode(content);

    return ParsedExpense(
      amount: (json['amount'] as num).toDouble(),
      category: json['category'].toString(),
      description: json['description'].toString(),
      date: json['date'].toString(),
    );
  }
}