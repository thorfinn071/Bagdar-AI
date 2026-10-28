# Exact topology of the canonical pixel partition

The canonical projection supplement closes four of the six passable static
scans. person-side and camera-pan-clear retain one or two distant floor
sections because floating-point polygon clipping still creates microscopic
fragments of the hidden slab bottom. Example: camera-pan-clear view 4,
pixel (136,111). Shared vertices alone do not guarantee exact half-plane
intersection topology.

Use exact rational arithmetic for the binary floating-point projected
vertices, inverse-depth coefficients and polygon intersections. No vertex
is snapped and no positive-area fragment is discarded. Full coverage is an
exact area equality; every uncovered fragment stays unknown. The existing
canonical near-plane construction remains frozen. Height evaluation retains
the conservative 1e-5 m numerical envelope. This second height supplement
preserves the first supplement's accepted floor intervals and all original
depth, validity, surface-Z and body free-Z packets.

The same label-free computation filter applies: centre height inside the
requested +/- .05 m floor interval and prior interval lacking support.
This merely selects where to compute the independent first-return proof.
Missing free-Z proof must remain absent when combining the two inputs.

Acceptance includes representable positive-area gaps down to the adjacent
floating-point values around .5 pixel, overlapping coverage holes, thin
foreground height, actual visible drops, hidden-surface invariance and
independent fractional Blender ray witnesses. Goal: six complete passable
static scans, six blocked hazardous scans, zero hazardous clears; all twelve
strict 100 ms stale scans rejected. No runtime wiring, phone validation,
neural accuracy or moving-frame latency claims follow from this experiment.
