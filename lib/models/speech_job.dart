enum SpeechPriority { info, warning, critical }

class SpeechJob {
  final String text;
  final SpeechPriority priority;
  final double pan;

  final double rate;

  final int? trackId;

  final DateTime enqueuedAt;

  SpeechJob(
    this.text,
    this.priority, {
    this.pan    = 0.0,
    this.rate   = 0.50,
    this.trackId,
  }) : enqueuedAt = DateTime.now();
}
