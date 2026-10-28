# Immutable typed optical transport — 2026-10-11

Version 2 amendment: preserve v1 sources/preregistration/receipts/executable.
Nine new regression cases demonstrated that a v1 payload could be accidentally
paired with different frame/capture/session/model/transform/reference/pose or
intrinsics metadata. Add a 32-byte SHA256 fingerprint of the versioned original
metadata, including exact floating-point bits, and reject mismatch on receive.
This is an accidental-pairing check, not authentication or sensor calibration.
Pixel arrays, models, scoring cases, strict ages and producer predicates remain
unchanged. Freeze v2 before re-running corpus/timing; retain the initial failing
regression log. Include all fingerprint work in publication-inclusive timing.

The previous scalar optimization preserved measurements but typed copies
partly offset its coverage gain. Add a separate immutable transport subtype for
the six exact Float64 optical planes and one byte validity mask. Preserve every
pixel value (including NaN, infinity and signed zero), pose, units, errors,
calibration bindings, frame/session/order and original capture clocks. Never
create bounds, fill holes, validate metric scale or confer clearance authority.

Copies own their contiguous storage. TransferableTypedData publication copies
into unique storage; receiving materializes once and exposes only read-only
numeric/buffer/subview and validity interfaces. Reject malformed dimensions,
plane shapes, total wire size or validity bytes outside 0/1. Relative/invalid
metadata remain invalid rather than being repaired. No ordinary runtime wiring.

Before corpus/performance scoring freeze new sources/tests/protocol/profile/audit
and the preceding scalar/minimal chain. Reuse the 48 full/minimal/single/suffix6
known-scene comparisons and 17 negative controls, alternating typed copy and
pack/materialize across frames. Compare every observation field to the frozen
indexed producer. Repeat receipt byte-for-byte; also test ownership and 100
seeded small differing-intrinsics packets. Labels stay after measurement.

Measure Windows Dart AOT preloaded known minimal-ten-view packets. All modes
use the frozen scalar producer and the same sequential COUNTERFACTUAL 120 fps
timestamps, plus 2000 us start lag. Compare generic input, typed-copy publication
and typed pack/materialize publication. One warmup per mode/scene, three rounds
with reversed mode order every other round. Include publication of all ten
packets inside each advancing Stopwatch/age-gate compute call, recording packing,
source stages and total pipeline. Never move publication outside the timed
pipeline or renew a capture timestamp to conceal its cost. Reject expired
observations and decisions. No test or model workload in parallel.

This measures packet publication/materialization, source, evaluator and gate;
it does not measure actual isolate queue/dispatch, physical capture, inference,
transport from Android, phone latency or scene dynamics. Preserve 100000 us TTL,
STOP/history, models, request and conservative body/floor/occupancy predicates.
Keep shadow, promotionAllowed=false, ordinaryCameraWired=false,
falseStopReductionEstablished=false and canAuthorizeMovement=false. This slice
cannot complete the ordinary-camera goal while justified current measurements
remain absent and the required volume is outside tested ordinary camera views.
