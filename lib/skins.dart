import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

enum CosmeticCategory { ship, orbit, core, trail }

enum CosmeticRarity { standard, premium }

enum ShipSkinId {
  defaultSkin,
  emerald,
  nebula,
  solar,
  supernova,
  obsidian,
  prism,
  inferno,
  frostbite,
  phantom,
}

enum OrbitSkinId {
  defaultOrbit,
  aurora,
  solar,
  eclipse,
  plasma,
  ion,
  pulsar,
  voidOrbit,
  prism,
  radiant,
}

enum CoreSkinId {
  defaultCore,
  crimson,
  glacier,
  toxic,
  voidCore,
  magma,
  ocean,
  rose,
  stellar,
  quantum,
}

enum TrailSkinId {
  classic,
  aurora,
  solar,
  frost,
  phantom,
  electric,
  ember,
  stardust,
  toxic,
  spectrum,
}

extension OrbitSkinIdentity on OrbitSkinId {
  String get itemId =>
      this == OrbitSkinId.voidOrbit ? 'orbit.void' : 'orbit.$name';
}

extension CoreSkinIdentity on CoreSkinId {
  String get itemId => this == CoreSkinId.voidCore ? 'core.void' : 'core.$name';
}

enum ShipSilhouette {
  orb,
  diamond,
  nebula,
  solarStar,
  supernova,
  obsidian,
  prism,
  inferno,
  frostbite,
  phantom,
}

class ShipVisualStyle {
  const ShipVisualStyle({
    required this.color,
    required this.accent,
    required this.silhouette,
  });

  final int color;
  final int accent;
  final ShipSilhouette silhouette;
}

const shipVisualStyles = <ShipSkinId, ShipVisualStyle>{
  ShipSkinId.defaultSkin: ShipVisualStyle(
    color: 0xff60efff,
    accent: 0xffffffff,
    silhouette: ShipSilhouette.orb,
  ),
  ShipSkinId.emerald: ShipVisualStyle(
    color: 0xff66f0a5,
    accent: 0xffc0ffe0,
    silhouette: ShipSilhouette.diamond,
  ),
  ShipSkinId.nebula: ShipVisualStyle(
    color: 0xffbe86ff,
    accent: 0xffffffff,
    silhouette: ShipSilhouette.nebula,
  ),
  ShipSkinId.solar: ShipVisualStyle(
    color: 0xffffb54d,
    accent: 0xfffff0bb,
    silhouette: ShipSilhouette.solarStar,
  ),
  ShipSkinId.supernova: ShipVisualStyle(
    color: 0xffff6fcf,
    accent: 0xffffffff,
    silhouette: ShipSilhouette.supernova,
  ),
  ShipSkinId.obsidian: ShipVisualStyle(
    color: 0xff282333,
    accent: 0xffc39aff,
    silhouette: ShipSilhouette.obsidian,
  ),
  ShipSkinId.prism: ShipVisualStyle(
    color: 0xff75eaff,
    accent: 0xffff8ce8,
    silhouette: ShipSilhouette.prism,
  ),
  ShipSkinId.inferno: ShipVisualStyle(
    color: 0xffff573f,
    accent: 0xffffc14d,
    silhouette: ShipSilhouette.inferno,
  ),
  ShipSkinId.frostbite: ShipVisualStyle(
    color: 0xff8feaff,
    accent: 0xffffffff,
    silhouette: ShipSilhouette.frostbite,
  ),
  ShipSkinId.phantom: ShipVisualStyle(
    color: 0xff9c71e8,
    accent: 0xffe5ceff,
    silhouette: ShipSilhouette.phantom,
  ),
};

enum OrbitPattern {
  classic,
  aurora,
  solar,
  eclipse,
  plasma,
  ion,
  pulsar,
  voidOrbit,
  prism,
  radiant,
}

class OrbitVisualStyle {
  const OrbitVisualStyle({
    required this.glow,
    required this.stroke,
    required this.marker,
    required this.highlight,
    required this.pattern,
  });

  final int glow;
  final int stroke;
  final int marker;
  final int highlight;
  final OrbitPattern pattern;
}

