class WeightParser {
  double? parse(String rawData) {
    final regex = RegExp(r'(\d+\.\d+)');

    final match = regex.firstMatch(rawData);

    if (match == null) {
      return null;
    }

    return double.tryParse(match.group(1)!);
  }
}
