package com.paxpiece.playa

import android.media.audiofx.Equalizer
import androidx.annotation.NonNull
import com.ryanheise.audioservice.AudioServiceActivity
import com.paxpiece.playa.sonic.PcmDecode
import com.paxpiece.playa.sonic.SonicDnaAnalyzer
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "com.paxpiece.playa/equalizer"
    private val SONIC_CHANNEL = "com.paxpiece.playa/sonic_dna"
    private var equalizer: Equalizer? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "initializeEqualizer" -> {
                        val sessionId = call.argument<Int>("audioSessionId") ?: 0
                        if (equalizer != null) {
                            equalizer?.release()
                        }
                        equalizer = Equalizer(0, sessionId)
                        equalizer?.enabled = true
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
                    "release" -> {
                        equalizer?.release()
                        equalizer = null
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
    }

    override fun onDestroy() {
        equalizer?.release()
        super.onDestroy()
    }
}
