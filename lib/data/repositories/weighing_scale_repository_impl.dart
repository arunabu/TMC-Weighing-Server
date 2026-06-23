import 'package:tmc_weighing_server/domain/repositories/models/weighing_scale.dart';

import '../../domain/repositories/weighing_scale_repository.dart';

import '../datasources/rs232_datasource.dart';
import '../datasources/scale_port_detector_datasource.dart';

class WeighingScaleRepositoryImpl implements WeighingScaleRepository {
  final Rs232DataSource rs232;

  final ScalePortDetectorDataSource detector;

  WeighingScaleRepositoryImpl({required this.rs232, required this.detector});

  @override
  Future<WeighingScale?> detectScale() async {
    final port = await detector.detectPort();

    if (port == null) {
      return null;
    }

    await rs232.connect(port);

    return WeighingScale(portName: port, isConnected: true);
  }

  @override
  Stream<String> startReading() {
    return rs232.stream;
  }

  @override
  Future<void> stopReading() {
    return rs232.disconnect();
  }
}
