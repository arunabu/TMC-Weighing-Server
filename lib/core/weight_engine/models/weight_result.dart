class WeightResult {
  final bool isStable;

  final double? stableWeight;

  final double? modeWeight;

  final double? medianWeight;

  final double variance;

  final double slope;

  const WeightResult({
    required this.isStable,
    required this.stableWeight,
    required this.modeWeight,
    required this.medianWeight,
    required this.variance,
    required this.slope,
  });

  @override
  String toString() {
    return '''
WeightResult(
  isStable: $isStable,
  stableWeight: $stableWeight,
  modeWeight: $modeWeight,
  medianWeight: $medianWeight,
  variance: $variance,
  slope: $slope
)
''';
  }
}
