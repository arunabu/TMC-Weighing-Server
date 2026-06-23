abstract class Rs232DataSource {
  Future<void> connect(String portName);

  Stream<String> get stream;

  Future<void> disconnect();
}
