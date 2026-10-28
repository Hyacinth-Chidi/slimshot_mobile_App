package com.techfamz.slimshotai

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * This install's build, for what the app keeps from its own engine's drawings
 * (the Transitions and Effects tiles): the version code, and when this APK was
 * installed or last updated — `"2-1793141004000"`. The second moves with every
 * install, a store update and a debug rebuild alike, so a drawing kept by one
 * build is never shown by another, even where a changed shader left the
 * version code as it was.
 *
 * Answers null when the package cannot be read, and the tiles are then drawn
 * each launch as they always were.
 */
class AppBuildChannel(private val context: Context) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "buildStamp" -> result.success(runCatching { buildStamp() }.getOrNull())
            else -> result.notImplemented()
        }
    }

    private fun buildStamp(): String {
        val info = packageInfo()
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        return "$versionCode-${info.lastUpdateTime}"
    }

    private fun packageInfo(): PackageInfo {
        val packageManager = context.packageManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                context.packageName,
                PackageManager.PackageInfoFlags.of(0),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(context.packageName, 0)
        }
    }

    companion object {
        const val channelName = "slimshot_ai/app_build"
    }
}
