// NCNN-based depth inference for MiDaS Small.
//
// Exposed symbols (loaded by Dart via dart:ffi):
//   bagdar_ncnn_init         - load .param/.bin from filesystem paths
//   bagdar_ncnn_infer_yuv    - end-to-end: YUV Y-plane → resized CHW → infer → depth map
//   bagdar_ncnn_dispose      - free model resources
//   bagdar_ncnn_is_vulkan    - whether the active extractor is using Vulkan
//
// Thread safety:
//   - g_net is initialized once and read-only afterwards.
//   - Each infer call creates its own ncnn::Extractor (cheap).
//   - Dart will call from a single isolate, so concurrent calls are not expected.

#include <algorithm>
#include <atomic>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include <android/log.h>

#include "ncnn/net.h"
#include "ncnn/datareader.h"

#define LOG_TAG "BagdarNcnn"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

constexpr int kInputSize = 256;

struct NcnnDepthState {
  ncnn::Net net;
  std::mutex mtx;
  std::atomic<bool> ready{false};
  bool vulkan_active = false;
  std::string input_blob;
  std::string output_blob;
};

NcnnDepthState g_state;
std::atomic<int32_t> g_last_out_w{0};
std::atomic<int32_t> g_last_out_h{0};

inline int clampi(int v, int lo, int hi) {
  return v < lo ? lo : (v > hi ? hi : v);
}

inline uint8_t sample_plane(
    const uint8_t* p,
    int32_t len,
    int x,
    int y,
    int w,
    int h,
    int row_stride,
    int pixel_stride) {
  if (p == nullptr || len <= 0 || w <= 0 || h <= 0) return 0;
  x = clampi(x, 0, w - 1);
  y = clampi(y, 0, h - 1);
  const int64_t idx =
      static_cast<int64_t>(y) * row_stride + static_cast<int64_t>(x) * pixel_stride;
  if (idx < 0 || idx >= len) return 0;
  return p[idx];
}

inline void yuv_to_rgb01(uint8_t y, uint8_t u, uint8_t v, float* r, float* g, float* b) {
  const float yf = static_cast<float>(y);
  const float uf = static_cast<float>(u) - 128.f;
  const float vf = static_cast<float>(v) - 128.f;
  *r = std::clamp(yf + 1.402f * vf, 0.f, 255.f) * (1.f / 255.f);
  *g = std::clamp(yf - 0.344136f * uf - 0.714136f * vf, 0.f, 255.f) * (1.f / 255.f);
  *b = std::clamp(yf + 1.772f * uf, 0.f, 255.f) * (1.f / 255.f);
}

std::vector<std::string> tokenize_layer_line(const std::string& line) {
  std::vector<std::string> tokens;
  size_t i = 0;
  while (i < line.size()) {
    while (i < line.size() && std::isspace(static_cast<unsigned char>(line[i]))) ++i;
    size_t start = i;
    while (i < line.size() && !std::isspace(static_cast<unsigned char>(line[i]))) ++i;
    if (start < i) tokens.emplace_back(line.substr(start, i - start));
  }
  return tokens;
}

std::string layer_first_output(const std::vector<std::string>& tokens) {
  if (tokens.size() < 5) return {};
  int in_count = 0;
  int out_count = 0;
  try {
    in_count = std::stoi(tokens[2]);
    out_count = std::stoi(tokens[3]);
  } catch (...) {
    return {};
  }
  if (in_count < 0 || out_count <= 0) return {};
  const size_t out_start = 4 + static_cast<size_t>(in_count);
  if (out_start >= tokens.size()) return {};
  return tokens[out_start];
}

bool discover_blob_names(const char* param_path) {
  FILE* f = std::fopen(param_path, "rb");
  if (!f) return false;
  std::fseek(f, 0, SEEK_END);
  long sz = std::ftell(f);
  std::fseek(f, 0, SEEK_SET);
  if (sz <= 0 || sz > (1 << 20)) {
    std::fclose(f);
    return false;
  }
  std::string buf;
  buf.resize(sz);
  std::fread(buf.data(), 1, sz, f);
  std::fclose(f);

  std::string in_name, last_out_name;
  size_t pos = 0;
  while (pos < buf.size()) {
    size_t eol = buf.find('\n', pos);
    if (eol == std::string::npos) eol = buf.size();
    std::string line = buf.substr(pos, eol - pos);
    pos = eol + 1;
    auto tokens = tokenize_layer_line(line);
    if (tokens.size() < 5) continue;
    auto first_out = layer_first_output(tokens);
    if (first_out.empty()) continue;
    if (in_name.empty() && tokens[0] == "Input") {
      in_name = first_out;
    }
    last_out_name = first_out;
  }
  if (in_name.empty() || last_out_name.empty()) return false;
  g_state.input_blob = std::move(in_name);
  g_state.output_blob = std::move(last_out_name);
  return true;
}

}  // namespace

