import '../repositories/websocket_repository.dart';

class StartServerUseCase {
  final WebSocketRepository repository;

  StartServerUseCase(this.repository);

  Future<void> call() async {
    await repository.startServer();
  }
}
