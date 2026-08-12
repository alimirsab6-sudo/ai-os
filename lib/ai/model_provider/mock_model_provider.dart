import '../../core/result.dart';
import 'model_provider.dart';

/// Deterministic provider for development and offline tests.
final class MockModelProvider implements ModelProvider {
  const MockModelProvider({this.responseText = 'Mock response'});

  final String responseText;

  @override
  String get id => 'mock';

  @override
  Future<Result<ModelResponse>> generate(ModelRequest request) async {
    if (request.messages.isEmpty) {
      return const Result.failure(
        Failure('At least one message is required.', code: 'empty_request'),
      );
    }
    return Result.success(
      ModelResponse(
        message: ModelMessage(
          role: ModelMessageRole.assistant,
          content: responseText,
        ),
      ),
    );
  }
}
