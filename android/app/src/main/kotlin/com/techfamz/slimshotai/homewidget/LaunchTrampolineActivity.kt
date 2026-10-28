package com.techfamz.slimshotai.homewidget

import android.app.Activity
import android.os.Bundle

/**
 * Where the icon's menu lands first. Android launches a static shortcut with
 * `NEW_TASK | CLEAR_TASK`; aimed at `MainActivity`, that would destroy the
 * running app — the editor with its unsaved changes, an export under way —
 * before the tap ever reached it. This activity has a task of its own
 * (`taskAffinity=""`), so only that task is cleared; it hands the tap on to
 * the app the way the widget does, and is gone without being seen.
 */
class LaunchTrampolineActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val action = intent?.action
        val draftId = intent?.getStringExtra(LaunchIntents.EXTRA_DRAFT_ID)
        if (action != null &&
            LaunchIntents.toWire(action, draftId, launchedFromHistory = false) != null
        ) {
            startActivity(LaunchIntents.forMainActivity(this, action, draftId))
        }
        finish()
    }
}
