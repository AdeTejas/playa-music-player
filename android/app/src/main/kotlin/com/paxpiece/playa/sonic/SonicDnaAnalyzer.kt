package com.paxpiece.playa.sonic

import kotlin.math.*

object SonicDnaAnalyzer {
    data class Result(
        val bpm: Double?,
        val key: String?,
        val confidence: Double
    )

    fun analyze(pcm: FloatArray, sampleRate: Int): Result {
        if (pcm.isEmpty() || sampleRate <= 0) return Result(null, null, 0.0)

        val mono = pcm
        val bpm = estimateBpm(mono, sampleRate)
        val key = estimateKey(mono, sampleRate)

        val confidence = when {
            bpm != null && key != null -> 0.65
            bpm != null || key != null -> 0.45
            else -> 0.0
        }

        return Result(bpm = bpm, key = key, confidence = confidence)
    }

    /**
     * BPM estimate via simple onset-energy envelope + autocorrelation.
     * This is intentionally lightweight; good enough for many 4/4 tracks.
     */
    private fun estimateBpm(x: FloatArray, sr: Int): Double? {
        // Envelope at ~100 Hz
        val hop = (sr / 100).coerceAtLeast(1)
        val env = FloatArray(x.size / hop)
        var ei = 0
        var i = 0
        while (i + hop <= x.size && ei < env.size) {
            var sum = 0.0
            for (j in 0 until hop) {
                val v = x[i + j]
                sum += (v * v)
            }
            env[ei] = sqrt(sum / hop).toFloat()
            ei++
            i += hop
        }
        if (ei < 10) return null

        // Differentiate + half-wave rectify
        val diff = FloatArray(ei)
        for (k in 1 until ei) {
            val d = env[k] - env[k - 1]
            diff[k] = if (d > 0) d else 0f
        }

        // Normalize
        var mean = 0.0
        for (k in 0 until ei) mean += diff[k].toDouble()
        mean /= ei
        var varSum = 0.0
        for (k in 0 until ei) {
            val v = diff[k].toDouble() - mean
            varSum += v * v
        }
        val std = sqrt(varSum / ei).coerceAtLeast(1e-9)
        for (k in 0 until ei) {
            diff[k] = ((diff[k].toDouble() - mean) / std).toFloat()
        }

        // Autocorrelation search in plausible BPM range.
        // env is at ~100Hz -> lag in frames.
        val minBpm = 60
        val maxBpm = 200
        val minLag = (100.0 * 60.0 / maxBpm).roundToInt().coerceAtLeast(1) // shortest period
        val maxLag = (100.0 * 60.0 / minBpm).roundToInt().coerceAtMost(ei - 1)
        if (maxLag <= minLag) return null

        var bestLag = -1
        var bestScore = Double.NEGATIVE_INFINITY

        for (lag in minLag..maxLag) {
            var acc = 0.0
            for (k in 0 until (ei - lag)) {
                acc += diff[k].toDouble() * diff[k + lag].toDouble()
            }
            if (acc > bestScore) {
                bestScore = acc
                bestLag = lag
            }
        }

        if (bestLag <= 0) return null
        val bpm = 60.0 * 100.0 / bestLag.toDouble()

        // Snap common octave errors (double/half tempo)
        var snapped = bpm
        while (snapped < 60) snapped *= 2
        while (snapped > 200) snapped /= 2

        return snapped
    }