const orbitVisualStyles = <OrbitSkinId, OrbitVisualStyle>{
  OrbitSkinId.defaultOrbit: OrbitVisualStyle(
    glow: 0xff50dff8,
    stroke: 0xff75dcf5,
    marker: 0xff8cecff,
    highlight: 0xffffffff,
    pattern: OrbitPattern.classic,
  ),
  OrbitSkinId.aurora: OrbitVisualStyle(
    glow: 0xff39ed9d,
    stroke: 0xff75f0b7,
    marker: 0xffa2ffd0,
    highlight: 0xffffffff,
    pattern: OrbitPattern.aurora,
  ),
  OrbitSkinId.solar: OrbitVisualStyle(
    glow: 0xffffa83b,
    stroke: 0xffffd078,
    marker: 0xffffe2a6,
    highlight: 0xffffffff,
    pattern: OrbitPattern.solar,
  ),
  OrbitSkinId.eclipse: OrbitVisualStyle(
    glow: 0xff643b9b,
    stroke: 0xff21172f,
    marker: 0xffd5b2ff,
    highlight: 0xffa36bde,
    pattern: OrbitPattern.eclipse,
  ),
  OrbitSkinId.plasma: OrbitVisualStyle(
    glow: 0xffe33dff,
    stroke: 0xffc86be8,
    marker: 0xffffb4ff,
    highlight: 0xffff69f5,
    pattern: OrbitPattern.plasma,
  ),
  OrbitSkinId.ion: OrbitVisualStyle(
    glow: 0xff20bfff,
    stroke: 0xff64e6ff,
    marker: 0xffd8fbff,
    highlight: 0xff72f5ff,
    pattern: OrbitPattern.ion,
  ),
  OrbitSkinId.pulsar: OrbitVisualStyle(
    glow: 0xffff55cf,
    stroke: 0xffffa0e7,
    marker: 0xffffffff,
    highlight: 0xffffd5f4,
    pattern: OrbitPattern.pulsar,
  ),
  OrbitSkinId.voidOrbit: OrbitVisualStyle(
    glow: 0xff382d70,
    stroke: 0xff100e24,
    marker: 0xff8779e8,
    highlight: 0xffdedaff,
    pattern: OrbitPattern.voidOrbit,
  ),
  OrbitSkinId.prism: OrbitVisualStyle(
    glow: 0xff78dfff,
    stroke: 0xffa290ff,
    marker: 0xffff8ddc,
    highlight: 0xffc7fff6,
    pattern: OrbitPattern.prism,
  ),
  OrbitSkinId.radiant: OrbitVisualStyle(
    glow: 0xffffd34f,
    stroke: 0xffffefad,
    marker: 0xffffffff,
    highlight: 0xfffffff0,
    pattern: OrbitPattern.radiant,
  ),
};

enum CoreDetail {
  classic,
  toxic,
  voidCore,
  magma,
  ocean,
  rose,
  stellar,
  quantum,
}

class CoreVisualStyle {
  const CoreVisualStyle({
    required this.glow,
    required this.gradient,
    required this.band,
    required this.crater,
    required this.craterRim,
    required this.highlight,
    required this.outline,
    required this.detail,
  });

  final int glow;
  final List<int> gradient;
  final int band;
  final int crater;
  final int craterRim;
  final int highlight;
  final int outline;
  final CoreDetail detail;
}

