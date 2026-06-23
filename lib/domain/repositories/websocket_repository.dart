import '../entities/socket_message.dart';

abstract class WebSocketRepository {
  Future<void> startServer();

  Future<void> stopServer();

  Stream<SocketMessage> get messages;

  Future<void> send(SocketMessage message);
}
