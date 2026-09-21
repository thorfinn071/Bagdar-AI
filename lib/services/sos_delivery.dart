/// Structured SOS delivery outcomes. "Sent" is never inferred from opening
/// a composer or dialer.
enum SosDeliveryPhase {
  idle,
  resolvingLocation,
  sending,
  acceptedByModem,
  rejected,
  timedOut,
  delivered,
  deliveryUnconfirmed,
  composerOpened,
  dialerOpened,
  failed,
}

class SosDeliveryStatus {
  final SosDeliveryPhase phase;
  final String reasonCode;
  final DateTime at;
  final int? androidErrorCode;
  final bool locationStale;
  final String? locationAgeCategory;

  const SosDeliveryStatus({
    required this.phase,
    required this.reasonCode,
    required this.at,
    this.androidErrorCode,
    this.locationStale = false,
    this.locationAgeCategory,
  });

  bool get isTerminal =>
      phase == SosDeliveryPhase.delivered ||
      phase == SosDeliveryPhase.deliveryUnconfirmed ||
      phase == SosDeliveryPhase.composerOpened ||
      phase == SosDeliveryPhase.dialerOpened ||
      phase == SosDeliveryPhase.failed ||
      phase == SosDeliveryPhase.rejected ||
      phase == SosDeliveryPhase.timedOut;

  /// True only for modem acceptance. Composer/dialer are not success.
  bool get modemAccepted => phase == SosDeliveryPhase.acceptedByModem;

  bool get recipientDelivered => phase == SosDeliveryPhase.delivered;
}

class SosDeliveryMachine {
  SosDeliveryStatus _status = SosDeliveryStatus(
    phase: SosDeliveryPhase.idle,
    reasonCode: 'idle',
    at: DateTime.fromMillisecondsSinceEpoch(0),
  );

  SosDeliveryStatus get status => _status;

  void start(DateTime now) {
    _status = SosDeliveryStatus(
      phase: SosDeliveryPhase.resolvingLocation,
      reasonCode: 'resolving_location',
      at: now,
    );
  }

  void sending(DateTime now) {
    _status = SosDeliveryStatus(
      phase: SosDeliveryPhase.sending,
      reasonCode: 'sending',
      at: now,
    );
  }

  void acceptedByModem(DateTime now, {int? androidErrorCode}) {
    _status = SosDeliveryStatus(
      phase: SosDeliveryPhase.acceptedByModem,
      reasonCode: 'modem_accepted',
      at: now,
      androidErrorCode: androidErrorCode,
    );
  }

  void delivered(DateTime now) {
    _status = SosDeliveryStatus(
      phase: SosDeliveryPhase.delivered,
      reasonCode: 'delivered',
      at: now,
    );
  }

  void deliveryUnconfirmed(DateTime now) {
    _status = SosDeliveryStatus(
      phase: SosDeliveryPhase.deliveryUnconfirmed,
      reasonCode: 'delivery_unconfirmed',
      at: now,
    );
  }

  void composerOpened(DateTime now) {
    _status = SosDeliveryStatus(
      phase: SosDeliveryPhase.composerOpened,
      reasonCode: 'composer_opened',
      at: now,
    );
  }

  void dialerOpened(DateTime now) {
    _status = SosDeliveryStatus(
      phase: SosDeliveryPhase.dialerOpened,
      reasonCode: 'dialer_opened',
      at: now,
    );
  }

  void failed(
    DateTime now, {
    required String reasonCode,
    int? androidErrorCode,
  }) {
    _status = SosDeliveryStatus(
      phase: SosDeliveryPhase.failed,
      reasonCode: reasonCode,
      at: now,
      androidErrorCode: androidErrorCode,
    );
  }

  void timeout(DateTime now) {
    _status = SosDeliveryStatus(
      phase: SosDeliveryPhase.timedOut,
      reasonCode: 'timeout',
      at: now,
    );
  }
}
