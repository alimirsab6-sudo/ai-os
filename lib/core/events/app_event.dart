abstract class AppEvent {
  const AppEvent({required this.type, required this.occurredAt});

  final String type;
  final DateTime occurredAt;
}

final class ApplicationEvent extends AppEvent {
  const ApplicationEvent({
    required super.type,
    required super.occurredAt,
    this.data = const {},
  });

  final Map<String, Object?> data;
}

