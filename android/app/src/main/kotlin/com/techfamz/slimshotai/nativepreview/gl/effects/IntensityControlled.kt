package com.techfamz.slimshotai.nativepreview.gl.effects

/**
 * A pass whose strength can be changed without rebuilding it.
 *
 * **This is the difference between a slider that drags and one that stutters.**
 * Baking the intensity into a pass at construction means every change to it —
 * every frame of a slider drag — rebuilds the pass list and re-links its GL
 * programs, on a thread hop that blocks the caller. That puts a
 * `glLinkProgram` squarely in the render path, which is the cost
 * `TransitionShaders.warmUpShaders` exists to keep out of it, and it is why
 * `BlurPass` was already written with a settable `radiusFraction` rather than a
 * constructor argument. This is that pattern, named, so a heterogeneous pass
 * list can be retuned without the caller knowing what is in it.
 *
 * It is also what makes the next two stages possible at all: envelopes and
 * keyframes vary intensity **per frame** by design, and neither can exist if a
 * change costs a link.
 *
 * ### Threading
 *
 * [applyIntensity] is called from whichever thread drives the timeline — the main
 * thread for playback's ticker, the export loop's thread for a render — and the
 * value is read on the **GL thread** when the pass draws. Implementations must
 * therefore hold it in a `@Volatile` field. A `Float` write needs no GL context
 * and no lock: the worst a race can do is show one frame of the previous
 * strength, which is invisible, where the alternative — hopping to the GL
 * thread to set a number — reintroduces exactly the block this exists to avoid.
 */
internal interface IntensityControlled {

    /**
     * Sets this pass's strength from the catalog's normalised 0..1 value.
     *
     * A pass is free to map it onto whatever it actually varies — glow's blur
     * halves turn it into a radius — so callers must not assume the value
     * reaches a uniform unchanged.
     *
     * Named `applyIntensity` rather than `setIntensity` because the latter is
     * the JVM signature Kotlin already generates for a `var intensity`, and an
     * implementation holding both would not compile ("platform declaration
     * clash"). A pass that stores its strength in an ordinary property is the
     * expected shape here, so the interface gets out of its way.
     */
    fun applyIntensity(intensity: Float)
}
