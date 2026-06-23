class WeightReading {
  final double weight;

  final DateTime timestamp;

  const WeightReading({required this.weight, required this.timestamp});

  @override
  String toString() {
    return 'WeightReading(weight: $weight, timestamp: $timestamp)';
  }
}
