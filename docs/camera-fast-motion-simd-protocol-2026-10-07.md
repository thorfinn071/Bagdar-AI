# Strict SIMD2 fast-motion experiment — 2026-10-07

This is a separate Windows x64 desktop/shadow kernel. It uses the frozen packed
worker and independent capture feed; the ordinary camera is not wired to it.
No phone, Android, capture-to-command or controlled-walking evidence is added.

The new C kernel evaluates the first two adjacent colour channels together,
then the third channel separately. Bilinear multiply/add order within each
channel and scalar error accumulation in channel order 0, 1, 2 are preserved.
The vector type uses `aligned(1), may_alias` so vector loads do not impose new
alignment or aliasing requirements. Two-channel loads stay within each RGB
pixel; the third channel retains the scalar path. Clang documents these vector
types and arithmetic in its [language extensions](https://clang.llvm.org/docs/LanguageExtensions.html#vectors-and-extended-vectors).

Compile with `-O3 -fno-fast-math -ffp-contract=off -fno-math-errno` for Windows
x64, keeping the existing ABI 1. No thresholds, feature selection, search
radius, candidate order, tie handling, ambiguity rejection, geometric checks,
worker ownership, clocks, sessions, queue bounds or 100 ms freshness limit
change. Input RGB, metric first-return depth and pose remain synthetic;
relative MiDaS output supplies concurrent load only and has no sensing authority.

Before timing, require full 109-frame kernel and worker diagnostic JSON to
match the frozen reference; run native transport/worker safety contracts and
the 67-frame shadow replay. Differential ABI tests compare winners and the
bit pattern of every scratch score, coordinate, axis and status byte for 85
cases covering colour channels, unaligned loads, edges, fractional projective
sampling, score thresholds, ties, ambiguous images and invalid sensing.

Measure using the frozen `replay_fast_camera_motion_stream.dart --elapsed-nn`
caller, selecting the original or SIMD DLL by path. Use fresh output paths and
serial balanced pairs: original/SIMD, SIMD/original, original/SIMD. No analyzer,
compilation or tests run concurrently with a timed trial. Preserve all trials,
including failures. Record the caller and DLL hashes. The prior stream trials
remain separate observations. Timings are observations, not deterministic
software-release checks or independent model validation.

For each trial report fresh reference risk updates out of 54, test updates out
of 30, expiry/pair-reset losses, all-frame age p50/p95, callback age, compute and
copy times, queue bounds and load activity. Report the risk-update gate and
all-frame 100 ms gate separately. Never admit a stale result or equate unknown
space with free space. Repeating the known test subset does not create a new
holdout. False-stop clearance remains a separate unresolved observability gate.

Source receipt is write-once. Its verifier checks the older frozen stream,
packed and load contracts and proves the C source changes only the channel
sampling expression and vector typedef. Results and latency reports are kept
outside the source receipt; `promotionAllowed=false`.
