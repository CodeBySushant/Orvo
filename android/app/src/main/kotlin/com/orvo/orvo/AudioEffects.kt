package com.orvo.orvo

import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer

/**
 * Process-wide holder for the Equalizer / BassBoost effects.
 *
 * FIX (#1): effects must NOT live in the Activity. The playback foreground
 * service keeps playing after the user swipes the app away, and releasing the
 * Equalizer in Activity.onDestroy() silently killed EQ while music continued.
 * This object lives as long as the process — i.e. as long as playback can
 * possibly run — so the EQ survives the UI being closed.
 */
object AudioEffects {

    private var equalizer: Equalizer? = null
    private var bassBoost: BassBoost? = null
    private var sessionId: Int = -1

    /**
     * Attaches to [sessionId], reusing existing instances when the session
     * hasn't changed (re-opening the EQ screen must not reset the effect).
     * Returns the info map the Dart side expects.
     */
    fun init(sessionId: Int): Map<String, Any> {
        if (this.sessionId != sessionId) {
            release()
            equalizer = Equalizer(0, sessionId)
            bassBoost = BassBoost(0, sessionId)
            this.sessionId = sessionId
        }
        val eq = equalizer!!
        val bands = (0 until eq.numberOfBands).map { i ->
            mapOf(
                "index" to i,
                // getCenterFreq returns milliHertz
                "centerFreq" to eq.getCenterFreq(i.toShort()) / 1000,
                "level" to eq.getBandLevel(i.toShort()).toInt()
            )
        }
        val presets = (0 until eq.numberOfPresets).map {
            eq.getPresetName(it.toShort())
        }
        return mapOf(
            "minLevel" to eq.bandLevelRange[0].toInt(),
            "maxLevel" to eq.bandLevelRange[1].toInt(),
            "bands" to bands,
            "presets" to presets
        )
    }

    fun setEnabled(enabled: Boolean) {
        equalizer?.enabled = enabled
        bassBoost?.enabled = enabled && (bassBoost?.roundedStrength ?: 0) > 0
    }

    fun setBandLevel(band: Int, level: Int) {
        equalizer?.setBandLevel(band.toShort(), level.toShort())
    }

    /** Applies a device preset; returns the resulting band levels for the UI. */
    fun usePreset(preset: Int): List<Int> {
        val eq = equalizer ?: return emptyList()
        eq.usePreset(preset.toShort())
        return (0 until eq.numberOfBands).map {
            eq.getBandLevel(it.toShort()).toInt()
        }
    }

    fun setBassBoost(strength: Int) {
        bassBoost?.setStrength(strength.toShort())
        bassBoost?.enabled = strength > 0 && (equalizer?.enabled ?: false)
    }

    fun release() {
        equalizer?.release()
        equalizer = null
        bassBoost?.release()
        bassBoost = null
        sessionId = -1
    }
}
