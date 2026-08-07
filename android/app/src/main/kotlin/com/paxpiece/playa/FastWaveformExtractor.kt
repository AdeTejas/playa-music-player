package com.paxpiece.playa

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.math.sqrt

/**
 * Fast full-file RMS waveform extraction via MediaExtractor + MediaCodec.
 *
 * audio_waveforms' native extractor decodes the whole file but ships every
 * RMS bucket over the main thread as it goes (~14x realtime on Android), which
 * makes long audiobook chapters structurally impossible — a 2h chapter needs
 * 5+ minutes and would jank the UI the whole time. This extractor runs the
 * decode on a background thread, accumulates RMS into [samples] buckets
 * natively, and returns a single result when done. No per-bucket traffic, no
 * main-thread throttle.
 *
 * Single-flight: starting a new extraction cancels the previous one, and the
 * cancelled call resolves with null so the Dart future can't leak.
 */
class FastWaveformExtractor(
    private val context: Context,
    private val path: String,
    private val samples: Int,
    private val maxMillis: Long,
    private val result: MethodChannel.Result,
) {
    @Volatile
    private var cancelled = false
    private var thread: Thread? = null

    companion object {
        @Volatile
        private var current: FastWaveformExtractor? = null

        fun cancelCurrent() {
            current?.cancel()
        }
    }

    fun start() {
        cancelCurrent()
        current = this
        thread = Thread(::run, "fast-waveform-extract").apply {
            isDaemon = true
            start()
        }
    }

    fun cancel() {
        cancelled = true
        thread?.interrupt()
    }

    private fun run() {
        val startedAt = SystemClock.elapsedRealtime()
        var extractor: MediaExtractor? = null
        var codec: MediaCodec? = null
        try {
            val uri = if (path.startsWith("content://") || path.startsWith("file://")) {
                Uri.parse(path)
            } else {
                Uri.fromFile(File(path))
            }
            extractor = MediaExtractor()
            extractor.setDataSource(context, uri, null)

            var trackIndex = -1
            var format: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                val mime = f.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    trackIndex = i
                    format = f
                    break
                }
            }
            if (trackIndex < 0 || format == null) {
                result.error("NO_AUDIO_TRACK", "No audio track found", null)
                return
            }
            extractor.selectTrack(trackIndex)

            val durationUs =
                if (format.containsKey(MediaFormat.KEY_DURATION)) {
                    format.getLong(MediaFormat.KEY_DURATION)
                } else {
                    0L
                }
            // Decode cost scales with audio duration (MP3 soft-decode ~14x
            // realtime on this device). Budget = duration/8 + 45s margin,
            // bounded by the Dart-side cap (maxMillis). Self-limiting here from
            // the container duration means the Dart cap never truncates a
            // legitimate extraction early.
            val selfBudgetMs =
                if (durationUs > 0) {
                    (durationUs / 8000L + 45_000L).coerceIn(60_000L, maxMillis)
                } else {
                    maxMillis
                }
            val deadline = startedAt + selfBudgetMs
            val mime = format.getString(MediaFormat.KEY_MIME) ?: "audio/mpeg"
            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(format, null, null, 0)
            codec.start()

            val outputInfo = MediaCodec.BufferInfo()

            var sampleRate = 0
            var channels = 1
            var pcmBits = 16
            var sawInputEos = false
            var sawOutputEos = false
            var decodedFrames = 0L
            var totalSamples = 0L

            val bucketCount = samples.coerceIn(16, 2000)
            val sumSq = DoubleArray(bucketCount)
            val counts = LongArray(bucketCount)

            while (!sawOutputEos) {
                if (cancelled || SystemClock.elapsedRealtime() > deadline) {
                    break
                }

                if (!sawInputEos) {
                    val inIndex = codec.dequeueInputBuffer(10_000)
                    if (inIndex >= 0) {
                        val inBuf = codec.getInputBuffer(inIndex)!!
                        val size = extractor.readSampleData(inBuf, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(
                                inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            sawInputEos = true
                        } else {
                            codec.queueInputBuffer(inIndex, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                val outIndex = codec.dequeueOutputBuffer(outputInfo, 10_000)
                when (outIndex) {
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val f = codec.outputFormat
                        sampleRate =
                            if (f.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                                f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                            } else {
                                0
                            }
                        channels =
                            if (f.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                                f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                            } else {
                                1
                            }
                        pcmBits = decodePcmBits(f)
                        totalSamples = (sampleRate.toLong() * durationUs) / 1_000_000L
                    }
                    else -> {
                        if (outIndex >= 0) {
                            if (outputInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                                sawOutputEos = true
                            }
                            if (outputInfo.size > 0) {
                                val outBuf = codec.getOutputBuffer(outIndex)!!
                                // Copy once, then iterate the array — per-sample
                                // ByteBuffer.get() calls are JNI-bound and crush
                                // throughput on a 2h book (~635M samples).
                                val chunk = ByteArray(outputInfo.size)
                                outBuf.position(outputInfo.offset)
                                outBuf.limit(outputInfo.offset + outputInfo.size)
                                outBuf.get(chunk)
                                decodedFrames = accumulate(
                                    chunk, pcmBits, channels,
                                    totalSamples, decodedFrames, bucketCount, sumSq, counts,
                                )
                            }
                            codec.releaseOutputBuffer(outIndex, false)
                        }
                    }
                }
            }

            val timedOut = SystemClock.elapsedRealtime() > deadline
            releaseQuietly(codec, extractor)
            codec = null
            extractor = null

            if (cancelled) {
                result.success(null)
                return
            }

            if (timedOut || counts.all { it == 0L }) {
                result.success(null)
                return
            }

            val buckets = FloatArray(bucketCount)
            for (i in 0 until bucketCount) {
                buckets[i] = sqrt((sumSq[i] / counts[i]).toFloat())
            }
            result.success(buckets.toList())
        } catch (e: Exception) {
            releaseQuietly(codec, extractor)
            result.error("EXTRACT_ERROR", e.message, null)
        } finally {
            if (current === this) current = null
        }
    }

    private fun decodePcmBits(format: MediaFormat): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
            format.containsKey(MediaFormat.KEY_PCM_ENCODING)
        ) {
            return when (format.getInteger(MediaFormat.KEY_PCM_ENCODING)) {
                AudioFormat.ENCODING_PCM_8BIT -> 8
                AudioFormat.ENCODING_PCM_FLOAT -> 32
                else -> 16
            }
        }
        return 16
    }

    private fun accumulate(
        chunk: ByteArray,
        pcmBits: Int,
        channels: Int,
        totalSamples: Long,
        startFrame: Long,
        bucketCount: Int,
        sumSq: DoubleArray,
        counts: LongArray,
    ): Long {
        var frame = startFrame
        when (pcmBits) {
            8 -> {
                var i = 0
                val n = chunk.size
                while (i < n) {
                    var acc = 0
                    var c = 0
                    while (c < channels && i < n) {
                        acc += (chunk[i].toInt() and 0xFF) - 128
                        i++
                        c++
                    }
                    addSample(acc.toFloat() / channels, 128f, frame, totalSamples, bucketCount, sumSq, counts)
                    frame++
                }
            }
            32 -> {
                var i = 0
                val n = chunk.size / 4
                while (i < n) {
                    var acc = 0f
                    var c = 0
                    while (c < channels && i < n) {
                        val o = i * 4
                        val bits =
                            (chunk[o].toInt() and 0xFF) or
                                ((chunk[o + 1].toInt() and 0xFF) shl 8) or
                                ((chunk[o + 2].toInt() and 0xFF) shl 16) or
                                ((chunk[o + 3].toInt() and 0xFF) shl 24)
                        acc += Float.fromBits(bits)
                        i++
                        c++
                    }
                    addSample(acc / channels, 1f, frame, totalSamples, bucketCount, sumSq, counts)
                    frame++
                }
            }
            else -> {
                var i = 0
                val n = chunk.size / 2
                while (i < n) {
                    var acc = 0
                    var c = 0
                    while (c < channels && i < n) {
                        val o = i * 2
                        val lo = chunk[o].toInt() and 0xFF
                        val hi = chunk[o + 1].toInt()
                        acc += (hi shl 8) or lo
                        i++
                        c++
                    }
                    addSample(acc.toFloat() / channels, 32768f, frame, totalSamples, bucketCount, sumSq, counts)
                    frame++
                }
            }
        }
        return frame
    }

    private fun addSample(
        value: Float,
        scale: Float,
        frame: Long,
        totalSamples: Long,
        bucketCount: Int,
        sumSq: DoubleArray,
        counts: LongArray,
    ) {
        val d = (value / scale).toDouble()
        val idx = if (totalSamples > 0) {
            var i = ((frame * bucketCount) / totalSamples).toInt()
            if (i >= bucketCount) i = bucketCount - 1
            i
        } else {
            0
        }
        sumSq[idx] += d * d
        counts[idx]++
    }

    private fun releaseQuietly(codec: MediaCodec?, extractor: MediaExtractor?) {
        try {
            codec?.stop()
        } catch (_: Exception) {
        }
        try {
            codec?.release()
        } catch (_: Exception) {
        }
        try {
            extractor?.release()
        } catch (_: Exception) {
        }
    }
}
