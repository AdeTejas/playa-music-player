package com.paxpiece.playa.sonic

import android.content.Context
import android.media.*
import android.net.Uri
import kotlin.math.min

object PcmDecode {
    data class Decoded(val pcm: FloatArray, val sampleRate: Int)

    /**
     * Decode to mono float PCM ([-1,1]) using MediaExtractor/MediaCodec.
     * Best-effort: works for formats supported by device decoders.
     */
    fun decodeToMonoFloat(
        context: Context,
        uriString: String,
        maxSeconds: Int = 90,
        targetSampleRate: Int = 11025,
    ): Decoded {
        val uri = if (uriString.startsWith("content://") || uriString.startsWith("file://")) {
            Uri.parse(uriString)
        } else {
            // Treat as filesystem path
            Uri.fromFile(java.io.File(uriString))
        }

        val extractor = MediaExtractor()
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
        require(trackIndex >= 0 && format != null) { "No audio track" }
        extractor.selectTrack(trackIndex)

        val mime = format!!.getString(MediaFormat.KEY_MIME)!!
        val codec = MediaCodec.createDecoderByType(mime)
        codec.configure(format, null, null, 0)
        codec.start()

        val inputInfo = MediaCodec.BufferInfo()
        val outputInfo = MediaCodec.BufferInfo()

        val inSr = format!!.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val inCh = format!!.getInteger(MediaFormat.KEY_CHANNEL_COUNT)

        // Read up to maxSeconds worth of input based on timeUs
        val maxUs = maxSeconds.toLong() * 1_000_000L

        val floats = ArrayList<Float>(targetSampleRate * maxSeconds)

        var sawInputEos = false
        var sawOutputEos = false

        // Resampler state: naive decimate/average to targetSampleRate
        // Good enough for analysis.
        val ratio = inSr.toDouble() / targetSampleRate.toDouble()

        while (!sawOutputEos) {
            if (!sawInputEos) {
                val inIndex = codec.dequeueInputBuffer(10_000)
                if (inIndex >= 0) {
                    val inBuf = codec.getInputBuffer(inIndex)!!
                    val size = extractor.readSampleData(inBuf, 0)
                    val timeUs = extractor.sampleTime
                    if (size < 0 || timeUs < 0 || timeUs > maxUs) {
                        codec.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        sawInputEos = true
                    } else {
                        codec.queueInputBuffer(inIndex, 0, size, timeUs, 0)
                        extractor.advance()
                    }
                }
            }

            val outIndex = codec.dequeueOutputBuffer(outputInfo, 10_000)
            when {
                outIndex >= 0 -> {
                    if (outputInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        sawOutputEos = true
                    }

                    val outBuf = codec.getOutputBuffer(outIndex)!!
                    val chunk = ByteArray(outputInfo.size)
                    outBuf.position(outputInfo.offset)
                    outBuf.limit(outputInfo.offset + outputInfo.size)
                    outBuf.get(chunk)

                    // Assume PCM 16-bit if decoded; most decoders output PCM 16.
                    // Android can also output float on newer APIs, but we'll handle 16-bit here.
                    val pcm16 = ShortArray(chunk.size / 2)
                    var si = 0
                    var bi = 0
                    while (bi + 1 < chunk.size) {
                        val lo = chunk[bi].toInt() and 0xFF
                        val hi = chunk[bi + 1].toInt()
                        pcm16[si] = ((hi shl 8) or lo).toShort()
                        si++
                        bi += 2
                    }

                    // Downmix to mono and resample
                    // Interleaved per channel.
                    val frames = pcm16.size / inCh
                    var frameIndex = 0
                    var outFrame = 0
                    while (frameIndex < frames) {
                        // Naive resample: pick closest input frame.
                        val wantIn = (outFrame * ratio).toInt()
                        if (wantIn >= frames) break

                        var acc = 0
                        val base = wantIn * inCh
                        for (c in 0 until inCh) {
                            acc += pcm16[base + c].toInt()
                        }
                        val mono = acc.toFloat() / inCh.toFloat()
                        floats.add(mono / 32768f)

                        outFrame++
                        frameIndex = wantIn + 1
                    }

                    codec.releaseOutputBuffer(outIndex, false)

                    // Stop if we already have enough samples
                    if (floats.size >= targetSampleRate * maxSeconds) {
                        sawOutputEos = true
                    }
                }
                outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    // ignore
                }
            }
        }

        try {
            codec.stop()
        } catch (_: Exception) {
        }
        codec.release()
        extractor.release()

        val out = FloatArray(floats.size)
        for (k in floats.indices) out[k] = floats[k]

        return Decoded(out, targetSampleRate)
    }
}