    /**
     * Key estimate via rough chroma extraction + Krumhansl-Schmuckler template match.
     * Returns e.g. "C Maj" or "A Min".
     */
    private fun estimateKey(x: FloatArray, sr: Int): String? {
        // Use a short-ish segment for key estimation
        val seconds = (x.size / sr.toDouble()).coerceAtMost(60.0)
        val n = (seconds * sr).roundToInt().coerceAtMost(x.size)
        if (n < sr) return null

        // Frame parameters
        val frame = 4096
        val hop = 2048
        if (n < frame + hop) return null

        val window = DoubleArray(frame) { idx -> 0.5 - 0.5 * cos(2.0 * Math.PI * idx / (frame - 1)) }

        val chroma = DoubleArray(12)
        var pos = 0
        val bufRe = DoubleArray(frame)
        val bufIm = DoubleArray(frame)

        while (pos + frame <= n) {
            for (i in 0 until frame) {
                val v = x[pos + i].toDouble() * window[i]
                bufRe[i] = v
                bufIm[i] = 0.0
            }

            // FFT in-place
            fft(bufRe, bufIm)

            // Magnitudes to chroma bins
            val binHz = sr.toDouble() / frame
            for (k in 1 until frame / 2) {
                val freq = k * binHz
                if (freq < 40.0 || freq > 5000.0) continue

                val mag = sqrt(bufRe[k] * bufRe[k] + bufIm[k] * bufIm[k])
                if (mag.isNaN() || mag.isInfinite()) continue

                val midi = 69.0 + 12.0 * log2(freq / 440.0)
                val pc = ((midi.roundToInt() % 12) + 12) % 12
                chroma[pc] += mag
            }

            pos += hop
        }

        // Normalize chroma
        val sum = chroma.sum().coerceAtLeast(1e-9)
        for (i in 0 until 12) chroma[i] /= sum

        val majorTemplate = doubleArrayOf(6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88)
        val minorTemplate = doubleArrayOf(6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17)

        var best = Double.NEGATIVE_INFINITY
        var bestRoot = 0
        var bestMode = "Maj"

        for (root in 0 until 12) {
            val majScore = corr(chroma, rotate(majorTemplate, root))
            if (majScore > best) {
                best = majScore
                bestRoot = root
                bestMode = "Maj"
            }
            val minScore = corr(chroma, rotate(minorTemplate, root))
            if (minScore > best) {
                best = minScore
                bestRoot = root
                bestMode = "Min"
            }
        }

        if (!best.isFinite()) return null

        val names = arrayOf("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")
        return "${names[bestRoot]} $bestMode"
    }

    private fun rotate(t: DoubleArray, shift: Int): DoubleArray {
        val out = DoubleArray(12)
        for (i in 0 until 12) {
            out[(i + shift) % 12] = t[i]
        }
        return out
    }

    private fun corr(a: DoubleArray, b: DoubleArray): Double {
        // Pearson correlation
        val n = 12
        var ma = 0.0
        var mb = 0.0
        for (i in 0 until n) {
            ma += a[i]
            mb += b[i]
        }
        ma /= n
        mb /= n
        var num = 0.0
        var da = 0.0
        var db = 0.0
        for (i in 0 until n) {
            val va = a[i] - ma
            val vb = b[i] - mb
            num += va * vb
            da += va * va
            db += vb * vb
        }
        val den = sqrt(da * db).coerceAtLeast(1e-12)
        return num / den
    }

    private fun log2(x: Double): Double = ln(x) / ln(2.0)

    /** Minimal radix-2 FFT for power-of-two sizes. */
    private fun fft(re: DoubleArray, im: DoubleArray) {
        val n = re.size
        var j = 0
        for (i in 1 until n) {
            var bit = n shr 1
            while (j and bit != 0) {
                j = j xor bit
                bit = bit shr 1
            }
            j = j xor bit
            if (i < j) {
                val tr = re[i]
                re[i] = re[j]
                re[j] = tr
                val ti = im[i]
                im[i] = im[j]
                im[j] = ti
            }
        }

        var len = 2
        while (len <= n) {
            val ang = -2.0 * Math.PI / len
            val wlenR = cos(ang)
            val wlenI = sin(ang)
            var i = 0
            while (i < n) {
                var wr = 1.0
                var wi = 0.0
                for (k in 0 until len / 2) {
                    val uR = re[i + k]
                    val uI = im[i + k]
                    val vR = re[i + k + len / 2] * wr - im[i + k + len / 2] * wi
                    val vI = re[i + k + len / 2] * wi + im[i + k + len / 2] * wr

                    re[i + k] = uR + vR
                    im[i + k] = uI + vI
                    re[i + k + len / 2] = uR - vR
                    im[i + k + len / 2] = uI - vI

                    val nwr = wr * wlenR - wi * wlenI
                    wi = wr * wlenI + wi * wlenR
                    wr = nwr
                }
                i += len
            }
            len = len shl 1
        }
    }
}
