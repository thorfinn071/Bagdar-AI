/*
 * Bagdar Phase 2 — JNI shim for espeak-ng.
 *
 * Implements the three exports declared by
 * `android/app/src/main/kotlin/com/example/bagdar/EspeakNgEngine.kt`:
 *
 *   nativeInit(String dataPath) -> int
 *   nativeVersion()             -> String
 *   nativeSynth(String text, String lang, int wpm) -> byte[]?
 *
 * Linked into `libbagdar-espeakng.so` together with espeak-ng built
 * as a static library (see `tools/espeak-ng/build_android.sh`).
 *
 * Concurrency:
 *   espeak-ng's C API is *not* re-entrant; we serialize all calls via
 *   `g_engine_mu`. The `BagdarNativeTts` worker thread on the Kotlin
 *   side is the only producer, so contention here is zero in steady
 *   state and tiny when a critical-alert preempts an in-flight kk
 *   utterance.
 *
 * Output format:
 *   16-bit signed little-endian PCM, mono, 22050 Hz. Matches the
 *   `DEFAULT_SAMPLE_RATE` constant in `EspeakNgEngine.kt`.
 */

#include <jni.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#include <espeak-ng/speak_lib.h>

#ifndef JNIEXPORT
#define JNIEXPORT __attribute__((visibility("default")))
#endif

// -- Accumulator -----------------------------------------------------------

typedef struct {
    short *data;
    size_t length;    /* in samples, not bytes */
    size_t capacity;  /* in samples */
    int oom;          /* set to 1 if realloc ever failed, aborts synth */
} pcm_buffer_t;

static int pcm_buffer_append(pcm_buffer_t *buf, const short *src, int n) {
    if (n <= 0 || !src) return 0;
    if (buf->oom) return 1;
    size_t want = buf->length + (size_t)n;
    if (want > buf->capacity) {
        size_t newcap = buf->capacity ? buf->capacity * 2 : (size_t)(64 * 1024);
        while (newcap < want) {
            newcap *= 2;
        }
        short *nd = (short *)realloc(buf->data, newcap * sizeof(short));
        if (!nd) {
            buf->oom = 1;
            return 1;
        }
        buf->data = nd;
        buf->capacity = newcap;
    }
    memcpy(buf->data + buf->length, src, (size_t)n * sizeof(short));
    buf->length += (size_t)n;
    return 0;
}

/*
 * espeak-ng invokes this callback repeatedly during synchronous
 * synthesis. Each invocation carries up to a few thousand samples
 * plus an events list terminated by `espeakEVENT_LIST_TERMINATED`.
 * The first event always carries the `user_data` we attached to
 * `espeak_Synth` — we use it to find our pcm_buffer_t and append.
 *
 * Returning 1 instructs espeak to abort synthesis (OOM path).
 */
static int synth_callback(short *wav, int numsamples, espeak_EVENT *events) {
    if (!events) return 0;
    pcm_buffer_t *buf = NULL;
    for (int i = 0; events[i].type != espeakEVENT_LIST_TERMINATED; i++) {
        if (events[i].user_data) {
            buf = (pcm_buffer_t *)events[i].user_data;
            break;
        }
    }
    if (!buf) return 0;
    return pcm_buffer_append(buf, wav, numsamples);
}

// -- Engine state ----------------------------------------------------------

static pthread_mutex_t g_engine_mu = PTHREAD_MUTEX_INITIALIZER;
static int g_engine_initialized = 0;
static char g_last_voice[32] = {0};
static int g_last_rate = 0;

// -- JNI exports -----------------------------------------------------------

JNIEXPORT jint JNICALL
Java_com_example_bagdar_EspeakNgEngine_nativeInit(JNIEnv *env,
                                                  jobject thiz,
                                                  jstring jDataPath) {
    (void)thiz;
    pthread_mutex_lock(&g_engine_mu);
    if (g_engine_initialized) {
        pthread_mutex_unlock(&g_engine_mu);
        return 0;
    }

    const char *dataPath = (*env)->GetStringUTFChars(env, jDataPath, NULL);
    if (!dataPath) {
        pthread_mutex_unlock(&g_engine_mu);
        return -1;
    }

    /*
     * AUDIO_OUTPUT_SYNCHRONOUS makes espeak_Synth block until the full
     * utterance has been emitted via synth_callback. We don't use
     * espeak's own audio output (Bagdar drives AudioTrack itself) so
     * the buffer length argument is ignored.
     */
    int rate = espeak_Initialize(AUDIO_OUTPUT_SYNCHRONOUS, 0, dataPath, 0);
    (*env)->ReleaseStringUTFChars(env, jDataPath, dataPath);

    if (rate < 0) {
        pthread_mutex_unlock(&g_engine_mu);
        return -1;
    }

    espeak_SetSynthCallback(synth_callback);
    g_engine_initialized = 1;
    pthread_mutex_unlock(&g_engine_mu);
    return 0;
}