const coreVisualStyles = <CoreSkinId, CoreVisualStyle>{
  CoreSkinId.defaultCore: CoreVisualStyle(
    glow: 0xff455cff,
    gradient: [0xffd8a0ff, 0xff5f56bb, 0xff201d54, 0xff10152f],
    band: 0xffd9bdff,
    crater: 0xff17183e,
    craterRim: 0xffe4caff,
    highlight: 0xfff0d5ff,
    outline: 0xffa9a0ff,
    detail: CoreDetail.classic,
  ),
  CoreSkinId.crimson: CoreVisualStyle(
    glow: 0xffef412f,
    gradient: [0xffffbd8e, 0xffd94d3f, 0xff70242f, 0xff281521],
    band: 0xffffa47c,
    crater: 0xff481c2a,
    craterRim: 0xffffb28c,
    highlight: 0xffffc3a1,
    outline: 0xffff765f,
    detail: CoreDetail.classic,
  ),
  CoreSkinId.glacier: CoreVisualStyle(
    glow: 0xff46cfff,
    gradient: [0xffe2ffff, 0xff6bc9e8, 0xff24638f, 0xff101e3a],
    band: 0xffc1f7ff,
    crater: 0xff163c62,
    craterRim: 0xffd8ffff,
    highlight: 0xffd6ffff,
    outline: 0xff79e7ff,
    detail: CoreDetail.classic,
  ),
  CoreSkinId.toxic: CoreVisualStyle(
    glow: 0xff7dff32,
    gradient: [0xffe6ff8d, 0xff8bd334, 0xff31642c, 0xff13251e],
    band: 0xffc8ff42,
    crater: 0xff204322,
    craterRim: 0xffc0ff5c,
    highlight: 0xfff5ffcb,
    outline: 0xff9cff42,
    detail: CoreDetail.toxic,
  ),
  CoreSkinId.voidCore: CoreVisualStyle(
    glow: 0xff7b43d6,
    gradient: [0xff40366e, 0xff211b42, 0xff100d27, 0xff050711],
    band: 0xffab81ed,
    crater: 0xff080713,
    craterRim: 0xff9b6ee0,
    highlight: 0xffd2bdff,
    outline: 0xff8b62d3,
    detail: CoreDetail.voidCore,
  ),
  CoreSkinId.magma: CoreVisualStyle(
    glow: 0xffff481d,
    gradient: [0xffffc24e, 0xffe64a1f, 0xff722018, 0xff251018],
    band: 0xffff762e,
    crater: 0xff351116,
    craterRim: 0xffffb33e,
    highlight: 0xffffe28a,
    outline: 0xffff5d30,
    detail: CoreDetail.magma,
  ),
  CoreSkinId.ocean: CoreVisualStyle(
    glow: 0xff167ce0,
    gradient: [0xff74e5ff, 0xff1876bb, 0xff103c78, 0xff07152f],
    band: 0xff55d9ed,
    crater: 0xff08254a,
    craterRim: 0xff62d8ff,
    highlight: 0xffc2f5ff,
    outline: 0xff4baee8,
    detail: CoreDetail.ocean,
  ),
  CoreSkinId.rose: CoreVisualStyle(
    glow: 0xffff62b6,
    gradient: [0xffffd3ec, 0xffe76ea9, 0xff8c355f, 0xff321729],
    band: 0xffffa8d2,
    crater: 0xff4c2140,
    craterRim: 0xffffbfe0,
    highlight: 0xffffe9f4,
    outline: 0xffff85c5,
    detail: CoreDetail.rose,
  ),
  CoreSkinId.stellar: CoreVisualStyle(
    glow: 0xffffca54,
    gradient: [0xfffff4b5, 0xffd99249, 0xff70436e, 0xff171833],
    band: 0xffffdd80,
    crater: 0xff392751,
    craterRim: 0xffffe9a6,
    highlight: 0xffffffff,
    outline: 0xffffd66e,
    detail: CoreDetail.stellar,
  ),
  CoreSkinId.quantum: CoreVisualStyle(
    glow: 0xff6e71ff,
    gradient: [0xffb8f6ff, 0xff6478dd, 0xff493b9c, 0xff121536],
    band: 0xff83dfff,
    crater: 0xff24235e,
    craterRim: 0xffb78cff,
    highlight: 0xffe2faff,
    outline: 0xff9da7ff,
    detail: CoreDetail.quantum,
  ),
};

enum TrailPattern {
  classic,
  aurora,
  solar,
  frost,
  phantom,
  electric,
  ember,
  stardust,
  toxic,
  spectrum,
}

class TrailSkin {
  const TrailSkin({
    required this.id,
    required this.name,
    required this.description,
    required this.rarity,
    required this.price,
  });

  final TrailSkinId id;
  String get itemId => 'trail.${id.name}';
  final String name;
  final String description;
  final CosmeticRarity rarity;
  final int price;
  CosmeticCategory get category => CosmeticCategory.trail;
}

