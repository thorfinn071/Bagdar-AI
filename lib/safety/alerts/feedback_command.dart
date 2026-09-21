import '../planning/safety_action.dart';
import '../planning/corridor_candidate.dart';

enum FeedbackCommandSource {
  spatialAction,
  objectHazard,
  depthHazard,
  coreHealth,
  cameraHealth,
  emergency,
  onDemand,
}

enum FeedbackEarcon { none, stop, degraded, confirmation }

enum FeedbackHapticPattern {
  none,
  immediateStop,
  sensingDegraded,
  confirmation,
}

class FeedbackCommand {
  final String actionId;
  final int sceneRevision;
  final String speechKey;
  final FeedbackEarcon earcon;
  final FeedbackHapticPattern hapticPattern;
  final SafetyPriority priority;
  final FeedbackCommandSource source;
  final SafetyActionKind? actionKind;
  final CorridorDirection? direction;
  final double urgency;
  final bool canInterrupt;
  final String replaceKey;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String ruleId;
  final List<String> hazardIds;
  final double pan;

  FeedbackCommand({
    required this.actionId,
    required this.sceneRevision,
    required this.speechKey,
    required this.earcon,
    required this.hapticPattern,
    required this.priority,
    required this.source,
    required this.actionKind,
    required this.direction,
    required this.urgency,
    required this.canInterrupt,
    required this.replaceKey,
    required this.createdAt,
    required this.expiresAt,
    required this.ruleId,
    required List<String> hazardIds,
    this.pan = 0,
  }) : assert(actionId != ''),
       assert(speechKey != ''),
       assert(replaceKey != ''),
       assert(ruleId != ''),
       assert(urgency >= 0 && urgency <= 1),
       assert(pan >= -1 && pan <= 1),
       assert(!expiresAt.isBefore(createdAt)),
       hazardIds = List.unmodifiable(hazardIds);

  bool isExpiredAt(DateTime now) => now.isAfter(expiresAt);

  bool hasSameResponseAs(FeedbackCommand other) =>
      actionKind == other.actionKind && direction == other.direction;

  bool isMeaningfulEscalationOver(
    FeedbackCommand other, {
    double urgencyDelta = 0.05,
  }) =>
      priority.index > other.priority.index ||
      urgency >= other.urgency + urgencyDelta ||
      !hasSameResponseAs(other);

  FeedbackCommand copyWith({
    String? actionId,
    int? sceneRevision,
    String? speechKey,
    FeedbackEarcon? earcon,
    FeedbackHapticPattern? hapticPattern,
    SafetyPriority? priority,
    FeedbackCommandSource? source,
    SafetyActionKind? actionKind,
    CorridorDirection? direction,
    double? urgency,
    bool? canInterrupt,
    String? replaceKey,
    DateTime? createdAt,
    DateTime? expiresAt,
    String? ruleId,
    List<String>? hazardIds,
    double? pan,
  }) => FeedbackCommand(
    actionId: actionId ?? this.actionId,
    sceneRevision: sceneRevision ?? this.sceneRevision,
    speechKey: speechKey ?? this.speechKey,
    earcon: earcon ?? this.earcon,
    hapticPattern: hapticPattern ?? this.hapticPattern,
    priority: priority ?? this.priority,
    source: source ?? this.source,
    actionKind: actionKind ?? this.actionKind,
    direction: direction ?? this.direction,
    urgency: urgency ?? this.urgency,
    canInterrupt: canInterrupt ?? this.canInterrupt,
    replaceKey: replaceKey ?? this.replaceKey,
    createdAt: createdAt ?? this.createdAt,
    expiresAt: expiresAt ?? this.expiresAt,
    ruleId: ruleId ?? this.ruleId,
    hazardIds: hazardIds ?? this.hazardIds,
    pan: pan ?? this.pan,
  );

  FeedbackCommand mergeHazards(FeedbackCommand other) {
    final merged = <String>{...hazardIds, ...other.hazardIds}.toList()..sort();
    return copyWith(
      urgency: other.urgency > urgency ? other.urgency : urgency,
      hazardIds: merged,
    );
  }
}
