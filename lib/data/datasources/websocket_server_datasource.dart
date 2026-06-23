abstract class WebSocketServerDataSource {
  Future<void> startServer();

  Future<void> stopServer();

  Stream<String> get messages;

  Future<void> send(String message);
}