const trailSkins = <TrailSkin>[
  TrailSkin(
    id: TrailSkinId.classic,
    name: 'Classic Trail',
    description: 'The original cyan trail.',
    rarity: CosmeticRarity.standard,
    price: 0,
  ),
  TrailSkin(
    id: TrailSkinId.aurora,
    name: 'Aurora Trail',
    description: 'Soft emerald particles.',
    rarity: CosmeticRarity.standard,
    price: 100,
  ),
  TrailSkin(
    id: TrailSkinId.solar,
    name: 'Solar Trail',
    description: 'A warm golden flare.',
    rarity: CosmeticRarity.standard,
    price: 350,
  ),
  TrailSkin(
    id: TrailSkinId.frost,
    name: 'Frost Trail',
    description: 'Icy blue particles with crystalline sparks.',
    rarity: CosmeticRarity.standard,
    price: 450,
  ),
  TrailSkin(
    id: TrailSkinId.phantom,
    name: 'Phantom Trail',
    description: 'Violet spectral motes fade behind the ship.',
    rarity: CosmeticRarity.standard,
    price: 550,
  ),
  TrailSkin(
    id: TrailSkinId.electric,
    name: 'Electric Trail',
    description: 'Bright cyan particles flash with sharp sparks.',
    rarity: CosmeticRarity.standard,
    price: 700,
  ),
  TrailSkin(
    id: TrailSkinId.ember,
    name: 'Ember Trail',
    description: 'Warm red and orange embers drift behind.',
    rarity: CosmeticRarity.premium,
    price: 850,
  ),
  TrailSkin(
    id: TrailSkinId.stardust,
    name: 'Stardust Trail',
    description: 'Purple and blue particles sparkle like stars.',
    rarity: CosmeticRarity.premium,
    price: 1000,
  ),
  TrailSkin(
    id: TrailSkinId.toxic,
    name: 'Toxic Trail',
    description: 'Vivid green particles leave a bubbling wake.',
    rarity: CosmeticRarity.premium,
    price: 1150,
  ),
  TrailSkin(
    id: TrailSkinId.spectrum,
    name: 'Spectrum Trail',
    description: 'Particles split into a shifting spectrum.',
    rarity: CosmeticRarity.premium,
    price: 1350,
  ),
];

class TrailVisualStyle {
  const TrailVisualStyle({
    required this.color,
    required this.glowAlpha,
    required this.particleAlpha,
    required this.accentColor,
    required this.pattern,
  });

  final int color;
  final double glowAlpha;
  final double particleAlpha;
  final int accentColor;
  final TrailPattern pattern;
}