extern "C" __attribute__((visibility("default"))) int32_t bagdar_ncnn_init(
    const char* param_path,
    const char* bin_path,
    int32_t use_vulkan,
    int32_t num_threads) {
  if (param_path == nullptr || bin_path == nullptr) {
    LOGE("init: null path");
    return -1;
  }
  std::lock_guard<std::mutex> lock(g_state.mtx);
  g_state.ready = false;
  g_state.net.clear();

  if (!discover_blob_names(param_path)) {
    LOGE("init: cannot discover input/output blobs from %s", param_path);
    return -2;
  }

  g_state.net.opt.use_vulkan_compute = use_vulkan != 0;
  g_state.net.opt.num_threads = std::max(1, std::min(4, (int)num_threads));
  g_state.net.opt.use_packing_layout = true;
  g_state.net.opt.use_fp16_packed = true;
  g_state.net.opt.use_fp16_storage = true;
  g_state.net.opt.use_fp16_arithmetic = true;

  if (int ret = g_state.net.load_param(param_path); ret != 0) {
    LOGE("init: load_param failed (ret=%d) path=%s", ret, param_path);
    g_state.net.clear();
    return -3;
  }
  if (int ret = g_state.net.load_model(bin_path); ret != 0) {
    LOGE("init: load_model failed (ret=%d) path=%s", ret, bin_path);
    g_state.net.clear();
    return -4;
  }

  g_state.vulkan_active = g_state.net.opt.use_vulkan_compute;
  g_state.ready = true;
  LOGI("init: ok vulkan=%d threads=%d in=%s out=%s",
       (int)g_state.vulkan_active,
       g_state.net.opt.num_threads,
       g_state.input_blob.c_str(),
       g_state.output_blob.c_str());
  return 0;
}

extern "C" __attribute__((visibility("default"))) int32_t bagdar_ncnn_is_vulkan() {
  return g_state.vulkan_active ? 1 : 0;
}

// YUV_420_888 → RGB [0,1] CHW. Mean/std are INSIDE the NCNN graph
// (MemoryData 483/485 = ImageNet RGB). Do not apply them here. Do not
// replicate luma into three channels — the exported model is RGB.
static void preprocess_yuv420_to_chw(
    const uint8_t* src_y, int32_t y_len,
    const uint8_t* src_u, int32_t u_len,
    const uint8_t* src_v, int32_t v_len,
    int32_t src_w,
    int32_t src_h,
    int32_t y_row_stride, int32_t y_pixel_stride,
    int32_t u_row_stride, int32_t u_pixel_stride,
    int32_t v_row_stride, int32_t v_pixel_stride,
    int32_t rotation_degrees,
    int32_t mirrored,
    float crop_top_frac,
    float* chw_out) {
  rotation_degrees = ((rotation_degrees % 360) + 360) % 360;
  if (rotation_degrees != 0 && rotation_degrees != 90 &&
      rotation_degrees != 180 && rotation_degrees != 270) {
    rotation_degrees = 0;
  }
  const bool swap_axes = rotation_degrees == 90 || rotation_degrees == 270;
  const int32_t oriented_w = swap_axes ? src_h : src_w;
  const int32_t oriented_h = swap_axes ? src_w : src_h;
  crop_top_frac = std::clamp(crop_top_frac, 0.0f, 0.9f);
  const int32_t crop_top = std::clamp(
      static_cast<int32_t>(oriented_h * crop_top_frac), 0, oriented_h - 1);
  const int32_t crop_h = std::max(1, oriented_h - crop_top);
  const int plane = kInputSize * kInputSize;
  const int chroma_w = (src_w + 1) / 2;
  const int chroma_h = (src_h + 1) / 2;
  const int y_pix = y_pixel_stride <= 0 ? 1 : y_pixel_stride;
  const int u_pix = u_pixel_stride <= 0 ? 1 : u_pixel_stride;
  const int v_pix = v_pixel_stride <= 0 ? 1 : v_pixel_stride;

  for (int y = 0; y < kInputSize; ++y) {
    const int oy = crop_top + (y * crop_h) / kInputSize;
    const int row_off = y * kInputSize;
    for (int x = 0; x < kInputSize; ++x) {
      int ox = (x * oriented_w) / kInputSize;
      if (mirrored != 0) ox = oriented_w - 1 - ox;
      int sx = 0;
      int sy = 0;
      switch (rotation_degrees) {
        case 90:
          sx = oy;
          sy = src_h - 1 - ox;
          break;
        case 180:
          sx = src_w - 1 - ox;
          sy = src_h - 1 - oy;
          break;
        case 270:
          sx = src_w - 1 - oy;
          sy = ox;
          break;
        default:
          sx = ox;
          sy = oy;
          break;
      }
      const uint8_t Y = sample_plane(
          src_y, y_len, sx, sy, src_w, src_h, y_row_stride, y_pix);
      const uint8_t U = sample_plane(
          src_u, u_len, sx / 2, sy / 2, chroma_w, chroma_h, u_row_stride, u_pix);
      const uint8_t V = sample_plane(
          src_v, v_len, sx / 2, sy / 2, chroma_w, chroma_h, v_row_stride, v_pix);
      float r, g, b;
      yuv_to_rgb01(Y, U, V, &r, &g, &b);
      chw_out[row_off + x] = r;
      chw_out[plane + row_off + x] = g;
      chw_out[2 * plane + row_off + x] = b;
    }
  }
}

