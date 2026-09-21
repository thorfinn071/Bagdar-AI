import 'corridor_candidate.dart';

enum SafetyActionKind {
  continueForward,
  adjustLeft,
  adjustRight,
  holdAndScan,
  stopNow,
}

enum SafetyPriority { p3Information, p2Degraded, p1Correction, p0Emergency }

enum SafetyActionDelivery { primary, shadow }

/// The only user-action contract produced by the spatial planner.
class SafetyAction {
  final String actionId;
  final SafetyActionKind kind;
  final String cause;
  final SafetyPriority priority;
  final SafetyActionDelivery delivery;
  final int sceneRevision;
  final List<String> hazardIds;
  final Map<String, Object?> evidenceSummary;
  final CorridorDirection? direction;
  final double confidence;
  final DateTime createdAt;
  final DateTime validUntil;
  final String ruleId;

  SafetyAction({
    required this.actionId,
    required this.kind,
    required this.cause,
    required this.priority,
    this.delivery = SafetyActionDelivery.primary,
    required this.sceneRevision,
    required List<String> hazardIds,
    required Map<String, Object?> evidenceSummary,
    required this.direction,
    required this.confidence,
    required this.createdAt,
    required this.validUntil,
    required this.ruleId,
  }) : assert(actionId != ''),
       assert(cause != ''),
       assert(ruleId != ''),
       assert(confidence >= 0 && confidence <= 1),
       assert(!validUntil.isBefore(createdAt)),
       hazardIds = List.unmodifiable(hazardIds),
       evidenceSummary = Map.unmodifiable(evidenceSummary);

  bool isExpiredAt(DateTime now) => now.isAfter(validUntil);

  bool get isShadowOnly => delivery == SafetyActionDelivery.shadow;
}
