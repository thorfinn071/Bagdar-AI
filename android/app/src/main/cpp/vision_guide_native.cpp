#include <algorithm>
#include <array>
#include <cstdint>
#include <cstddef>

#include <android/log.h>

namespace {
constexpr int kInputSize = 256;
constexpr int kInputChannels = 3;
constexpr int kRequiredOutputLength = kInputSize * kInputSize * kInputChannels;
constexpr float kInv255 = 1.0f / 255.0f;
}

extern "C" __attribute__((visibility("default"))) int32_t vg_preprocess_y_plane_to_f32(
    const uint8_t* yBytes,
    int32_t srcWidth,
    int32_t srcHeight,
    int32_t rowStride,
    float cropTopFrac,
    float* outBuffer,
    int32_t outLength) {
  if (yBytes == nullptr || outBuffer == nullptr) {
    return 0;
  }
  if (srcWidth <= 0 || srcHeight <= 1 || rowStride <= 0) {
    return 0;
  }
  if (outLength < kRequiredOutputLength) {
    return 0;
  }

  cropTopFrac = std::clamp(cropTopFrac, 0.0f, 0.9f);
  const int32_t cropTop = std::clamp(static_cast<int32_t>(srcHeight * cropTopFrac), 0, srcHeight - 1);
  const int32_t cropHeight = std::max(1, srcHeight - cropTop);
  const uint8_t* cropPtr = yBytes + static_cast<size_t>(cropTop) * static_cast<size_t>(rowStride);

  thread_local std::array<uint8_t, kInputSize * kInputSize> gray{};
  for (int y = 0; y < kInputSize; ++y) {
    const int srcY = std::clamp((y * cropHeight) / kInputSize, 0, cropHeight - 1);
    const uint8_t* srcRow = cropPtr + static_cast<size_t>(srcY) * static_cast<size_t>(rowStride);
    const size_t outRowOffset = static_cast<size_t>(y) * static_cast<size_t>(kInputSize);
    for (int x = 0; x < kInputSize; ++x) {
      const int srcX = std::clamp((x * srcWidth) / kInputSize, 0, srcWidth - 1);
      gray[outRowOffset + static_cast<size_t>(x)] = srcRow[srcX];
    }
  }

  int outIndex = 0;
  for (int i = 0; i < kInputSize * kInputSize; ++i) {
    const float value = static_cast<float>(gray[static_cast<size_t>(i)]) * kInv255;
    outBuffer[outIndex++] = value;
    outBuffer[outIndex++] = value;
    outBuffer[outIndex++] = value;
  }

  return 1;
}