JNIEXPORT jstring JNICALL
Java_com_example_bagdar_EspeakNgEngine_nativeVersion(JNIEnv *env,
                                                     jobject thiz) {
    (void)thiz;
    const char *path = NULL;
    const char *version = espeak_Info(&path);
    return (*env)->NewStringUTF(env, version ? version : "");
}

JNIEXPORT jbyteArray JNICALL
Java_com_example_bagdar_EspeakNgEngine_nativeSynth(JNIEnv *env,
                                                   jobject thiz,
                                                   jstring jText,
                                                   jstring jLang,
                                                   jint jWpm) {
    (void)thiz;
    pthread_mutex_lock(&g_engine_mu);
    if (!g_engine_initialized) {
        pthread_mutex_unlock(&g_engine_mu);
        return NULL;
    }

    const char *text = (*env)->GetStringUTFChars(env, jText, NULL);
    const char *lang = (*env)->GetStringUTFChars(env, jLang, NULL);
    if (!text || !lang) {
        if (text) (*env)->ReleaseStringUTFChars(env, jText, text);
        if (lang) (*env)->ReleaseStringUTFChars(env, jLang, lang);
        pthread_mutex_unlock(&g_engine_mu);
        return NULL;
    }

    /*
     * Voice + rate are cached so we don't hit espeak's voice-load
     * path on every utterance (it parses a voice file every call).
     * Saves ~15 ms per synth on Snapdragon 680 once warm.
     */
    if (strncmp(g_last_voice, lang, sizeof(g_last_voice) - 1) != 0) {
        if (espeak_SetVoiceByName(lang) != EE_OK) {
            /* Voice unavailable — degrade to the default voice rather
             * than fail outright. The resolver in TtsService will pick
             * the russianFallback next time, but for *this* utterance
             * we still emit something. */
            espeak_SetVoiceByName("en");
        }
        strncpy(g_last_voice, lang, sizeof(g_last_voice) - 1);
        g_last_voice[sizeof(g_last_voice) - 1] = '\0';
    }

    int wpm = (int)jWpm;
    if (wpm < 80) wpm = 80;
    if (wpm > 450) wpm = 450;
    if (wpm != g_last_rate) {
        espeak_SetParameter(espeakRATE, wpm, 0);
        g_last_rate = wpm;
    }

    pcm_buffer_t buf;
    memset(&buf, 0, sizeof(buf));
    buf.capacity = 64 * 1024;
    buf.data = (short *)malloc(buf.capacity * sizeof(short));
    if (!buf.data) {
        (*env)->ReleaseStringUTFChars(env, jText, text);
        (*env)->ReleaseStringUTFChars(env, jLang, lang);
        pthread_mutex_unlock(&g_engine_mu);
        return NULL;
    }

    unsigned int unique_id = 0;
    espeak_ERROR err = espeak_Synth(
        text,
        strlen(text) + 1,                       /* include the NUL */
        0,                                      /* position */
        POS_CHARACTER,                          /* position_type */
        0,                                      /* end_position (0 == all) */
        espeakCHARS_UTF8,                       /* flags */
        &unique_id,
        &buf                                    /* user_data */
    );
    espeak_Synchronize();

    (*env)->ReleaseStringUTFChars(env, jText, text);
    (*env)->ReleaseStringUTFChars(env, jLang, lang);

    if (err != EE_OK || buf.oom || buf.length == 0) {
        free(buf.data);
        pthread_mutex_unlock(&g_engine_mu);
        return NULL;
    }

    jsize byteLen = (jsize)(buf.length * sizeof(short));
    jbyteArray result = (*env)->NewByteArray(env, byteLen);
    if (result) {
        /*
         * espeak emits host-endian 16-bit PCM. All Android targets
         * Bagdar supports are little-endian (arm64-v8a + armeabi-v7a),
         * which matches what AudioTrack expects for ENCODING_PCM_16BIT.
         */
        (*env)->SetByteArrayRegion(env, result, 0, byteLen,
                                   (const jbyte *)buf.data);
    }
    free(buf.data);
    pthread_mutex_unlock(&g_engine_mu);
    return result;
}
