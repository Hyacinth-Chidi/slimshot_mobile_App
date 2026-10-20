import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/audio_tools/record_controller.dart';
import 'package:slimshotai/features/audio_tools/voice_recorder_service.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/record_panel.dart';

class _Recorder implements VoiceRecorder {
  @override
  Future<void> open(String outputPath) async {}

  @override
  Future<void> setCapturing(bool on, {double? alignTo}) async {}

  @override
  Future<RecordedTake?> close({required bool keep}) async => null;
}

/// The record panel: one round button, the countdown on it, a pulsing ring
/// while recording, and the speaker toggle.
void main() {
  late RecordController controller;
  Completer<void>? hold;
  MicPermission permission = MicPermission.granted;
  var settingsOpened = 0;

  Future<void> pumpPanel(WidgetTester tester) async {
    controller = RecordController(
      recorder: _Recorder(),
      requestMic: () async => permission,
      newTakePath: () async => '/d/voice.m4a',
      play: () {},
      pause: () {},
      setMonitorMuted: (_) {},
      playhead: () => 1,
      projectEnd: () => 10,
      wait: (_) => hold?.future ?? Future<void>.value(),
    );
    await controller.enter();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RecordPanel(
          controller: controller,
          onOpenSettings: () => settingsOpened++,
        ),
      ),
    ));
  }

  setUp(() {
    hold = null;
    permission = MicPermission.granted;
    settingsOpened = 0;
  });

  testWidgets('idle shows record', (tester) async {
    await pumpPanel(tester);
    expect(find.byKey(const ValueKey('record-glyph-record')), findsOneWidget);
    expect(find.byKey(const ValueKey('record-pulse')), findsNothing);
  });

  testWidgets('recording shows pause with a pulsing ring', (tester) async {
    await pumpPanel(tester);
    await tester.tap(find.byKey(const ValueKey('record-button')));
    await tester.pump();
    await tester.pump();
    expect(controller.phase, RecordPhase.recording);
    expect(find.byKey(const ValueKey('record-glyph-pause')), findsOneWidget);
    expect(find.byKey(const ValueKey('record-pulse')), findsOneWidget);
    await controller.discard();
    await tester.pump();
  });

  testWidgets('the countdown shows its number', (tester) async {
    hold = Completer<void>();
    await pumpPanel(tester);
    await tester.tap(find.byKey(const ValueKey('record-button')));
    await tester.pump();
    await tester.pump();
    expect(controller.phase, RecordPhase.countdown);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('the speaker toggle flips the monitor', (tester) async {
    await pumpPanel(tester);
    expect(controller.monitorMuted, isTrue);
    await tester.tap(find.byKey(const ValueKey('record-monitor')));
    await tester.pump();
    expect(controller.monitorMuted, isFalse);
  });

  testWidgets('a microphone refused for good offers Settings', (tester) async {
    permission = MicPermission.permanentlyDenied;
    await pumpPanel(tester);
    await tester.tap(find.byKey(const ValueKey('record-button')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Open Settings'));
    expect(settingsOpened, 1);
  });
}
