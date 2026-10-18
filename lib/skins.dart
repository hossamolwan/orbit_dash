import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

enum CosmeticCategory { ship }

enum CosmeticRarity { standard, premium }

enum ShipSkinId { defaultSkin, emerald, nebula, solar, supernova }

class ShipSkin {
  const ShipSkin({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.rarity,
    required this.price,
  });
  final ShipSkinId id;
  String get itemId => 'ship.${id.name}';
  final String name;
  final String description;
  final CosmeticCategory category;
  final CosmeticRarity rarity;
  final int price;
}

/// Central catalog. New cosmetic categories can join this catalog later.
const shipSkins = <ShipSkin>[
  ShipSkin(
    id: ShipSkinId.defaultSkin,
    name: 'Default',
    description: 'The original orbital glow.',
    category: CosmeticCategory.ship,
    rarity: CosmeticRarity.standard,
    price: 0,
  ),
  ShipSkin(
    id: ShipSkinId.emerald,
    name: 'Emerald',
    description: 'A bright emerald trail.',
    category: CosmeticCategory.ship,
    rarity: CosmeticRarity.standard,
    price: 25,
  ),
  ShipSkin(
    id: ShipSkinId.nebula,
    name: 'Nebula',
    description: 'A shimmering nebula glow.',
    category: CosmeticCategory.ship,
    rarity: CosmeticRarity.standard,
    price: 75,
  ),
  ShipSkin(
    id: ShipSkinId.solar,
    name: 'Solar',
    description: 'A warm solar flare.',
    category: CosmeticCategory.ship,
    rarity: CosmeticRarity.premium,
    price: 150,
  ),
  ShipSkin(
    id: ShipSkinId.supernova,
    name: 'Supernova',
    description: 'A vivid supernova burst.',
    category: CosmeticCategory.ship,
    rarity: CosmeticRarity.premium,
    price: 300,
  ),
];

class SkinStore {
  SkinStore({Future<SharedPreferences> Function()? loadPreferences})
    : _loadPreferences = loadPreferences ?? SharedPreferences.getInstance;

  // Versioned keys intentionally ignore historical unlock and selection data.
  static const selectedSkinKey = 'orbit_dash_selected_skin_v2';
  final Future<SharedPreferences> Function() _loadPreferences;
  ShipSkinId _selected = ShipSkinId.defaultSkin;
  Future<void> _tail = Future<void>.value();
  ShipSkinId get selectedSkin => _selected;
  Future<void> flush() => _tail;

  Future<void> load({Set<String> ownedItemIds = const {'ship.defaultSkin'}}) =>
      _serialize(() async {
        final prefs = await _loadPreferences();
        String? value;
        try {
          value = prefs.getString(selectedSkinKey);
        } on TypeError {
          // Treat malformed selection data as an unequipped item.
        }
        final owned = {'ship.defaultSkin', ...ownedItemIds};
        final id = ShipSkinId.values
            .where((item) => item.name == value)
            .firstOrNull;
        _selected = id != null && owned.contains('ship.${id.name}')
            ? id
            : ShipSkinId.defaultSkin;
        if (_selected.name != value) {
          final saved = await prefs.setString(selectedSkinKey, _selected.name);
          if (!saved) throw StateError('Skin selection was not persisted.');
        }
      });

  Future<bool> select(ShipSkinId id, {required Set<String> ownedItemIds}) =>
      _serialize(() async {
        if (!ownedItemIds.contains('ship.${id.name}')) return false;
        final prefs = await _loadPreferences();
        final saved = await prefs.setString(selectedSkinKey, id.name);
        if (!saved) throw StateError('Skin selection was not persisted.');
        _selected = id;
        return true;
      });

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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
