class SocketMessage {
  final String type;
  final Map<String, dynamic>? payload;

  SocketMessage({required this.type, this.payload});
}