const trailVisualStyles = <TrailSkinId, TrailVisualStyle>{
  TrailSkinId.classic: TrailVisualStyle(
    color: 0xff60efff,
    glowAlpha: .16,
    particleAlpha: .10,
    accentColor: 0xffffffff,
    pattern: TrailPattern.classic,
  ),
  TrailSkinId.aurora: TrailVisualStyle(
    color: 0xff39ed9d,
    glowAlpha: .22,
    particleAlpha: .14,
    accentColor: 0xffbcffda,
    pattern: TrailPattern.aurora,
  ),
  TrailSkinId.solar: TrailVisualStyle(
    color: 0xffffa83b,
    glowAlpha: .28,
    particleAlpha: .18,
    accentColor: 0xffffe29b,
    pattern: TrailPattern.solar,
  ),
  TrailSkinId.frost: TrailVisualStyle(
    color: 0xff74dfff,
    glowAlpha: .24,
    particleAlpha: .16,
    accentColor: 0xffe6fcff,
    pattern: TrailPattern.frost,
  ),
  TrailSkinId.phantom: TrailVisualStyle(
    color: 0xff9a65e8,
    glowAlpha: .22,
    particleAlpha: .13,
    accentColor: 0xffe1c9ff,
    pattern: TrailPattern.phantom,
  ),
  TrailSkinId.electric: TrailVisualStyle(
    color: 0xff35eaff,
    glowAlpha: .3,
    particleAlpha: .2,
    accentColor: 0xffffffff,
    pattern: TrailPattern.electric,
  ),
  TrailSkinId.ember: TrailVisualStyle(
    color: 0xffff603c,
    glowAlpha: .25,
    particleAlpha: .17,
    accentColor: 0xffffc04f,
    pattern: TrailPattern.ember,
  ),
  TrailSkinId.stardust: TrailVisualStyle(
    color: 0xff8971ff,
    glowAlpha: .23,
    particleAlpha: .15,
    accentColor: 0xff62dcff,
    pattern: TrailPattern.stardust,
  ),
  TrailSkinId.toxic: TrailVisualStyle(
    color: 0xff8eff3d,
    glowAlpha: .26,
    particleAlpha: .18,
    accentColor: 0xffd6ff62,
    pattern: TrailPattern.toxic,
  ),
  TrailSkinId.spectrum: TrailVisualStyle(
    color: 0xfff36fff,
    glowAlpha: .26,
    particleAlpha: .18,
    accentColor: 0xff58f5ff,
    pattern: TrailPattern.spectrum,
  ),
};

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
  ShipSkin(
    id: ShipSkinId.obsidian,
    name: 'Obsidian',
    description: 'Graphite armor with a violet energy edge.',
    category: CosmeticCategory.ship,
    rarity: CosmeticRarity.premium,
    price: 650,
  ),
  ShipSkin(
    id: ShipSkinId.prism,
    name: 'Prism',
    description: 'A faceted body split by spectral color.',
    category: CosmeticCategory.ship,
    rarity: CosmeticRarity.premium,
    price: 800,
  ),
  ShipSkin(
    id: ShipSkinId.inferno,
    name: 'Inferno',
    description: 'A flame-shaped hull with molten light.',
    category: CosmeticCategory.ship,
    rarity: CosmeticRarity.premium,
    price: 950,
  ),
  ShipSkin(
    id: ShipSkinId.frostbite,
    name: 'Frostbite',
    description: 'A sharp crystal edged in arctic light.',
    category: CosmeticCategory.ship,
    rarity: CosmeticRarity.premium,
    price: 1100,
  ),
  ShipSkin(
    id: ShipSkinId.phantom,
    name: 'Phantom',
    description: 'A spectral crescent with a violet glow.',
    category: CosmeticCategory.ship,
    rarity: CosmeticRarity.premium,
    price: 1250,
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
  String get itemId => id.itemId;
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
    rarity: CosmeticRarity.standard,
    price: 200,
  ),
  OrbitSkin(
    id: OrbitSkinId.eclipse,
    category: CosmeticCategory.orbit,
    name: 'Eclipse',
    description: 'A shadowed violet orbit edged by a luminous crescent.',
    rarity: CosmeticRarity.premium,
    price: 500,
  ),
  OrbitSkin(
    id: OrbitSkinId.plasma,
    category: CosmeticCategory.orbit,
    name: 'Plasma',
    description: 'Jagged magenta energy arcs crackle along the orbit.',
    rarity: CosmeticRarity.premium,
    price: 600,
  ),
  OrbitSkin(
    id: OrbitSkinId.ion,
    category: CosmeticCategory.orbit,
    name: 'Ion',
    description: 'An electric blue ring with cyan sparks.',
    rarity: CosmeticRarity.premium,
    price: 750,
  ),
  OrbitSkin(
    id: OrbitSkinId.pulsar,
    category: CosmeticCategory.orbit,
    name: 'Pulsar',
    description: 'A stellar ring punctuated by bright pulses.',
    rarity: CosmeticRarity.premium,
    price: 900,
  ),
  OrbitSkin(
    id: OrbitSkinId.voidOrbit,
    category: CosmeticCategory.orbit,
    name: 'Void',
    description: 'A deep-space ring with pale violet markers.',
    rarity: CosmeticRarity.standard,
    price: 300,
  ),
  OrbitSkin(
    id: OrbitSkinId.prism,
    category: CosmeticCategory.orbit,
    name: 'Prism Orbit',
    description: 'Multitone markers refract around the ring.',
    rarity: CosmeticRarity.premium,
    price: 1200,
  ),
  OrbitSkin(
    id: OrbitSkinId.radiant,
    category: CosmeticCategory.orbit,
    name: 'Radiant',
    description: 'A bright celestial gold and white orbit.',
    rarity: CosmeticRarity.standard,
    price: 400,
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
  String get itemId => id.itemId;
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
    rarity: CosmeticRarity.standard,
    price: 300,
  ),
  CoreSkin(
    id: CoreSkinId.toxic,
    category: CosmeticCategory.core,
    name: 'Toxic Core',
    description: 'A neon green world alive with toxic bubbles.',
    rarity: CosmeticRarity.premium,
    price: 450,
  ),
  CoreSkin(
    id: CoreSkinId.voidCore,
    category: CosmeticCategory.core,
    name: 'Void Core',
    description: 'A dark cosmic sphere rimmed in violet.',
    rarity: CosmeticRarity.premium,
    price: 600,
  ),
  CoreSkin(
    id: CoreSkinId.magma,
    category: CosmeticCategory.core,
    name: 'Magma Core',
    description: 'Molten orange fissures cross a volcanic world.',
    rarity: CosmeticRarity.premium,
    price: 750,
  ),
  CoreSkin(
    id: CoreSkinId.ocean,
    category: CosmeticCategory.core,
    name: 'Ocean Core',
    description: 'Deep blue gradients and flowing currents.',
    rarity: CosmeticRarity.premium,
    price: 900,
  ),
  CoreSkin(
    id: CoreSkinId.rose,
    category: CosmeticCategory.core,
    name: 'Rose Core',
    description: 'Pink rose bands with luminous highlights.',
    rarity: CosmeticRarity.premium,
    price: 1050,
  ),
  CoreSkin(
    id: CoreSkinId.stellar,
    category: CosmeticCategory.core,
    name: 'Stellar Core',
    description: 'A radiant star suspended in a cosmic mantle.',
    rarity: CosmeticRarity.premium,
    price: 1200,
  ),
  CoreSkin(
    id: CoreSkinId.quantum,
    category: CosmeticCategory.core,
    name: 'Quantum Core',
    description: 'Geometric fields shift through blue and violet.',
    rarity: CosmeticRarity.premium,
    price: 1400,
  ),
];

