/// Developer/rollout flag for the generic obstacle stack.
///
/// Not a user-facing mode carousel. Default is [shadow] so the detector
/// can log decisions without speaking until the validation report
/// authorizes supervised [assistive] alerts.
enum GenericObstacleMode { off, shadow, assistive }

/// Assistive generic-obstacle speech is not authorized for any build until
/// `docs/generic-obstacle-validation-report.md` names that build. Prefs
/// and research flags cannot bypass this.
const bool kGenericObstacleAssistiveAuthorized = false;

/// Collapse an unauthorized [GenericObstacleMode.assistive] request to
/// [GenericObstacleMode.shadow].
GenericObstacleMode sanitizeGenericObstacleMode(GenericObstacleMode mode) {
  if (mode == GenericObstacleMode.assistive &&
      !kGenericObstacleAssistiveAuthorized) {
    return GenericObstacleMode.shadow;
  }
  return mode;
}
