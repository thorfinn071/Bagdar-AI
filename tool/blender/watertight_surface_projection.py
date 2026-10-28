"""Canonical shared near-plane vertices, without geometric dilation."""
def clip_near(points, near=.01):
    out = []
    for a, b in zip(points, points[1:] + points[:1]):
        ai, bi = a[2] >= near, b[2] >= near
        if ai:
            out.append(tuple(a))
        if ai != bi:
            lo, hi = sorted((tuple(a), tuple(b)))
            t = (near - lo[2]) / (hi[2] - lo[2])
            out.append((lo[0] + (hi[0]-lo[0])*t,
                        lo[1] + (hi[1]-lo[1])*t, near))
    return out