/// Stores appearance selections independently from wallet ownership.
class AppearanceStore {
  AppearanceStore({Future<SharedPreferences> Function()? loadPreferences})
    : _loadPreferences = loadPreferences ?? SharedPreferences.getInstance;

  static const selectedOrbitKey = 'orbit_dash_selected_orbit_v1';
  static const selectedCoreKey = 'orbit_dash_selected_core_v1';
  static const selectedTrailKey = 'orbit_dash_selected_trail_v1';
  final Future<SharedPreferences> Function() _loadPreferences;
  OrbitSkinId _selectedOrbit = OrbitSkinId.defaultOrbit;
  CoreSkinId _selectedCore = CoreSkinId.defaultCore;
  TrailSkinId _selectedTrail = TrailSkinId.classic;
  Future<void> _tail = Future<void>.value();

  OrbitSkinId get selectedOrbit => _selectedOrbit;
  CoreSkinId get selectedCore => _selectedCore;
  TrailSkinId get selectedTrail => _selectedTrail;
  Future<void> flush() => _tail;

  Future<void> load({Set<String> ownedItemIds = const {}}) =>
      _serialize(() async {
        final prefs = await _loadPreferences();
        final orbitValue = _readString(prefs, selectedOrbitKey);
        final coreValue = _readString(prefs, selectedCoreKey);
        final trailValue = _readString(prefs, selectedTrailKey);
        final orbit = OrbitSkinId.values
            .where((id) => id.name == orbitValue)
            .firstOrNull;
        final core = CoreSkinId.values
            .where((id) => id.name == coreValue)
            .firstOrNull;
        final trail = TrailSkinId.values
            .where((id) => id.name == trailValue)
            .firstOrNull;
        _selectedOrbit =
            orbit != null &&
                (orbit == OrbitSkinId.defaultOrbit ||
                    ownedItemIds.contains(orbit.itemId))
            ? orbit
            : OrbitSkinId.defaultOrbit;
        _selectedCore =
            core != null &&
                (core == CoreSkinId.defaultCore ||
                    ownedItemIds.contains(core.itemId))
            ? core
            : CoreSkinId.defaultCore;
        _selectedTrail =
            trail != null &&
                (trail == TrailSkinId.classic ||
                    ownedItemIds.contains('trail.${trail.name}'))
            ? trail
            : TrailSkinId.classic;
        if (_selectedOrbit.name != orbitValue) {
          await _save(prefs, selectedOrbitKey, _selectedOrbit.name);
        }
        if (_selectedCore.name != coreValue) {
          await _save(prefs, selectedCoreKey, _selectedCore.name);
        }
        if (_selectedTrail.name != trailValue) {
          await _save(prefs, selectedTrailKey, _selectedTrail.name);
        }
      });

  Future<bool> selectOrbit(
    OrbitSkinId id, {
    required Set<String> ownedItemIds,
  }) => _serialize(() async {
    if (id != OrbitSkinId.defaultOrbit && !ownedItemIds.contains(id.itemId)) {
      return false;
    }
    final prefs = await _loadPreferences();
    await _save(prefs, selectedOrbitKey, id.name);
    _selectedOrbit = id;
    return true;
  });

  Future<bool> selectCore(CoreSkinId id, {required Set<String> ownedItemIds}) =>
      _serialize(() async {
        if (id != CoreSkinId.defaultCore && !ownedItemIds.contains(id.itemId)) {
          return false;
        }
        final prefs = await _loadPreferences();
        await _save(prefs, selectedCoreKey, id.name);
        _selectedCore = id;
        return true;
      });

  Future<bool> selectTrail(
    TrailSkinId id, {
    required Set<String> ownedItemIds,
  }) => _serialize(() async {
    if (id != TrailSkinId.classic &&
        !ownedItemIds.contains('trail.${id.name}')) {
      return false;
    }
    final prefs = await _loadPreferences();
    await _save(prefs, selectedTrailKey, id.name);
    _selectedTrail = id;
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