static void resize_bilinear_nan(
    const float* src, int sw, int sh,
    float* dst, int dw, int dh) {
  if (sw == dw && sh == dh) {
    std::memcpy(dst, src, sizeof(float) * dw * dh);
    return;
  }
  for (int y = 0; y < dh; ++y) {
    const float fy = (sh == 1) ? 0.f : ((y + 0.5f) * sh / dh - 0.5f);
    const int y0 = clampi(static_cast<int>(std::floor(fy)), 0, sh - 1);
    const int y1 = clampi(y0 + 1, 0, sh - 1);
    const float wy = fy - std::floor(fy);
    for (int x = 0; x < dw; ++x) {
      const float fx = (sw == 1) ? 0.f : ((x + 0.5f) * sw / dw - 0.5f);
      const int x0 = clampi(static_cast<int>(std::floor(fx)), 0, sw - 1);
      const int x1 = clampi(x0 + 1, 0, sw - 1);
      const float wx = fx - std::floor(fx);
      const float v00 = src[y0 * sw + x0];
      const float v10 = src[y0 * sw + x1];
      const float v01 = src[y1 * sw + x0];
      const float v11 = src[y1 * sw + x1];
      if (!std::isfinite(v00) || !std::isfinite(v10) ||
          !std::isfinite(v01) || !std::isfinite(v11)) {
        dst[y * dw + x] = NAN;
        continue;
      }
      const float v0 = v00 * (1.f - wx) + v10 * wx;
      const float v1 = v01 * (1.f - wx) + v11 * wx;
      dst[y * dw + x] = v0 * (1.f - wy) + v1 * wy;
    }
  }
}

static bool to_float32_unpacked(const ncnn::Mat& src, ncnn::Mat& dst) {
  ncnn::Option opt = g_state.net.opt;
  ncnn::Mat tmp = src;
  if (tmp.elempack != 1) {
    ncnn::Mat unpacked;
    ncnn::convert_packing(tmp, unpacked, 1, opt);
    tmp = unpacked;
  }
  if (tmp.elemsize == 2) {
    ncnn::Mat f32;
    ncnn::cast_float16_to_float32(tmp, f32, opt);
    tmp = f32;
  } else if (tmp.elemsize != 4) {
    return false;
  }
  dst = tmp;
  return true;
}

extern "C" __attribute__((visibility("default"))) int32_t bagdar_ncnn_last_out_w() {
  return g_last_out_w.load();
}

extern "C" __attribute__((visibility("default"))) int32_t bagdar_ncnn_last_out_h() {
  return g_last_out_h.load();
}

