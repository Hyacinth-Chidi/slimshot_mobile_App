package com.techfamz.slimshotai.homewidget

/**
 * Taps waiting for the app's Dart side. The one the app was started with is
 * kept until Dart asks for it ([take]) — once — and a tap that arrives before
 * Dart is listening is kept the same way, the last one winning; after that a
 * tap goes straight on ([arrive]). Main thread only.
 */
class LaunchMailbox(start: Map<String, Any?>?) {

    private var kept: Map<String, Any?>? = start
    private var listening = false

    /** Dart asking, which also says it is listening now. */
    fun take(): Map<String, Any?>? {
        listening = true
        return kept.also { kept = null }
    }

    /** The tap to send now, or null while it is kept for [take]. */
    fun arrive(action: Map<String, Any?>): Map<String, Any?>? {
        if (listening) return action
        kept = action
        return null
    }
}
