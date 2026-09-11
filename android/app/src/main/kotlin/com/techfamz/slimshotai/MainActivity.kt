package com.techfamz.slimshotai

import androidx.media3.common.util.UnstableApi
import com.techfamz.slimshotai.nativepreview.NativeTimelinePreviewManager
import com.techfamz.slimshotai.thumbnails.VideoThumbnailProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

@OptIn(UnstableApi::class)
class MainActivity : FlutterActivity() {

    private var thumbnailProvider: VideoThumbnailProvider? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val thumbnails = VideoThumbnailProvider()
        thumbnailProvider = thumbnails
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            VideoThumbnailProvider.channelName,
        ).setMethodCallHandler(thumbnails)

        // The preview renders into a Flutter texture rather than a PlatformView,
        // so the engine's renderer (the TextureRegistry) is what it needs.
        val manager = NativeTimelinePreviewManager(
            context = applicationContext,
            textureRegistry = flutterEngine.renderer,
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NativeTimelinePreviewManager.methodChannelName,
        ).setMethodCallHandler(manager)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NativeTimelinePreviewManager.eventChannelName,
        ).setStreamHandler(manager)
    }

    override fun onDestroy() {
        thumbnailProvider?.dispose()
        thumbnailProvider = null
        super.onDestroy()
    }
}
