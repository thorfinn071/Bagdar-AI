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
#include <cstdint>
#include <cstring>
#include <mutex>

#include <android/log.h>

#include "net.h"
#include "datareader.h"

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

// Best-effort blob name discovery: parse the .param header to find
// the first "Input" layer's output and the last layer's first output.
// Falls back to common defaults.
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

  std::string in_name, out_name;
  size_t pos = 0;
  std::string last_line;
  while (pos < buf.size()) {
    size_t eol = buf.find('\n', pos);
    if (eol == std::string::npos) eol = buf.size();
    std::string line = buf.substr(pos, eol - pos);
    pos = eol + 1;
    if (line.empty()) continue;
    last_line = line;
    if (in_name.empty() && line.rfind("Input", 0) == 0) {
      // tokens: "Input <name> <inputs> <outputs> <output_blob>"
      size_t sp = line.find_last_of(' ');
      if (sp != std::string::npos) in_name = line.substr(sp + 1);
    }
  }
  if (!last_line.empty()) {
    size_t sp = last_line.find_last_of(' ');
    if (sp != std::string::npos) out_name = last_line.substr(sp + 1);
  }
  if (in_name.empty() || out_name.empty()) return false;
  g_state.input_blob = std::move(in_name);
  g_state.output_blob = std::move(out_name);
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

// Resize Y-plane to 256x256 grayscale and replicate across 3 channels in CHW
// layout that ncnn expects. crop_top_frac removes the upper portion of the
// frame (sky/ceiling) before resize, matching the existing TFLite preprocess.
static void preprocess_yuv_to_chw(
    const uint8_t* src_y,
    int32_t src_w,
    int32_t src_h,
    int32_t row_stride,
    float crop_top_frac,
    float* chw_out) {
  crop_top_frac = std::clamp(crop_top_frac, 0.0f, 0.9f);
  const int32_t crop_top = std::clamp(
      static_cast<int32_t>(src_h * crop_top_frac), 0, src_h - 1);
  const int32_t crop_h = std::max(1, src_h - crop_top);
  const uint8_t* base = src_y + static_cast<size_t>(crop_top) * row_stride;
  constexpr float inv255 = 1.0f / 255.0f;
  const int plane = kInputSize * kInputSize;

  for (int y = 0; y < kInputSize; ++y) {
    const int sy = std::clamp((y * crop_h) / kInputSize, 0, crop_h - 1);
    const uint8_t* row = base + static_cast<size_t>(sy) * row_stride;
    const int row_off = y * kInputSize;
    for (int x = 0; x < kInputSize; ++x) {
      const int sx = std::clamp((x * src_w) / kInputSize, 0, src_w - 1);
      const float v = static_cast<float>(row[sx]) * inv255;
      chw_out[row_off + x] = v;                  // ch 0
      chw_out[plane + row_off + x] = v;          // ch 1
      chw_out[2 * plane + row_off + x] = v;      // ch 2
    }
  }
}

extern "C" __attribute__((visibility("default"))) int32_t bagdar_ncnn_infer_yuv(
    const uint8_t* src_y,
    int32_t src_w,
    int32_t src_h,
    int32_t row_stride,
    float crop_top_frac,
    float* output,
    int32_t output_len) {
  if (!g_state.ready.load()) {
    LOGE("infer: not initialized");
    return -10;
  }
  if (src_y == nullptr || output == nullptr) return -11;
  if (src_w <= 0 || src_h <= 1 || row_stride <= 0) return -12;
  if (output_len < kInputSize * kInputSize) return -13;

  thread_local std::vector<float> chw;
  chw.resize(static_cast<size_t>(kInputSize) * kInputSize * 3);
  preprocess_yuv_to_chw(src_y, src_w, src_h, row_stride, crop_top_frac, chw.data());

  ncnn::Mat in(kInputSize, kInputSize, 3, (void*)chw.data(), sizeof(float));
  ncnn::Extractor ex = g_state.net.create_extractor();
  ex.set_num_threads(g_state.net.opt.num_threads);

  if (int ret = ex.input(g_state.input_blob.c_str(), in); ret != 0) {
    LOGE("infer: input failed (ret=%d)", ret);
    return -20;
  }

  ncnn::Mat out;
  if (int ret = ex.extract(g_state.output_blob.c_str(), out); ret != 0) {
    LOGE("infer: extract failed (ret=%d)", ret);
    return -21;
  }

  // Output is expected to be (h, w) or (1, h, w). Flatten to 256x256.
  const int oh = out.h;
  const int ow = out.w;
  if (oh <= 0 || ow <= 0) return -22;
  const int total = oh * ow;
  if (total > output_len) return -23;

  // ncnn::Mat is float internally when net.opt has fp16_storage but extracts as fp32.
  std::memcpy(output, out.data, sizeof(float) * total);

  // Pad remainder if output map is smaller than 256x256 (some MiDaS variants emit 128x128).
  if (total < kInputSize * kInputSize) {
    std::memset(output + total, 0, sizeof(float) * (kInputSize * kInputSize - total));
  }
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
