import 'dart:async';

import 'app_event.dart';

abstract interface class EventPublisher {
  void publish(AppEvent event);
}

final class EventBus implements EventPublisher {
  final StreamController<AppEvent> _controller =
      StreamController<AppEvent>.broadcast(sync: true);

  Stream<AppEvent> get events => _controller.stream;

  @override
  void publish(AppEvent event) => _controller.add(event);

  Future<void> close() => _controller.close();
}
