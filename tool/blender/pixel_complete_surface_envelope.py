"""Analytic first-return envelope over an entire closed pixel rectangle.

Each patch is an opaque projected triangle and affine inverse axis depth.
Partitioning retains holes and chooses the nearest patch on every fragment.
No centre-ray approximation, semantic labels, or area-sum coverage admission.
"""
import math


def area(poly):
    if len(poly) < 3:
        return 0.0
    return abs(math.fsum(a[0] * b[1] - b[0] * a[1]
                   for a, b in zip(poly, poly[1:] + poly[:1]))) / 2


def value(coef, p):
    return coef[0] * p[0] + coef[1] * p[1] + coef[2]


def clip(poly, line):
    """Keep the closed nonnegative half-plane; do not dilate boundaries."""
    result = []
    for a, b in zip(poly, poly[1:] + poly[:1]):
        da, db = value(line, a), value(line, b)
        if da >= 0:
            result.append(a)
        if (da >= 0) != (db >= 0):
            t = da / (da - db)
            result.append((a[0] + t * (b[0] - a[0]),
                           a[1] + t * (b[1] - a[1])))
    return result


def subtract_convex(poly, edges):
    """Disjoint outside pieces plus the intersection, preserving all area."""
    outside = []
    inside = poly
    for edge in edges:
        part = clip(inside, tuple(-v for v in edge))
        if area(part) > 0:
            outside.append(part)
        inside = clip(inside, edge)
        if area(inside) == 0:
            return outside, []
    return outside, inside


def triangle_edges(triangle):
    a, b, c = triangle
    orientation = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    if orientation == 0:
        return []
    sign = 1 if orientation > 0 else -1
    return [(sign * -(b[1] - a[1]), sign * (b[0] - a[0]),
             sign * ((b[1] - a[1]) * a[0] - (b[0] - a[0]) * a[1]))
            for a, b in zip(triangle, triangle[1:] + triangle[:1])]


def first_return_bounds(x, y, patches, height_numerator, origin_height, maximum_fragments=256):
    """Return a certified axis-Z upper bound, or NaN when proof is absent.

    Only the actually nearest opaque surface is kept in each fragment.
    A hidden surface cannot erase a foreground patch or fill a remaining hole
    without being the visible first return in that hole.
    """
    # Local coordinates avoid subtracting large screen-area terms at seams.
    rectangle = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
    hcoef = (height_numerator[0], height_numerator[1],
             math.fsum((height_numerator[2], height_numerator[0]*x, height_numerator[1]*y)))
    pieces = [(rectangle, None)]
    for triangle, coef in patches:
        triangle = [(float(p[0]) - x, float(p[1]) - y) for p in triangle]
        coef = tuple(map(float, coef))
        coef = (coef[0], coef[1], math.fsum((coef[2], coef[0] * x, coef[1] * y)))
        if not all(math.isfinite(v) for p in triangle for v in p) or not all(map(math.isfinite, coef)):
            return math.nan, math.nan, math.nan, math.nan
        edges = triangle_edges(triangle)
        if not edges:
            continue
        updated = []
        for poly, previous in pieces:
            delta = tuple(coef[i] - previous[i] for i in range(3)) if previous else None
            # Already occluded over this entire convex fragment: leave its
            # geometry intact, including when more hidden surfaces are added.
            if previous and all(value(delta, p) <= 0 for p in poly):
                updated.append((poly, previous))
                continue
            outside, inside = subtract_convex(poly, edges)
            updated.extend((p, previous) for p in outside)
            if not inside:
                continue
            if previous is None:
                updated.append((inside, coef))
            else:
                nearer = clip(inside, delta)
                farther = clip(inside, tuple(-v for v in delta))
                if area(nearer) > 0:
                    updated.append((nearer, coef))
                if area(farther) > 0:
                    updated.append((farther, previous))
        if len(updated) > maximum_fragments:
            return math.nan, math.nan, math.nan, math.nan
        pieces = updated
    if not pieces or abs(sum(area(p) for p, _ in pieces) - 1.0) > 1e-9:
        return math.nan, math.nan, math.nan, math.nan
    upper = 0.0
    lower = math.inf
    height_lower, height_upper = math.inf, -math.inf
    for poly, coef in pieces:
        if coef is None:
            return math.nan, math.nan, math.nan, math.nan
        inverse = [value(coef, p) for p in poly]
        if min(inverse) <= 0:
            return math.nan, math.nan, math.nan, math.nan
        upper = max(upper, 1 / min(inverse))
        lower = min(lower, 1 / max(inverse))
        heights = [origin_height+value(hcoef,p)/inv for p,inv in zip(poly,inverse)]
        height_lower = min(height_lower, min(heights))
        height_upper = max(height_upper, max(heights))
    return upper, height_lower, height_upper, lower
