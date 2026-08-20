import 'dart:convert';
import 'dart:io';

import 'package:ai_os/ai/model_provider/model_provider.dart';
import 'package:ai_os/core/result.dart';
import 'package:ai_os/ai/model_provider/ollama_model_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;

  tearDown(() async => server.close(force: true));

  test('sends Crony system prompt and returns local Ollama response', () async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      expect(body['model'], 'qwen3:4b');
      expect(body['think'], false);
      final messages = body['messages'] as List<dynamic>;
      expect(messages.first['role'], 'system');
      expect(messages.first['content'], contains('You are Crony'));
      expect(messages.last['content'], 'How are you?');
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'message': {
            'role': 'assistant',
            'content': 'I am doing well, Ali.',
          },
        }))
        ..close();
    });

    final provider = OllamaModelProvider(
      baseUrl: 'http://127.0.0.1:${server.port}',
    );
    final result = await provider.generate(const ModelRequest(
      messages: [
        ModelMessage(role: ModelMessageRole.user, content: 'How are you?'),
      ],
    ));

    expect(result.isSuccess, isTrue);
    final response = (result as Success<ModelResponse>).value;
    expect(response.message.content, 'I am doing well, Ali.');
    await provider.dispose();
  });
}




