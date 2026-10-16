import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

enum ShipSkinId { defaultSkin, emerald, nebula, solar, supernova }

class ShipSkin {
  const ShipSkin({
    required this.id,
    required this.name,
    required this.description,
    required this.gemRequirement,
    required this.stageRequirement,
  });

  final ShipSkinId id;
  final String name;
  final String description;
  final int? gemRequirement;
  final int? stageRequirement;
}

const shipSkins = <ShipSkin>[
  ShipSkin(
    id: ShipSkinId.defaultSkin,
    name: 'Default',
    description: 'The original orbital glow.',
    gemRequirement: null,
    stageRequirement: null,
  ),
  ShipSkin(
    id: ShipSkinId.emerald,
    name: 'Emerald',
    description: 'Collect 25 lifetime gems.',
    gemRequirement: 25,
    stageRequirement: null,
  ),
  ShipSkin(
    id: ShipSkinId.nebula,
    name: 'Nebula',
    description: 'Collect 75 lifetime gems.',
    gemRequirement: 75,
    stageRequirement: null,
  ),
  ShipSkin(
    id: ShipSkinId.solar,
    name: 'Solar',
    description: 'Complete Stage 3.',
    gemRequirement: null,
    stageRequirement: 3,
  ),
  ShipSkin(
    id: ShipSkinId.supernova,
    name: 'Supernova',
    description: 'Complete Stage 5.',
    gemRequirement: null,
    stageRequirement: 5,
  ),
];

class SkinStore {
  SkinStore({Future<SharedPreferences> Function()? loadPreferences})
    : _loadPreferences = loadPreferences ?? SharedPreferences.getInstance;

  static const unlockedSkinsKey = 'orbit_dash_unlocked_skins_v1';
  static const selectedSkinKey = 'orbit_dash_selected_skin_v1';

  final Future<SharedPreferences> Function() _loadPreferences;
  final Set<ShipSkinId> _unlocked = {ShipSkinId.defaultSkin};
  ShipSkinId _selected = ShipSkinId.defaultSkin;
  Future<void> _tail = Future<void>.value();

  Set<ShipSkinId> get unlockedSkins => Set.unmodifiable(_unlocked);
  ShipSkinId get selectedSkin => _selected;
  bool isUnlocked(ShipSkinId id) => _unlocked.contains(id);
  Future<void> flush() => _tail;

  Future<void> load({
    required int lifetimeGems,
    required Set<int> completedStages,
  }) => _serialize(() async {
    final preferences = await _loadPreferences();
    final saved = _readUnlocked(preferences);
    _unlocked
      ..clear()
      ..add(ShipSkinId.defaultSkin)
      ..addAll(saved);
    _unlockEligible(lifetimeGems, completedStages);
    final selectedValue = _readSelected(preferences);
    ShipSkinId? selectedId;
    for (final id in ShipSkinId.values) {
      if (id.name == selectedValue) selectedId = id;
    }
    _selected = selectedId != null && _unlocked.contains(selectedId)
        ? selectedId
        : ShipSkinId.defaultSkin;
    await _save(preferences);
  });

  Future<void> updateProgress({
    required int lifetimeGems,
    required Set<int> completedStages,
  }) => _serialize(() async {
    final preferences = await _loadPreferences();
    _unlockEligible(lifetimeGems, completedStages);
    await _save(preferences);
  });

  Future<bool> select(ShipSkinId id) => _serialize(() async {
    if (!_unlocked.contains(id)) return false;
    final preferences = await _loadPreferences();
    _selected = id;
    await preferences.setString(selectedSkinKey, id.name);
    return true;
  });

  Future<void> _save(SharedPreferences preferences) async {
    await preferences.setStringList(
      unlockedSkinsKey,
      _unlocked.map((id) => id.name).toList()..sort(),
    );
    if (!_unlocked.contains(_selected)) _selected = ShipSkinId.defaultSkin;
    await preferences.setString(selectedSkinKey, _selected.name);
  }

  void _unlockEligible(int lifetimeGems, Set<int> completedStages) {
    for (final skin in shipSkins) {
      final gemUnlocked =
          skin.gemRequirement != null && lifetimeGems >= skin.gemRequirement!;
      final stageUnlocked =
          skin.stageRequirement != null &&
          completedStages.contains(skin.stageRequirement);
      if (gemUnlocked || stageUnlocked) _unlocked.add(skin.id);
    }
  }

  Set<ShipSkinId> _readUnlocked(SharedPreferences preferences) {
    try {
      final ids = preferences.getStringList(unlockedSkinsKey) ?? const [];
      return ShipSkinId.values.where((id) => ids.contains(id.name)).toSet();
    } on TypeError {
      return {};
    }
  }

  String? _readSelected(SharedPreferences preferences) {
    try {
      return preferences.getString(selectedSkinKey);
    } on TypeError {
      return null;
    }
  }

  Future<T> _serialize<T>(Future<T> Function() action) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      return await action();
    } finally {
      done.complete();
    }
  }
}
