/// Features that exist in source but are excluded from the Core runtime
/// unless [BuildProfile.research] is compiled.
///
/// Core-required systems (camera, YOLO, depth, alerts, SOS, fall,
/// orientation, TTS, haptics) are not listed here — they are always on.
enum CoreFeature {
  bazaarLivestock,
  acousticWorldModel,
  vlmSceneQa,
  sonar,
  bleMesh,
  smartCane,
  indoorTrail,
  chargingJobs,
  paymentSms,
  phoneAbandoned,
  objectMemoryFinder,
  publicTransit,
  experimentalWinter,
  sceneNarration,
  paddleOcr,
  kazakhStackV2,
  localAsrAdaptation,
}
