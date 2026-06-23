import 'package:tmc_weighing_server/data/datasources/scale_port_detector_datasource.dart';

class ScalePortDetectorDataSourceImpl implements ScalePortDetectorDataSource {
  @override
  Future<String?> detectPort() async {
    return "COM4";
  }
}
