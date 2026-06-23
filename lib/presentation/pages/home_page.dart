import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  final List<String> first50ScaleEntries = [];
  final List<String> logs = [];

  bool isCapturingScaleData = false;
  bool isRunning = false;

  String ipAddress = "Unknown";
  String rs232Status = "Disconnected";
  String rs232Port = "Unknown";

  StreamSubscription<String>? _scaleSubscription;

  @override
  void initState() {
    super.initState();
    repository = WeighingScaleRepositoryImpl(
      rs232: Rs232DataSourceImpl(),
      detector: ScalePortDetectorDataSourceImpl(),
    );
    _loadIpAddress();
    _addLog("Application Initialized");
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scaleSubscription?.cancel();
    server.stopServer();
    super.dispose();
  }

  void _addLog(String message) {
    final now = DateTime.now();
    final timeStr =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
    setState(() {
      logs.insert(0, "[$timeStr] $message");
    });
  }

  Future<void> _loadIpAddress() async {
    try {
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
      _addLog("Server IP Address loaded: $ipAddress");
    } catch (e) {
      _addLog("Error loading IP Address: $e");
    }
  }

  bool _isPrivateIp(InternetAddress address) {
    final bytes = address.rawAddress;
    return bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168);
  }

  Future<void> _startServer() async {
    try {
      await server.startServer();
      server.messages.listen((message) {
        _addLog(message);
      });

      setState(() {
        isRunning = true;
      });
      _addLog("WebSocket Server started on port 8080");
    } catch (e) {
      _addLog("Failed to start server: $e");
    }
  }

  Future<void> _stopServer() async {
    try {
      await server.stopServer();
      setState(() {
        isRunning = false;
        rs232Status = "Disconnected";
        rs232Port = "Unknown";
      });
      _addLog("WebSocket Server stopped");
    } catch (e) {
      _addLog("Failed to stop server: $e");
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    try {
      await server.send(message);
      _addLog("Sent: $message");
      _messageController.clear();
    } catch (e) {
      _addLog("Failed to send message: $e");
    }
  }

  Future<void> _captureFirst50Entries() async {
    if (isCapturingScaleData) return;

    setState(() {
      isCapturingScaleData = true;
      first50ScaleEntries.clear();
    });

    _addLog("Detecting scale connection...");
    final scale = await repository.detectScale();

    if (scale == null) {
      setState(() {
        isCapturingScaleData = false;
      });
      _addLog("Error: Scale not found");
      return;
    }

    setState(() {
      rs232Status = "Connected";
      rs232Port = scale.portName;
    });
    _addLog("Scale connected on ${scale.portName}. Capturing 50 readings...");

    await _scaleSubscription?.cancel();
    _scaleSubscription = repository.startReading().listen(
      (rawData) {
        if (first50ScaleEntries.length < 50) {
          setState(() {
            first50ScaleEntries.add(rawData);
          });
        }
        if (first50ScaleEntries.length >= 50) {
          _scaleSubscription?.cancel();
          setState(() {
            isCapturingScaleData = false;
          });
          _addLog("Successfully captured 50 scale entries.");
        }
      },
      onError: (err) {
        _addLog("Scale stream error: $err");
        setState(() {
          isCapturingScaleData = false;
        });
      },
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Copied to clipboard: $text"),
        behavior: SnackBarBehavior.floating,
        width: 300,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final String serverUrl = "ws://$ipAddress:8080";

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "TMC Weighing Control Hub",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh Server IP",
            onPressed: _loadIpAddress,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Narrow Screen / Mobile Layout
          if (constraints.maxWidth < 850) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStatusCards(serverUrl),
                  const SizedBox(height: 16),
                  _buildControlPanel(),
                  const SizedBox(height: 16),
                  _buildMessageConsole(),
                  const SizedBox(height: 16),
                  SizedBox(height: 350, child: _buildTerminalLogs(isDark)),
                  const SizedBox(height: 16),
                  SizedBox(height: 300, child: _buildScaleEntriesPanel(isDark)),
                ],
              ),
            );
          }

          // Desktop Dashboard Layout
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left column: Info & controls (360px wide)
                  SizedBox(
                    width: 360,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildStatusCards(serverUrl),
                        const SizedBox(height: 16),
                        _buildControlPanel(),
                        const SizedBox(height: 16),
                        _buildMessageConsole(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Right column: Terminals / log outputs (fixed heights)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 420,
                          child: _buildTerminalLogs(isDark),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 350,
                          child: _buildScaleEntriesPanel(isDark),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusCards(String serverUrl) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "System Health",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const Divider(),
            const SizedBox(height: 8),
            // Server status
            Row(
              children: [
                _buildStatusDot(isRunning),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "WebSocket Server",
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        isRunning ? "Running" : "Stopped",
                        style: TextStyle(
                          color: isRunning ? Colors.green : Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (isRunning) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        serverUrl,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16),
                      tooltip: "Copy Server URL",
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _copyToClipboard(serverUrl),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            // RS232 Port status
            Row(
              children: [
                _buildStatusDot(rs232Status == "Connected"),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "RS232 Interface",
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        rs232Status == "Connected"
                            ? "Connected (Port: $rs232Port)"
                            : "Disconnected",
                        style: TextStyle(
                          color: rs232Status == "Connected"
                              ? Colors.blue
                              : Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusDot(bool active) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? Colors.green : Colors.grey.shade400,
        boxShadow: active
            ? [
                BoxShadow(
                  color: Colors.green.withOpacity(0.4),
                  blurRadius: 8,
                  spreadRadius: 2,
                )
              ]
            : [],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Server Actions",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text("Start Server"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade50,
                      foregroundColor: Colors.green.shade800,
                    ),
                    onPressed: isRunning ? null : _startServer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.stop),
                    label: const Text("Stop Server"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade50,
                      foregroundColor: Colors.red.shade800,
                    ),
                    onPressed: isRunning ? _stopServer : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: isCapturingScaleData
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sensors),
                label: const Text("Capture 50 Scale Readings"),
                onPressed: isCapturingScaleData ? null : _captureFirst50Entries,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageConsole() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Outgoing WebSocket Console",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const Divider(),
            const SizedBox(height: 8),
            TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                labelText: 'Payload message',
                hintText: 'Type a message to client...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              enabled: isRunning,
              onSubmitted: (_) => _sendMessage(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.send),
                label: const Text('Send to Connected Client'),
                onPressed: isRunning ? _sendMessage : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTerminalLogs(bool isDark) {
    return Card(
      elevation: 4,
      color: const Color(0xFF141414),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.terminal, color: Colors.greenAccent, size: 20),
                    SizedBox(width: 8),
                    Text(
                      "WebSocket & Server Log",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text("Clear", style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () {
                    setState(() {
                      logs.clear();
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white10),
                ),
                child: logs.isEmpty
                    ? const Center(
                        child: Text(
                          "No active server logs.",
                          style: TextStyle(
                            color: Colors.grey,
                            fontFamily: 'monospace',
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: logs.length,
                        itemBuilder: (context, index) {
                          final logItem = logs[index];
                          Color textColor = Colors.white70;

                          if (logItem.contains("Sent:")) {
                            textColor = Colors.amberAccent;
                          } else if (logItem.contains("Received From Android:")) {
                            textColor = Colors.cyanAccent;
                          } else if (logItem.contains("WebSocket Server started") ||
                              logItem.contains("Server Started")) {
                            textColor = Colors.greenAccent;
                          } else if (logItem.contains("WebSocket Server stopped")) {
                            textColor = Colors.orangeAccent;
                          } else if (logItem.contains("SCALE:")) {
                            textColor = Colors.pinkAccent;
                          } else if (logItem.contains("Error") ||
                              logItem.contains("Failed")) {
                            textColor = Colors.redAccent;
                          }

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              logItem,
                              style: TextStyle(
                                color: textColor,
                                fontFamily: 'monospace',
                                fontSize: 13,
                              ),
                            ),
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

  Widget _buildScaleEntriesPanel(bool isDark) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.analytics_outlined,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Raw Scale Readings Window (${first50ScaleEntries.length}/50)",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (first50ScaleEntries.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        first50ScaleEntries.clear();
                      });
                    },
                    child: const Text("Clear Readings", style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            if (isCapturingScaleData) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: first50ScaleEntries.length / 50.0,
                backgroundColor: Colors.grey.shade200,
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                  ),
                ),
                child: first50ScaleEntries.isEmpty
                    ? Center(
                        child: Text(
                          isCapturingScaleData
                              ? "Capturing scale readings..."
                              : "No scale data captured. Click 'Capture 50 Scale Readings' to begin.",
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        itemCount: first50ScaleEntries.length,
                        itemBuilder: (context, index) {
                          return Container(
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: isDark
                                      ? Colors.white10
                                      : Colors.grey.shade100,
                                ),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  "#${(index + 1).toString().padLeft(2, '0')}",
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    first50ScaleEntries[index],
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              ],
                            ),
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
