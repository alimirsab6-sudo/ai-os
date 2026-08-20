import 'package:ai_os/ai/model_provider/mock_model_provider.dart';
import 'package:ai_os/ai/model_provider/model_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mock provider returns a deterministic assistant response', () async {
    const provider = MockModelProvider(responseText: 'offline response');
    final result = await provider.generate(
      const ModelRequest(
        messages: [ModelMessage(role: ModelMessageRole.user, content: 'hello')],
      ),
    );

    expect(
      result.fold((value) => value.message.content, (_) => null),
      'offline response',
    );
  });
}

