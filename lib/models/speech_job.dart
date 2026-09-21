enum SpeechPriority { info, warning, critical }

class SpeechJob {
  final String text;
  final SpeechPriority priority;
  final double pan;

  final double rate;

  final int? trackId;
  final String? actionId;
  final String? hazardId;

  final DateTime enqueuedAt;
  final DateTime expiresAt;
  final bool skipHaptic;

  SpeechJob(
    this.text,
    this.priority, {
    this.pan = 0.0,
    this.rate = 0.50,
    this.trackId,
    this.actionId,
    this.hazardId,
    DateTime? enqueuedAt,
    DateTime? expiresAt,
    this.skipHaptic = false,
  }) : enqueuedAt = enqueuedAt ?? DateTime.now(),
       expiresAt =
           expiresAt ??
           (enqueuedAt ?? DateTime.now()).add(
             priority == SpeechPriority.critical
                 ? const Duration(seconds: 4)
                 : const Duration(seconds: 5),
           );

  bool isExpiredAt(DateTime now) => now.isAfter(expiresAt);
}
