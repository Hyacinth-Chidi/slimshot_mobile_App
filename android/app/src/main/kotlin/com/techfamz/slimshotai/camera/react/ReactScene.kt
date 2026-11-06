package com.techfamz.slimshotai.camera.react

/**
 * What the live recorder draws: your camera, and the video over its place.
 *
 * The layout rules live in Dart (`reactionScene`, from `reactionPlaces`, the
 * rules the reaction made afterwards is rendered by); they arrive here as
 * rects and the recorder only draws them, so there is no second copy of the
 * layout to drift.
 */

/** A rect as fractions, y down: of the frame for a `dst`, of the upright picture for a `src`. */
internal data class ReactRect(val left: Float, val top: Float, val width: Float, val height: Float)

/** One picture: where it goes, and the part of it shown there. */
internal data class ReactQuad(val dst: ReactRect, val src: ReactRect)

internal data class ReactScene(val camera: ReactQuad?, val video: ReactQuad?) {
    companion object {
        val EMPTY = ReactScene(null, null)

        /** The scene from the channel; a quad that cannot be read is left out. */
        fun fromMap(map: Map<*, *>?): ReactScene {
            if (map == null) return EMPTY
            return ReactScene(quad(map["camera"]), quad(map["video"]))
        }

        private fun quad(raw: Any?): ReactQuad? {
            if (raw !is Map<*, *>) return null
            val dst = rect(raw["dst"]) ?: return null
            val src = rect(raw["src"]) ?: return null
            return ReactQuad(dst, src)
        }

        private fun rect(raw: Any?): ReactRect? {
            if (raw !is List<*> || raw.size != 4) return null
            val values = raw.map { (it as? Number)?.toFloat() ?: return null }
            if (values.any { !it.isFinite() }) return null
            return ReactRect(values[0], values[1], values[2], values[3])
        }
    }
}

/** The corners the GL draw takes, in triangle-strip order: top left, bottom left, top right, bottom right. */
internal object ReactGeometry {

    /** [dst]'s corners in clip space. */
    fun positions(dst: ReactRect): FloatArray {
        val left = 2f * dst.left - 1f
        val right = 2f * (dst.left + dst.width) - 1f
        val top = 1f - 2f * dst.top
        val bottom = 1f - 2f * (dst.top + dst.height)
        return floatArrayOf(left, top, left, bottom, right, top, right, bottom)
    }

    /**
     * The texture coordinates of [src]'s corners — the upright picture's
     * point, mirrored first where the camera did not mirror it, then turned
     * back into the buffer by [quarterTurns] clockwise turns where the camera
     * did not turn it (one turn: buffer x = v, y = 1 − u), then into GL's
     * y-up space when [yUp]. A camera's or a decoder's texture is multiplied
     * by its `SurfaceTexture` matrix after this; a bitmap's (top-left first)
     * takes y down as it is.
     */
    fun texCoords(src: ReactRect, quarterTurns: Int = 0, mirrored: Boolean = false, yUp: Boolean = true): FloatArray {
        val right = src.left + src.width
        val bottom = src.top + src.height
        val corners = arrayOf(
            src.left to src.top,
            src.left to bottom,
            right to src.top,
            right to bottom,
        )
        val turns = ((quarterTurns % 4) + 4) % 4
        val out = FloatArray(8)
        corners.forEachIndexed { i, (u0, v0) ->
            var u = if (mirrored) 1f - u0 else u0
            var v = v0
            repeat(turns) {
                val x = v
                val y = 1f - u
                u = x
                v = y
            }
            out[2 * i] = u
            out[2 * i + 1] = if (yUp) 1f - v else v
        }
        return out
    }
}
