package com.techfamz.slimshotai

import android.content.Intent
import android.os.Bundle
import androidx.media3.common.util.UnstableApi
import com.techfamz.slimshotai.audio.AudioToolsChannel
import com.techfamz.slimshotai.audio.VoiceRecorderChannel
import com.techfamz.slimshotai.homewidget.HomeWidgetChannel
import com.techfamz.slimshotai.homewidget.LaunchIntents
import com.techfamz.slimshotai.nativepreview.NativeTimelinePreviewManager
import com.techfamz.slimshotai.privacy.PhotoMetadataReader
import com.techfamz.slimshotai.thumbnails.VideoThumbnailProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

@OptIn(UnstableApi::class)
class MainActivity : FlutterActivity() {

    private var thumbnailProvider: VideoThumbnailProvider? = null
    private var photoMetadataReader: PhotoMetadataReader? = null
    private var audioTools: AudioToolsChannel? = null
    private var voiceRecorder: VoiceRecorderChannel? = null
    private var homeWidget: HomeWidgetChannel? = null

    /** The widget or menu tap the app was started with, if it was. */
    private var launchedWith: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Read once, on a fresh start only, and before the engine is set up
        // (configureFlutterEngine runs inside super.onCreate). Recreated from
        // saved state, or reopened from Recents, the activity carries the
        // intent of a tap that was already acted on.
        launchedWith = if (savedInstanceState == null) launchActionOf(intent) else null
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        launchActionOf(intent)?.let { homeWidget?.deliver(it) }
    }

    private fun launchActionOf(intent: Intent?): Map<String, Any?>? =
        LaunchIntents.toWire(
            intent?.action,
            intent?.getStringExtra(LaunchIntents.EXTRA_DRAFT_ID),
            launchedFromHistory = intent != null &&
                (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0,
        )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val widgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            HomeWidgetChannel.channelName,
        )
        homeWidget = HomeWidgetChannel(applicationContext, widgetChannel, launchedWith).also {
            widgetChannel.setMethodCallHandler(it)
        }

        val thumbnails = VideoThumbnailProvider()
        thumbnailProvider = thumbnails
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            VideoThumbnailProvider.channelName,
        ).setMethodCallHandler(thumbnails)

        val metadata = PhotoMetadataReader()
        photoMetadataReader = metadata
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PhotoMetadataReader.channelName,
        ).setMethodCallHandler(metadata)

        val tools = AudioToolsChannel()
        audioTools = tools
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AudioToolsChannel.channelName,
        ).setMethodCallHandler(tools)

        val voice = VoiceRecorderChannel()
        voiceRecorder = voice
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            VoiceRecorderChannel.channelName,
        ).setMethodCallHandler(voice)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AppBuildChannel.channelName,
        ).setMethodCallHandler(AppBuildChannel(applicationContext))

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
        photoMetadataReader?.release()
        photoMetadataReader = null
        audioTools?.release()
        audioTools = null
        voiceRecorder?.release()
        voiceRecorder = null
        homeWidget?.release()
        homeWidget = null
        super.onDestroy()
    }
}
