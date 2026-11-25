/// Whether a player-domain document was present when it was loaded.
enum PlayerDataPresence { missing, present }

/// Result of loading a player-domain document.
///
/// A present document always carries its decoded value, including when that
/// value contains only default-valued fields. A missing document has no value.
class PlayerDataResult<T> {
  const PlayerDataResult.missing()
    : presence = PlayerDataPresence.missing,
      value = null;

  const PlayerDataResult.present(T this.value)
    : presence = PlayerDataPresence.present;

  final PlayerDataPresence presence;
  final T? value;

  bool get isMissing => presence == PlayerDataPresence.missing;
  bool get isPresent => presence == PlayerDataPresence.present;

  /// Returns the decoded value, throwing if the document was missing.
  T get requireValue {
    final value = this.value;
    if (value == null) {
      throw StateError('A missing player document has no value.');
    }
    return value;
  }
}
