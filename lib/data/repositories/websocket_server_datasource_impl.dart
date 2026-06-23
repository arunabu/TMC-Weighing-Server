import 'dart:async';
import 'dart:io';

import 'package:tmc_weighing_server/data/datasources/websocket_server_datasource.dart';

class WebSocketServerDataSourceImpl implements WebSocketServerDataSource {
  HttpServer? _server;

  WebSocket? _client;

  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  @override
  Stream<String> get messages => _controller.stream;

  @override
  Future<void> startServer() async {
    if (_server != null) {
      return;
    }

    _server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);

    _controller.add("Server Started On Port 8080");

    _server!.listen((HttpRequest request) async {
      final socket = await WebSocketTransformer.upgrade(
        request,
        compression: CompressionOptions.compressionOff,
      );

      _client = socket;

      print("CLIENT CONNECTED");

      socket.listen(
        (data) {
          print("DATA = $data");
          _controller.add("Received From Android: $data");
        },
        onDone: () {
          print("CLIENT DISCONNECTED");
        },
        onError: (e) {
          print("ERROR = $e");
        },
      );
    });
  }

  @override
  Future<void> send(String message) async {
    _client?.add(message);
  }

  @override
  Future<void> stopServer() async {
    await _server?.close(force: true);

    _server = null;

    _controller.add("Server Stopped");
  }
}
