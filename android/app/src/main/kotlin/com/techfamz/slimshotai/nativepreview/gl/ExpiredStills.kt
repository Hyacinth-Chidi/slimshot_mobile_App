package com.techfamz.slimshotai.nativepreview.gl

/**
 * Which uploaded stills an export can free at an instant.
 *
 * A still's texture used to live until the whole export ended, so a project
 * carrying a hundred captions held a hundred text atlases on the GPU at once —
 * hundreds of megabytes on the low-end parts this app runs on. The export's
 * clock only walks forward, so a path every overlay has finished with is never
 * needed again. A path a later overlay still uses (a photo placed twice) is
 * kept, or it would be decoded and uploaded a second time.
 */
internal object ExpiredStills {

    data class Span(val path: String, val endSeconds: Double)

    fun releasable(spans: List<Span>, t: Double): Set<String> {
        val finished = mutableSetOf<String>()
        val inUse = mutableSetOf<String>()
        for (span in spans) {
            if (t >= span.endSeconds) finished += span.path else inUse += span.path
        }
        return finished - inUse
    }
}
