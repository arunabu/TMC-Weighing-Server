import 'dart:convert';

import 'package:tmc_weighing_server/data/datasources/websocket_server_datasource.dart';

import '../../domain/entities/socket_message.dart';
import '../../domain/repositories/websocket_repository.dart';

class WebSocketRepositoryImpl implements WebSocketRepository {
  final WebSocketServerDataSource dataSource;

  WebSocketRepositoryImpl(this.dataSource);

  @override
  Future<void> startServer() => dataSource.startServer();

  @override
  Future<void> stopServer() => dataSource.stopServer();

  @override
  Stream<SocketMessage> get messages {
    return dataSource.messages.map((json) {
      try {
        final map = jsonDecode(json);

        return SocketMessage(type: map['type'], payload: map['payload']);
      } catch (e) {
        print("JSON ERROR: $e");
        print("RAW MESSAGE: $json");

        return SocketMessage(type: "raw", payload: {"message": json});
      }
    });
  }

  @override
  Future<void> send(SocketMessage message) {
    return dataSource.send(
      jsonEncode({"type": message.type, "payload": message.payload}),
    );
  }
}
