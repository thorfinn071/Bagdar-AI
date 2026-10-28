import '../services/sos_service.dart';

enum SosUiPhase { idle, countdown, cancelled, sending, result }

/// Presentation of an SOS attempt. Opening another app is not delivery.
class SosUiState {
  final SosUiPhase phase;
  final int secondsLeft;
  final bool cancelConfirmationPending;
  final SosResult? result;
  final bool afterFall;

  const SosUiState.idle()
    : phase = SosUiPhase.idle,
      secondsLeft = 0,
      cancelConfirmationPending = false,
      result = null,
      afterFall = false;

  const SosUiState.countdown(
    this.secondsLeft, {
    required this.cancelConfirmationPending,
  }) : phase = SosUiPhase.countdown,
       result = null,
       afterFall = true;

  const SosUiState.cancelled()
    : phase = SosUiPhase.cancelled,
      secondsLeft = 0,
      cancelConfirmationPending = false,
      result = null,
      afterFall = true;

  const SosUiState.sending()
    : phase = SosUiPhase.sending,
      secondsLeft = 0,
      cancelConfirmationPending = false,
      result = null,
      afterFall = false;

  const SosUiState.result(SosResult value, {this.afterFall = false})
    : phase = SosUiPhase.result,
      result = value,
      secondsLeft = 0,
      cancelConfirmationPending = false;

  String get messageKey => switch (phase) {
    SosUiPhase.idle => 'sos_action',
    SosUiPhase.countdown => 'sos_fall_countdown',
    SosUiPhase.cancelled => 'sos_fall_cancelled',
    SosUiPhase.sending => 'sos_sending',
    SosUiPhase.result => switch (result!) {
      SosResult.sent => afterFall ? 'sos_fall_sent' : 'sos_sent',
      SosResult.sentFallback => 'sos_sent',
      SosResult.pendingEnqueued => 'sos_queued',
      SosResult.sentWithoutLocation => 'sos_sent_no_location',
      SosResult.noContact => 'sos_no_contact',
      SosResult.noLocation => 'sos_no_location',
      SosResult.launchFailed => 'sos_launch_failed',
      SosResult.error => 'sos_error',
      SosResult.composerOpened => 'sos_composer_opened',
      SosResult.dialerOpened => 'sos_dialer_opened',
    },
  };
}
