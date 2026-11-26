/// Shared bounds and parsers used by preflight and local feature stores.
abstract final class LocalDataValidation {
  static const maxPersistedCounter = 1 << 31;

  static bool isValidCalendarDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
    final parsed = DateTime.tryParse(value);
    return parsed != null &&
        parsed.year.toString().padLeft(4, '0') == value.substring(0, 4) &&
        parsed.month.toString().padLeft(2, '0') == value.substring(5, 7) &&
        parsed.day.toString().padLeft(2, '0') == value.substring(8, 10);
  }

  static bool isValidCounter(Object value) =>
      value is int && value >= 0 && value <= maxPersistedCounter;

  static bool isValidMaxOrbit(Object value) =>
      value is int && value >= 2 && value <= 5;

  /// Returns parsed stages, or null when the saved list is malformed.
  static Set<int>? parseCompletedStages(Object? value) {
    if (value is! List<String>) return null;
    final stages = <int>{};
    for (final item in value) {
      final stage = int.tryParse(item);
      if (stage == null || stage < 1 || stage > 5) return null;
      stages.add(stage);
    }
    return stages;
  }
}
