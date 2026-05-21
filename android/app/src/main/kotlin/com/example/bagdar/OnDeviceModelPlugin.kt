package com.example.bagdar

import android.content.Context
import io.flutter.plugin.common.MethodChannel

/// Stub plugin for the on-device VLM (visual language model) inference
/// engine. Registers the `bagdar/vlm_engine` MethodChannel so the Dart
/// `SceneQuestionService` does not throw `MissingPluginException`.
///
/// Phase 4 — Direction 11. The actual llama.cpp / MobileVLM / MiniCPM
/// inference backend is a future deliverable gated on model pack
/// download, free-space, and device capability. Until a model pack is
/// installed and the backend is linked, this plugin returns `false` for
/// `loadVlmModel`, causing `SceneQuestionService` to fall back
/// gracefully to the template-based `SceneNarrator` path.
///
/// Channel: bagdar/vlm_engine
/// Methods handled:
///   loadVlmModel  → false  (no model installed)
///   inferVlm      → null   (guarded: only called after loadVlmModel succeeds)
///   cancelVlm     → null
///   unloadVlmModel → null
@Suppress("UNUSED_PARAMETER")
class OnDeviceModelPlugin(private val context: Context) {

    fun register(channel: MethodChannel) {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "loadVlmModel" -> {
                    // Signal that no model pack is installed. SceneQuestionService
                    // logs 'load_failed' and remains on the SceneNarrator fallback.
                    result.success(false)
                }
                "inferVlm" -> {
                    // Should not be reached without a loaded model, but return null
                    // so SceneQuestionService's catch-all triggers the fallback TTS.
                    result.success(null)
                }
                "cancelVlm" -> result.success(null)
                "unloadVlmModel" -> result.success(null)
                else -> result.notImplemented()
            }
        }
    }
}
