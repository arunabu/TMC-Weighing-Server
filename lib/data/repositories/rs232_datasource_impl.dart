import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import '../datasources/rs232_datasource.dart';

class Rs232DataSourceImpl implements Rs232DataSource {
  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _subscription;

  String _buffer = '';

  @override
  Stream<String> get stream => _controller.stream;

  @override
  Future<void> connect(String portName) async {
    if (_port != null && _port!.isOpen) {
      return;
    }

    print('[RS232] Connecting to $portName');

    _port = SerialPort(portName);

    final opened = _port!.openReadWrite();

    if (!opened) {
      throw Exception('Unable to open serial port $portName');
    }

    final config = SerialPortConfig();

    config.baudRate = 9600;
    config.bits = 8;
    config.stopBits = 1;
    config.parity = SerialPortParity.none;

    _port!.config = config;

    _reader = SerialPortReader(_port!);

    _startListening();

    print('[RS232] Connected to $portName');
  }

  void _startListening() {
    _subscription = _reader!.stream.listen(
      (Uint8List data) {
        final incoming = String.fromCharCodes(data);

        _buffer += incoming;

        _extractLines();
      },
      onError: (error) {
        print('[RS232] Error: $error');
      },
      onDone: () {
        print('[RS232] Reader stopped');
      },
    );
  }

  void _extractLines() {
    while (true) {
      int lineBreakIndex = _buffer.indexOf('\n');

      if (lineBreakIndex == -1) {
        break;
      }

      String line = _buffer.substring(0, lineBreakIndex);

      _buffer = _buffer.substring(lineBreakIndex + 1);

      line = line.replaceAll('\r', '').trim();

      if (line.isEmpty) {
        continue;
      }

      print('[RS232] RAW => $line');

      _controller.add(line);
    }
  }

  @override
  Future<void> disconnect() async {
    print('[RS232] Disconnecting');

    await _subscription?.cancel();

    _reader = null;

    if (_port != null) {
      try {
        if (_port!.isOpen) {
          _port!.close();
        }
      } catch (_) {}
    }

    _port = null;

    _buffer = '';

    print('[RS232] Disconnected');
  }

  Future<void> dispose() async {
    await disconnect();
    await _controller.close();
  }
}
