import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiService {
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;
  GeminiService._internal();

  // API key must not be committed. Set it via dart-define or a secure config.
  static const _apiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  Future<String> fetchGeminiWithRetry({
    required String prompt,
    required String systemPrompt,
    int retries = 5,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception(
          'Gemini API key not configured. Use --dart-define=GEMINI_API_KEY=your_key');
    }

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=$_apiKey',
    );

    final payload = {
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'systemInstruction': {
        'parts': [
          {'text': systemPrompt}
        ]
      }
    };

    for (int i = 0; i < retries; i++) {
      try {
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: json.encode(payload),
        );

        if (response.statusCode == 200) {
          final result = json.decode(response.body);
          final candidates = result['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final content = candidates[0]['content'];
            if (content != null) {
              final parts = content['parts'] as List?;
              if (parts != null && parts.isNotEmpty) {
                final text = parts[0]['text'] as String?;
                if (text != null) {
                  return text.trim();
                }
              }
            }
          }
          throw Exception('Invalid Gemini API response structure');
        } else {
          throw Exception(
              'HTTP Error ${response.statusCode}: ${response.body}');
        }
      } catch (e) {
        print('Gemini API attempt $i failed: $e');
        if (i == retries - 1) {
          return "Me oracle broken. Try later.";
        }
        // Exponential backoff
        await Future.delayed(Duration(seconds: (1 << i)));
      }
    }
    return "Me oracle broken. Try later.";
  }
}
