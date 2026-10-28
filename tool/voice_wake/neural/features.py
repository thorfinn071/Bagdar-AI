"""Reference single-utterance input gate and raw-waveform log-mel contract."""
import numpy as np

SAMPLE_RATE = 16000
WINDOW = 32000

def prepare_window(signal, jitter=0):
    signal = np.asarray(signal, dtype=np.float32)
    if signal.ndim != 1 or len(signal) == 0 or not np.isfinite(signal).all() or np.max(np.abs(signal)) > 1.01:
        return np.zeros(WINDOW, np.float32), False
    # Energy gate only segments an utterance. It is not a speech/word classifier.
    frames = np.pad(signal, (0, (-len(signal)) % 160)).reshape(-1, 160)
    rms = np.sqrt(np.mean(frames ** 2, axis=1))
    peak = float(np.max(rms))
    if peak < .003:
        return np.zeros(WINDOW, np.float32), False
    voiced = np.flatnonzero(rms >= max(.003, peak * .08))
    start = max(0, int(voiced[0]) * 160 - 320)
    end = min(len(signal), (int(voiced[-1]) + 1) * 160 + 320)
    speech = signal[start:end]
    if len(speech) < 2560 or len(speech) > 28800:
        return np.zeros(WINDOW, np.float32), False
    # RMS normalization and fixed-size centered padding; no test-time stretching.
    speech = np.clip(speech / max(float(np.sqrt(np.mean(speech ** 2))), .01) * .15, -1, 1)
    result = np.zeros(WINDOW, np.float32)
    offset = max(0, min(WINDOW - len(speech), (WINDOW - len(speech)) // 2 + jitter))
    result[offset:offset + len(speech)] = speech
    return result, True

def log_mel(waves):
    import tensorflow as tf
    waves = tf.convert_to_tensor(waves, tf.float32)
    spectrum = tf.signal.stft(waves, frame_length=400, frame_step=160, fft_length=512,
        window_fn=tf.signal.hann_window, pad_end=False)
    power = tf.math.square(tf.abs(spectrum))
    matrix = tf.signal.linear_to_mel_weight_matrix(40, 257, 16000, 80.0, 7600.0)
    mel = tf.math.log(tf.maximum(tf.matmul(power, matrix), 1e-6))
    mean, variance = tf.nn.moments(mel, axes=[1, 2], keepdims=True)
    return ((mel - mean) / tf.sqrt(variance + 1e-5))[..., None]

def augment(signal, rng):
    from scipy.signal import resample_poly, lfilter
    # Pitch and speaking speed vary together; this is not a natural new speaker.
    ratio = int(rng.uniform(.88, 1.12) * 100)
    result = resample_poly(signal, 100, ratio).astype(np.float32)
    if rng.random() < .5:
        impulse = np.zeros(int(rng.uniform(.02, .09) * SAMPLE_RATE), np.float32)
        impulse[0] = 1
        positions = rng.integers(1, len(impulse), 5)
        impulse[positions] = rng.uniform(-.12, .12, 5)
        result = lfilter(impulse, [1.0], result).astype(np.float32)
    power = float(np.sqrt(np.mean(result ** 2)))
    if power > 0:
        noise = rng.normal(0, power / (10 ** (rng.uniform(12, 35) / 20)), len(result)).astype(np.float32)
        result = result + noise
    result *= rng.uniform(.5, 1.4)
    return np.clip(result, -.99, .99)
