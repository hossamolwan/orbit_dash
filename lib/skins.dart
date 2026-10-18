import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

enum CosmeticCategory { ship, orbit, core }

enum CosmeticRarity { standard, premium }

enum ShipSkinId { defaultSkin, emerald, nebula, solar, supernova }

enum OrbitSkinId { defaultOrbit, aurora, solar }

enum CoreSkinId { defaultCore, crimson, glacier }

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
    price: 40,
  ),
  ShipSkin(
    id: ShipSkinId.nebula,
    name: 'Nebula',
    description: 'A shimmering nebula glow.',
    category: CosmeticCategory.ship,
    rarity: CosmeticRarity.standard,
    price: 100,
  ),
  ShipSkin(
    id: ShipSkinId.solar,
    name: 'Solar',
    description: 'A warm solar flare.',
    category: CosmeticCategory.ship,
    rarity: CosmeticRarity.premium,
    price: 250,
  ),
  ShipSkin(
    id: ShipSkinId.supernova,
    name: 'Supernova',
    description: 'A vivid supernova burst.',
    category: CosmeticCategory.ship,
    rarity: CosmeticRarity.premium,
    price: 500,
  ),
];

class OrbitSkin {
  const OrbitSkin({
    required this.id,
    required this.category,
    required this.name,
    required this.description,
    required this.rarity,
    required this.price,
  });

  final OrbitSkinId id;
  final CosmeticCategory category;
  String get itemId => 'orbit.${id.name}';
  final String name;
  final String description;
  final CosmeticRarity rarity;
  final int price;
}

const orbitSkins = <OrbitSkin>[
  OrbitSkin(
    id: OrbitSkinId.defaultOrbit,
    category: CosmeticCategory.orbit,
    name: 'Default Orbit',
    description: 'The original cyan orbital rings.',
    rarity: CosmeticRarity.standard,
    price: 0,
  ),
  OrbitSkin(
    id: OrbitSkinId.aurora,
    category: CosmeticCategory.orbit,
    name: 'Aurora Orbit',
    description: 'An emerald orbital glow.',
    rarity: CosmeticRarity.standard,
    price: 60,
  ),
  OrbitSkin(
    id: OrbitSkinId.solar,
    category: CosmeticCategory.orbit,
    name: 'Solar Orbit',
    description: 'A golden solar flare.',
    rarity: CosmeticRarity.premium,
    price: 275,
  ),
];

class CoreSkin {
  const CoreSkin({
    required this.id,
    required this.category,
    required this.name,
    required this.description,
    required this.rarity,
    required this.price,
  });

  final CoreSkinId id;
  final CosmeticCategory category;
  String get itemId => 'core.${id.name}';
  final String name;
  final String description;
  final CosmeticRarity rarity;
  final int price;
}

const coreSkins = <CoreSkin>[
  CoreSkin(
    id: CoreSkinId.defaultCore,
    category: CosmeticCategory.core,
    name: 'Default Core',
    description: 'The original nebula core.',
    rarity: CosmeticRarity.standard,
    price: 0,
  ),
  CoreSkin(
    id: CoreSkinId.crimson,
    category: CosmeticCategory.core,
    name: 'Crimson Core',
    description: 'A blazing crimson surface.',
    rarity: CosmeticRarity.standard,
    price: 75,
  ),
  CoreSkin(
    id: CoreSkinId.glacier,
    category: CosmeticCategory.core,
    name: 'Glacier Core',
    description: 'An icy blue core.',
    rarity: CosmeticRarity.premium,
    price: 300,
  ),
];

/// Stores appearance selections independently from wallet ownership.
class AppearanceStore {
  AppearanceStore({Future<SharedPreferences> Function()? loadPreferences})
    : _loadPreferences = loadPreferences ?? SharedPreferences.getInstance;

  static const selectedOrbitKey = 'orbit_dash_selected_orbit_v1';
  static const selectedCoreKey = 'orbit_dash_selected_core_v1';
  final Future<SharedPreferences> Function() _loadPreferences;
  OrbitSkinId _selectedOrbit = OrbitSkinId.defaultOrbit;
  CoreSkinId _selectedCore = CoreSkinId.defaultCore;
  Future<void> _tail = Future<void>.value();

  OrbitSkinId get selectedOrbit => _selectedOrbit;
  CoreSkinId get selectedCore => _selectedCore;
  Future<void> flush() => _tail;

  Future<void> load({Set<String> ownedItemIds = const {}}) =>
      _serialize(() async {
        final prefs = await _loadPreferences();
        final orbitValue = _readString(prefs, selectedOrbitKey);
        final coreValue = _readString(prefs, selectedCoreKey);
        final orbit = OrbitSkinId.values
            .where((id) => id.name == orbitValue)
            .firstOrNull;
        final core = CoreSkinId.values
            .where((id) => id.name == coreValue)
            .firstOrNull;
        _selectedOrbit =
            orbit != null &&
                (orbit == OrbitSkinId.defaultOrbit ||
                    ownedItemIds.contains('orbit.${orbit.name}'))
            ? orbit
            : OrbitSkinId.defaultOrbit;
        _selectedCore =
            core != null &&
                (core == CoreSkinId.defaultCore ||
                    ownedItemIds.contains('core.${core.name}'))
            ? core
            : CoreSkinId.defaultCore;
        if (_selectedOrbit.name != orbitValue) {
          await _save(prefs, selectedOrbitKey, _selectedOrbit.name);
        }
        if (_selectedCore.name != coreValue) {
          await _save(prefs, selectedCoreKey, _selectedCore.name);
        }
      });

  Future<bool> selectOrbit(
    OrbitSkinId id, {
    required Set<String> ownedItemIds,
  }) => _serialize(() async {
    if (id != OrbitSkinId.defaultOrbit &&
        !ownedItemIds.contains('orbit.${id.name}')) {
      return false;
    }
    final prefs = await _loadPreferences();
    await _save(prefs, selectedOrbitKey, id.name);
    _selectedOrbit = id;
    return true;
  });

  Future<bool> selectCore(CoreSkinId id, {required Set<String> ownedItemIds}) =>
      _serialize(() async {
        if (id != CoreSkinId.defaultCore &&
            !ownedItemIds.contains('core.${id.name}')) {
          return false;
        }
        final prefs = await _loadPreferences();
        await _save(prefs, selectedCoreKey, id.name);
        _selectedCore = id;
        return true;
      });

  String? _readString(SharedPreferences prefs, String key) {
    try {
      return prefs.getString(key);
    } on TypeError {
      return null;
    }
  }

  Future<void> _save(SharedPreferences prefs, String key, String value) async {
    if (!await prefs.setString(key, value)) {
      throw StateError('Appearance selection was not persisted.');
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
