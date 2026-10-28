# Canonical projection of visible floor surfaces

The complete-envelope-v1 scan closes body coverage in all six passable layouts,
but retains unknown floor patches. A localized witness in path-clear, view 4,
pixel (150,111), shows an artificial approximately 5e-12 pixel gap between the
two triangles of one floor face. Reversed traversal of their shared near-plane
intersection computes different floating-point endpoints. The first-return
partition consequently includes the otherwise hidden bottom of the slab.

This separate supplement preserves the previous corpora and the complete
envelope's depth, validity, axis bounds and independent first-Z lower bounds.
Only height intervals are recomputed at pixels whose centre height is inside
the requested floor interval and whose previous whole-pixel height interval
cannot establish floor support. This is a computation filter, not an admission
rule. No scoring label, object name, floor fit, interpolation or hole filling
is available to the consumer or used to select pixels.

Shared near-plane intersections and directed edge coefficients use canonical
endpoint order. Both adjacent triangles consequently reuse the same geometric
boundary. No epsilon expansion, snapping or positive-area hole removal is
allowed. The exact first-return partition must still retain actual gaps,
off-centre foreground surfaces, drop boundaries and uncovered space.

Acceptance: exact reversed-edge coefficients/intersections, actual gaps down
to 1e-12 pixel unknown, independent fractional Blender ray witnesses, hidden
surface invariance, thin foreground/drop retained; all 144 packets bound to
the prior frozen packet identities. Final replay goal: six passable static
scans completely measured, six hazardous scans blocked, zero hazardous clears.
The strict 100 ms policy must still reject all twelve 2.2-second scans. This
known-regression geometry experiment is shadow-only and has no phone/runtime
or neural-model accuracy authority.
