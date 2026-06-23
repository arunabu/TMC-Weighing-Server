import 'package:tmc_weighing_server/domain/repositories/models/weighing_scale.dart';

abstract class WeighingScaleRepository {
  Future<WeighingScale?> detectScale();

  Stream<String> startReading();

  Future<void> stopReading();
}
