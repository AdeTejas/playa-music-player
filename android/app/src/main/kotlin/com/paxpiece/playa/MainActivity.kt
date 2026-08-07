package com.paxpiece.playa

import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.PresetReverb
import android.media.audiofx.Virtualizer
import com.ryanheise.audioservice.AudioServiceActivity
import com.paxpiece.playa.sonic.PcmDecode
import com.paxpiece.playa.sonic.SonicDnaAnalyzer
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "com.paxpiece.playa/equalizer"
    private val SONIC_CHANNEL = "com.paxpiece.playa/sonic_dna"
    private val WAVEFORM_CHANNEL = "com.paxpiece.playa/fast_waveform"

    // Index-aligned with android.media.audiofx.PresetReverb PRESET_* constants
    // (PRESET_NONE=0 … PRESET_PLATE=6).
    private val PRESET_REVERB_NAMES = listOf(
        "None", "Small Room", "Medium Room", "Large Room",
        "Medium Hall", "Large Hall", "Plate",
    )

    private var equalizer: Equalizer? = null
    private var virtualizer: Virtualizer? = null
    private var bassBoost: BassBoost? = null
    private var presetReverb: PresetReverb? = null

    private fun releaseAudioEffects() {
        try { equalizer?.release() } catch (_: Exception) {}
        try { virtualizer?.release() } catch (_: Exception) {}
        try { bassBoost?.release() } catch (_: Exception) {}
        try { presetReverb?.release() } catch (_: Exception) {}
        equalizer = null
        virtualizer = null
        bassBoost = null
        presetReverb = null
    }

    private fun initAudioEffects(sessionId: Int) {
        releaseAudioEffects()
        try {
            equalizer = Equalizer(0, sessionId)
            equalizer?.enabled = true
        } catch (_: Exception) { equalizer = null }
        try {
            virtualizer = Virtualizer(0, sessionId)
            virtualizer?.enabled = false
        } catch (_: Exception) { virtualizer = null }
        try {
            bassBoost = BassBoost(0, sessionId)
            bassBoost?.enabled = false
        } catch (_: Exception) { bassBoost = null }
        try {
            presetReverb = PresetReverb(0, sessionId)
            presetReverb?.enabled = false
        } catch (_: Exception) { presetReverb = null }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "initializeEqualizer" -> {
                        val sessionId = call.argument<Int>("audioSessionId") ?: 0
                        initAudioEffects(sessionId)
                        result.success(null)
                    }
                    "getEqualizerBands" -> {
                        result.success(equalizer?.numberOfBands?.toInt() ?: 0)
                    }
                    "getBandLevelRange" -> {
                        val range = equalizer?.bandLevelRange
                        if (range != null) {
                            result.success(listOf(range[0].toInt(), range[1].toInt()))
                        } else {
                            result.error("EQ_ERROR", "Equalizer not initialized", null)
                        }
                    }
                    "getBandLevel" -> {
                        val band = call.argument<Int>("band") ?: 0
                        result.success(equalizer?.getBandLevel(band.toShort())?.toInt() ?: 0)
                    }
                    "getAllBandLevels" -> {
                        val bands = equalizer?.numberOfBands ?: 0
                        val levels = ArrayList<Int>()
                        for (i in 0 until bands) {
                            levels.add(equalizer?.getBandLevel(i.toShort())?.toInt() ?: 0)
                        }
                        result.success(levels)
                    }
                    "getBandCenterFrequencies" -> {
                        val bands = equalizer?.numberOfBands ?: 0
                        val freqs = ArrayList<Int>()
                        for (i in 0 until bands) {
                            freqs.add(equalizer?.getCenterFreq(i.toShort())?.toInt() ?: 0)
                        }
                        result.success(freqs)
                    }
                    "setBandLevel" -> {
                        val band = call.argument<Int>("band") ?: 0
                        val level = call.argument<Int>("level") ?: 0
                        equalizer?.setBandLevel(band.toShort(), level.toShort())
                        result.success(null)
                    }
                    "getPresetNames" -> {
                        val presets = equalizer?.numberOfPresets ?: 0
                        val names = ArrayList<String>()
                        for (i in 0 until presets) {
                            names.add(equalizer?.getPresetName(i.toShort()) ?: "Preset $i")
                        }
                        result.success(names)
                    }
                    "usePreset" -> {
                        val preset = call.argument<Int>("preset") ?: 0
                        equalizer?.usePreset(preset.toShort())
                        result.success(null)
                    }
                    "getCurrentPreset" -> {
                        result.success(equalizer?.currentPreset?.toInt() ?: -1)
                    }
                    "setEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        equalizer?.enabled = enabled
                        result.success(null)
                    }
                    "isEnabled" -> {
                        result.success(equalizer?.enabled ?: false)
                    }
                    "getVirtualizerSupported" -> {
                        result.success(virtualizer?.strengthSupported ?: false)
                    }
                    "getVirtualizerStrength" -> {
                        result.success(virtualizer?.getRoundedStrength()?.toInt() ?: 0)
                    }
                    "setVirtualizerStrength" -> {
                        val strength = call.argument<Int>("strength") ?: 0
                        virtualizer?.setStrength(strength.toShort())
                        result.success(null)
                    }
                    "isVirtualizerEnabled" -> {
                        result.success(virtualizer?.enabled ?: false)
                    }
                    "setVirtualizerEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        virtualizer?.enabled = enabled
                        result.success(null)
                    }
                    "getBassBoostSupported" -> {
                        result.success(bassBoost?.strengthSupported ?: false)
                    }
                    "getBassBoostStrength" -> {
                        result.success(bassBoost?.getRoundedStrength()?.toInt() ?: 0)
                    }
                    "setBassBoostStrength" -> {
                        val strength = call.argument<Int>("strength") ?: 0
                        bassBoost?.setStrength(strength.toShort())
                        result.success(null)
                    }
                    "isBassBoostEnabled" -> {
                        result.success(bassBoost?.enabled ?: false)
                    }
                    "setBassBoostEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        bassBoost?.enabled = enabled
                        result.success(null)
                    }
                    "getPresetReverbPresets" -> {
                        result.success(PRESET_REVERB_NAMES.toList())
                    }
                    "getCurrentPresetReverb" -> {
                        result.success(presetReverb?.preset?.toInt() ?: 0)
                    }
                    "usePresetReverb" -> {
                        val preset = call.argument<Int>("preset") ?: 0
                        presetReverb?.preset = preset.toShort()
                        result.success(null)
                    }
                    "isPresetReverbEnabled" -> {
                        result.success(presetReverb?.enabled ?: false)
                    }
                    "setPresetReverbEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        presetReverb?.enabled = enabled
                        result.success(null)
                    }
                    "release" -> {
                        releaseAudioEffects()
                        result.success(null)
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            } catch (e: Exception) {
                result.error("EQ_ERROR", e.message, null)
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SONIC_CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "analyzeTrack" -> {
                        val uri = call.argument<String>("uri") ?: ""
                        val maxSeconds = call.argument<Int>("maxSeconds") ?: 90
                        val targetSampleRate = call.argument<Int>("targetSampleRate") ?: 11025

                        if (uri.isBlank()) {
                            result.success(mapOf("bpm" to null, "key" to null, "confidence" to 0.0))
                            return@setMethodCallHandler
                        }

                        // Run decode+analysis off the UI thread.
                        Thread {
                            try {
                                val decoded = PcmDecode.decodeToMonoFloat(
                                    context = this,
                                    uriString = uri,
                                    maxSeconds = maxSeconds,
                                    targetSampleRate = targetSampleRate,
                                )
                                val r = SonicDnaAnalyzer.analyze(decoded.pcm, decoded.sampleRate)
                                result.success(mapOf(
                                    "bpm" to r.bpm,
                                    "key" to r.key,
                                    "confidence" to r.confidence,
                                ))
                            } catch (e: Exception) {
                                result.success(mapOf("bpm" to null, "key" to null, "confidence" to 0.0))
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.success(mapOf("bpm" to null, "key" to null, "confidence" to 0.0))
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WAVEFORM_CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "extractWaveform" -> {
                        val path = call.argument<String>("path") ?: ""
                        val samples = call.argument<Int>("samples") ?: 300
                        val maxMillis = call.argument<Int>("maxMillis")?.toLong() ?: 600_000L
                        if (path.isBlank()) {
                            result.error("NO_PATH", "path is required", null)
                            return@setMethodCallHandler
                        }
                        // Decode + RMS bucketing run on a background thread inside the
                        // extractor; the result resolves exactly once when done.
                        FastWaveformExtractor(this, path, samples, maxMillis, result).start()
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("WAVEFORM_ERROR", e.message, null)
            }
        }
    }

    override fun onDestroy() {
        releaseAudioEffects()
        super.onDestroy()
    }
}
