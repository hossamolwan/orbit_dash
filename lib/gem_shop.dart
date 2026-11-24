import 'package:flutter/foundation.dart';

/// Stable store products, including display-only approved price metadata.
@immutable
class GemPackage {
  const GemPackage({
    required this.id,
    required this.gems,
    this.bonusGems = 0,
    required this.displayOrder,
    this.displayPrice,
    this.featured = false,
  });

  final String id;
  final int gems;
  final int bonusGems;
  final int displayOrder;
  final String? displayPrice;
  final bool featured;
  int get totalGems => gems + bonusGems;
}

const gemPackages = <GemPackage>[
  GemPackage(
    id: 'gems.small',
    gems: 500,
    displayOrder: 0,
    displayPrice: r'$0.99',
  ),
  GemPackage(
    id: 'gems.medium',
    gems: 1200,
    bonusGems: 100,
    displayOrder: 1,
    displayPrice: r'$2.99',
  ),
  GemPackage(
    id: 'gems.large',
    gems: 2500,
    bonusGems: 350,
    displayOrder: 2,
    featured: true,
    displayPrice: r'$4.99',
  ),
  GemPackage(
    id: 'gems.mega',
    gems: 6000,
    bonusGems: 1200,
    displayOrder: 3,
    displayPrice: r'$9.99',
  ),
];

enum GemPurchaseStatus { unavailable }

class GemPurchaseResult {
  const GemPurchaseResult(this.status);
  final GemPurchaseStatus status;
}

/// Payment provider boundary. No local wallet mutation is permitted here.
abstract interface class GemPurchaseService {
  Future<GemPurchaseResult> purchase(GemPackage package);
}

/// Phase 1 implementation: safely reports that checkout is not available.
class UnavailableGemPurchaseService implements GemPurchaseService {
  const UnavailableGemPurchaseService();

  @override
  Future<GemPurchaseResult> purchase(GemPackage package) async =>
      const GemPurchaseResult(GemPurchaseStatus.unavailable);
}