// Legacy Y-only entry. Grayscale replication is forbidden — return error.
extern "C" __attribute__((visibility("default"))) int32_t bagdar_ncnn_infer_yuv(
    const uint8_t* src_y,
    int32_t src_w,
    int32_t src_h,
    int32_t row_stride,
    float crop_top_frac,
    float* output,
    int32_t output_len) {
  (void)src_y;
  (void)src_w;
  (void)src_h;
  (void)row_stride;
  (void)crop_top_frac;
  (void)output;
  (void)output_len;
  LOGE("infer_yuv: Y-only grayscale path removed; use bagdar_ncnn_infer_yuv420");
  return -30;
}

extern "C" __attribute__((visibility("default"))) int32_t bagdar_ncnn_infer_yuv420(
    const uint8_t* src_y, int32_t y_len,
    const uint8_t* src_u, int32_t u_len,
    const uint8_t* src_v, int32_t v_len,
    int32_t src_w,
    int32_t src_h,
    int32_t y_row_stride, int32_t y_pixel_stride,
    int32_t u_row_stride, int32_t u_pixel_stride,
    int32_t v_row_stride, int32_t v_pixel_stride,
    int32_t rotation_degrees,
    int32_t mirrored,
    float crop_top_frac,
    float* output,
    int32_t output_len) {
  if (!g_state.ready.load()) {
    LOGE("infer: not initialized");
    return -10;
  }
  if (src_y == nullptr || src_u == nullptr || src_v == nullptr || output == nullptr) {
    return -11;
  }
  if (src_w <= 0 || src_h <= 1) return -12;
  if (output_len < kInputSize * kInputSize) return -13;
  if (y_len <= 0 || u_len <= 0 || v_len <= 0) return -14;

  thread_local std::vector<float> chw;
  chw.resize(static_cast<size_t>(kInputSize) * kInputSize * 3);
  preprocess_yuv420_to_chw(
      src_y, y_len, src_u, u_len, src_v, v_len,
      src_w, src_h,
      y_row_stride, y_pixel_stride,
      u_row_stride, u_pixel_stride,
      v_row_stride, v_pixel_stride,
      rotation_degrees, mirrored,
      crop_top_frac, chw.data());

  ncnn::Mat in(kInputSize, kInputSize, 3, (void*)chw.data(), sizeof(float));
  ncnn::Extractor ex = g_state.net.create_extractor();
  ex.set_num_threads(g_state.net.opt.num_threads);

  if (int ret = ex.input(g_state.input_blob.c_str(), in); ret != 0) {
    LOGE("infer: input failed (ret=%d)", ret);
    return -20;
  }

  ncnn::Mat out_raw;
  if (int ret = ex.extract(g_state.output_blob.c_str(), out_raw); ret != 0) {
    LOGE("infer: extract failed (ret=%d)", ret);
    return -21;
  }

  ncnn::Mat out;
  if (!to_float32_unpacked(out_raw, out)) return -24;

  int ow = out.w;
  int oh = out.h;
  int oc = out.c;
  if (oh <= 0 || ow <= 0) return -22;
  // Squeeze may leave a 1 x (w*h) vector. Recover a square layout if possible.
  if (oh == 1 && oc <= 1) {
    const int side = static_cast<int>(std::lround(std::sqrt(static_cast<double>(ow))));
    if (side * side == ow) {
      oh = side;
      ow = side;
    }
  }
  if (oc > 1) {
    // Depth is channel 0.
  }
  g_last_out_w.store(ow);
  g_last_out_h.store(oh);
  LOGI("infer: native_out=%dx%d (c=%d) -> %dx%d", ow, oh, oc, kInputSize, kInputSize);

  thread_local std::vector<float> src;
  src.resize(static_cast<size_t>(ow) * oh);
  ncnn::Mat ch0 = (out.c > 0) ? out.channel(0) : out;
  const float* ptr = reinterpret_cast<const float*>(ch0.data);
  if (ptr == nullptr) {
    return -25;
  }
  for (int i = 0; i < ow * oh; ++i) {
    const float v = ptr[i];
    src[i] = std::isfinite(v) ? v : NAN;
  }
  resize_bilinear_nan(src.data(), ow, oh, output, kInputSize, kInputSize);
  return 0;
}

extern "C" __attribute__((visibility("default"))) void bagdar_ncnn_dispose() {
  std::lock_guard<std::mutex> lock(g_state.mtx);
  g_state.ready = false;
  g_state.net.clear();
  g_state.vulkan_active = false;
  g_state.input_blob.clear();
  g_state.output_blob.clear();
  LOGI("dispose: ok");
}
