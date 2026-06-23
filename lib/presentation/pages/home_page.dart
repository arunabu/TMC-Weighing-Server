import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tmc_weighing_server/data/repositories/rs232_datasource_impl.dart';
import 'package:tmc_weighing_server/data/repositories/scale_port_detector_data_source_impl.dart';
import 'package:tmc_weighing_server/data/repositories/websocket_server_datasource_impl.dart';
import 'package:tmc_weighing_server/data/repositories/weighing_scale_repository_impl.dart';
import 'package:tmc_weighing_server/domain/repositories/weighing_scale_repository.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final WebSocketServerDataSourceImpl server = WebSocketServerDataSourceImpl();

  final TextEditingController _messageController = TextEditingController();
  late final WeighingScaleRepository repository;
  List<String> first50ScaleEntries = [];

  bool isCapturingScaleData = false;
  bool isRunning = false;

  String ipAddress = "Unknown";
  String rs232Status = "Disconnected";
  String rs232Port = "Unknown";

  final List<String> logs = [];

  @override
  void initState() {
    super.initState();

    repository = WeighingScaleRepositoryImpl(
      rs232: Rs232DataSourceImpl(),
      detector: ScalePortDetectorDataSourceImpl(),
    );

    _loadIpAddress();
  }

  Future<void> _loadIpAddress() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );

    final addresses = interfaces
        .expand((interface) => interface.addresses)
        .where(
          (address) =>
              address.type == InternetAddressType.IPv4 && !address.isLoopback,
        );

    final selectedAddress = addresses.firstWhere(
      _isPrivateIp,
      orElse: () =>
          addresses.isNotEmpty ? addresses.first : InternetAddress("0.0.0.0"),
    );

    setState(() {
      ipAddress = selectedAddress.address;
    });
  }

  bool _isPrivateIp(InternetAddress address) {
    final bytes = address.rawAddress;
    return bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168);
  }

  Future<void> _startServer() async {
    await server.startServer();

    server.messages.listen((message) {
      setState(() {
        logs.insert(0, message);
      });
    });

    setState(() {
      isRunning = true;
    });

    // await _startScale();
  }

  Future<void> _stopServer() async {
    await server.stopServer();

    setState(() {
      isRunning = false;
      rs232Status = "Disconnected";
      rs232Port = "Unknown";
    });
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    await server.send(message);

    setState(() {
      logs.insert(0, "Sent: $message");
      _messageController.clear();
    });
  }

  Future<void> _startScale() async {
    final scale = await repository.detectScale();

    if (scale == null) {
      setState(() {
        logs.insert(0, "Scale not found");
      });

      return;
    }

    setState(() {
      rs232Status = "Connected";
      rs232Port = scale.portName;
      logs.insert(0, "Scale connected on ${scale.portName}");
    });

    repository.startReading().listen((rawData) {
      setState(() {
        logs.insert(0, "SCALE: $rawData");
      });
    });
  }

  Future<void> _captureFirst50Entries() async {
    if (isCapturingScaleData) {
      return;
    }

    setState(() {
      isCapturingScaleData = true;
      first50ScaleEntries.clear();
    });

    final scale = await repository.detectScale();

    if (scale == null) {
      setState(() {
        isCapturingScaleData = false;
        logs.insert(0, "Scale not found");
      });

      return;
    }

    rs232Status = "Connected";
    rs232Port = scale.portName;

    final tempEntries = <String>[];
    StreamSubscription<String>? subscription;
    subscription = repository.startReading().listen((rawData) {
      if (tempEntries.length < 50) {
        tempEntries.add(rawData);
      }

      if (tempEntries.length >= 50) {
        subscription?.cancel();

        setState(() {
          first50ScaleEntries = List.from(tempEntries);

          logs.insert(0, "Captured first 50 scale entries");

          isCapturingScaleData = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("TMC Weighing Server")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Server Status",
                      style: Theme.of(context).textTheme.titleLarge,
                    ),

                    const SizedBox(height: 12),

                    Text(isRunning ? "Running" : "Stopped"),

                    const SizedBox(height: 8),

                    Text("ws://$ipAddress:8080"),

                    const SizedBox(height: 16),

                    Text(
                      "RS232 Status",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),

                    const SizedBox(height: 8),

                    Text("$rs232Status"),
                    const SizedBox(height: 4),
                    Text("Port: $rs232Port"),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: isRunning ? null : _startServer,
                    child: const Text("Start Server"),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: ElevatedButton(
                    onPressed: isRunning ? _stopServer : null,
                    child: const Text("Stop Server"),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                labelText: 'Outgoing message',
                hintText: 'Type a message to send over websocket',
                border: OutlineInputBorder(),
              ),
              enabled: isRunning,
              onSubmitted: (_) => _sendMessage(),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isRunning ? _sendMessage : null,
                child: const Text('Send Message'),
              ),
            ),

            const SizedBox(height: 20),

            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Logs",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _captureFirst50Entries,
                child: const Text("Capture First 50 Scale Entries"),
              ),
            ),
            const SizedBox(height: 20),

            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "First 50 Scale Entries",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),

            const SizedBox(height: 8),

            SizedBox(
              height: 200,
              child: Card(
                child: ListView.builder(
                  itemCount: first50ScaleEntries.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(first50ScaleEntries[index]),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: Card(
                child: ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(logs[index]),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
