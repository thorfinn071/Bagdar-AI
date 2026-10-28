/* Desktop-only experiment. No runtime, allocation, labels, NN or timestamps.
 * The caller supplies bounded scratch storage and admitted immutable frames.
 * Compile without fast-math or floating-point contraction: score order matters.
 */
typedef unsigned char u8;
int _fltused = 0;
typedef struct {
  int width, height;
  double fx, fy, error;
  const double *pixels, *range, *lower, *upper;
  const double *nx, *ny, *x2, *y2;
  double *axis;
  const u8 *valid;
  u8 *status;
} MotionFrame;

__declspec(dllexport) int fast_motion_abi(void) { return 1; }

static int axis_at(MotionFrame *f, int x, int y) {
  int k = y * f->width + x;
  if (f->status[k]) return f->status[k] == 2;
  double lo = f->lower[k] - f->error;
  double hi = f->upper[k] + f->error;
  double z = f->range[k] / __builtin_sqrt(1 + f->x2[x] + f->y2[y]);
  if (!f->valid[k] || !__builtin_isfinite(z) ||
      !__builtin_isfinite(lo) || !__builtin_isfinite(hi) ||
      lo <= 0 || hi < lo || z < lo - 1e-5 || z > hi + 1e-5 ||
      (hi - lo) / z > .04) {
    f->status[k] = 1;
    return 0;
  }
  f->axis[k] = z;
  f->status[k] = 2;
  return 1;
}

static int coordinates(int center, int maximum, int *out) {
  int count = 0;
  int low = center - 32 > 1 ? center - 32 : 1;
  int high = center + 32 < maximum ? center + 32 : maximum;
  for (int d = 0; d <= 32; d++) {
    if (center + d >= low && center + d <= high) out[count++] = center + d;
    if (d && center - d >= low && center - d <= high) out[count++] = center - d;
  }
  return count;
}

/* Workspace: 4225 scores and 2*4225 coordinates, owned by one worker.
 * Return the winning pixel index, or -1 for an unavailable/ambiguous match.
 */
__declspec(dllexport) int fast_motion_match(
    MotionFrame *f, const double *template75, const double *basis6,
    double za, int center_x, int center_y,
    double *scores, int *score_x, int *score_y) {
  int columns[65], rows[65];
  int nc = coordinates(center_x, f->width - 2, columns);
  int nr = coordinates(center_y, f->height - 2, rows);
  int count = 0;
  double best = __builtin_inf();
  for (int row = 0; row < nr; row++) {
    int y = rows[row];
    for (int col = 0; col < nc; col++) {
      int x = columns[col];
      if (!axis_at(f, x, y)) continue;
      double zb = f->axis[y * f->width + x];
      if (za / zb < .6 || za / zb > 1.6) continue;
      double nx = f->nx[x], ny = f->ny[y];
      double ax = f->fx * (basis6[0] - nx * basis6[2]) / zb;
      double ay = f->fy * (basis6[1] - ny * basis6[2]) / zb;
      double bx = f->fx * (basis6[3] - nx * basis6[5]) / zb;
      double by = f->fy * (basis6[4] - ny * basis6[5]) / zb;
      if (__builtin_fabs(ax * by - ay * bx) < .36) continue;
      double error = 0;
      int k = 0, good = 1;
      double limit = ((best < .065 ? best : .065) + .015 + 1e-12) * 75;
      for (int dy = -4; dy <= 4 && good; dy += 2) {
        for (int dx = -4; dx <= 4; dx += 2) {
          double u = x + ax * dx + bx * dy;
          double v = y + ay * dx + by * dy;
          if (!__builtin_isfinite(u) || !__builtin_isfinite(v) ||
              u < 0 || v < 0 || u >= f->width - 1 || v >= f->height - 1) {
            good = 0;
            break;
          }
          /* u/v are admitted nonnegative, so truncation equals floor. */
          int iu = (int)u, iv = (int)v;
          double du = u - iu, dv = v - iv;
          double left = 1 - du, up = 1 - dv;
          int i00 = (iv * f->width + iu) * 3;
          int i10 = i00 + 3, i01 = i00 + f->width * 3, i11 = i01 + 3;
          for (int c = 0; c < 3; c++) {
            double sample = f->pixels[i00+c] * left * up +
                            f->pixels[i10+c] * du * up +
                            f->pixels[i01+c] * left * dv +
                            f->pixels[i11+c] * du * dv;
            error += __builtin_fabs(template75[k++] - sample);
          }
          if (error > limit) { good = 0; break; }
        }
      }
      if (!good) continue;
      double score = error / 75;
      scores[count] = score; score_x[count] = x; score_y[count] = y;
      count++;
      if (score < best) best = score;
    }
  }
  if (!count || best > .065) return -1;
  int winner = 0;
  for (int k = 1; k < count; k++) {
    if (scores[k] < scores[winner] ||
        (scores[k] == scores[winner] &&
         (score_y[k] < score_y[winner] ||
          (score_y[k] == score_y[winner] && score_x[k] < score_x[winner])))) {
      winner = k;
    }
  }
  double second = __builtin_inf();
  for (int k = 0; k < count; k++) {
    int dx = score_x[k] - score_x[winner], dy = score_y[k] - score_y[winner];
    if ((dx > 2 || dx < -2 || dy > 2 || dy < -2) && scores[k] < second)
      second = scores[k];
  }
  if (second - best < .015) return -1;
  return score_y[winner] * f->width + score_x[winner];
}
