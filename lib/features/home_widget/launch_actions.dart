import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'home_widget_sync.dart';

/// What a tap on the home screen widget or the icon's menu asks for. Home
/// runs each with the handler its own button runs, so there is no second
/// implementation of either job.
sealed class LaunchAction {
  const LaunchAction();

  /// Reads `{action, draftId}` from the channel; anything else is nothing.
  static LaunchAction? fromWire(Object? message) {
    if (message is! Map) return null;
    return switch (message['action']) {
      'continue' => switch (message['draftId']) {
          final String id when id.isNotEmpty => ContinueEdit(id),
          _ => null,
        },
      'new_video' => const NewVideo(),
      'compress_video' => const CompressVideo(),
      _ => null,
    };
  }
}

/// The widget's Continue: open this draft in the editor.
final class ContinueEdit extends LaunchAction {
  const ContinueEdit(this.draftId);

  final String draftId;

  @override
  bool operator ==(Object other) =>
      other is ContinueEdit && other.draftId == draftId;

  @override
  int get hashCode => Object.hash(ContinueEdit, draftId);

  @override
  String toString() => 'ContinueEdit($draftId)';
}

/// The menu's New video, and the empty widget's Start editing.
final class NewVideo extends LaunchAction {
  const NewVideo();

  @override
  bool operator ==(Object other) => other is NewVideo;

  @override
  int get hashCode => (NewVideo).hashCode;

  @override
  String toString() => 'NewVideo';
}

/// The menu's Compress video.
final class CompressVideo extends LaunchAction {
  const CompressVideo();

  @override
  bool operator ==(Object other) => other is CompressVideo;

  @override
  int get hashCode => (CompressVideo).hashCode;

  @override
  String toString() => 'CompressVideo';
}

enum LaunchRoute {
  /// The app came forward and that is all: something on screen would be
  /// lost, or the tap asked for what is already open.
  bringForward,

  /// Onboarding first; the action waits for Home.
  waitForHome,

  /// Home, which then runs the action.
  goHome,
}

/// Where a tap goes. Work in progress is never thrown away by a tap
/// ([busy]: an export, a compression, a result nobody kept), and Continue on
/// the edit already open only brings the app forward.
LaunchRoute routeFor(
  LaunchAction action, {
  required bool busy,
  required String? openDraftId,
  required bool onboardingSeen,
}) {
  if (busy) return LaunchRoute.bringForward;
  if (action case ContinueEdit(:final draftId) when draftId == openDraftId) {
    return LaunchRoute.bringForward;
  }
  if (!onboardingSeen) return LaunchRoute.waitForHome;
  return LaunchRoute.goHome;
}

/// The action waiting for Home. A tap posts; Home takes it — once — when it
/// is up, so an action that arrives during the splash or onboarding runs
/// when Home appears, and never twice.
class LaunchActions extends ChangeNotifier {
  LaunchActions();

  static final LaunchActions instance = LaunchActions();

  LaunchAction? _pending;

  LaunchAction? get pending => _pending;

  /// Replaces whatever is waiting: the last tap wins.
  void post(LaunchAction action) {
    _pending = action;
    notifyListeners();
  }

  LaunchAction? take() {
    final action = _pending;
    _pending = null;
    return action;
  }
}

/// The app's end of the launch actions: the one it was started with, asked
/// for once, and every later tap as it arrives.
class LaunchChannel {
  LaunchChannel({
    MethodChannel? channel,
    required void Function(LaunchAction action) onAction,
  })  : _channel = channel ?? const MethodChannel(kHomeWidgetChannel),
        _onAction = onAction;

  final MethodChannel _channel;
  final void Function(LaunchAction action) _onAction;

  Future<void> start() async {
    // Listening first: the platform holds a tap that arrives before the
    // app asks, and sends the ones after.
    _channel.setMethodCallHandler(_onCall);
    try {
      final action = LaunchAction.fromWire(
        await _channel.invokeMethod<Object?>('takeLaunchAction'),
      );
      if (action != null) _onAction(action);
    } catch (_) {
      // No widget on this platform.
    }
  }

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method == 'launchAction') {
      final action = LaunchAction.fromWire(call.arguments);
      if (action != null) _onAction(action);
    }
    return null;
  }

  void dispose() => _channel.setMethodCallHandler(null);
}

/// Sends an action where [routeFor] says. Going Home with an edit open
/// saves it first, as leaving the editor always does, and Home acts only
/// once the editor has gone: two editors at once would share one editor
/// state and one native preview.
class LaunchRouter {
  LaunchRouter({
    required bool Function() busy,
    required String? Function() openDraftId,
    required Future<bool> Function() onboardingSeen,
    required Future<void> Function() saveOpenEdit,
    required void Function() goHome,
    required Future<void> Function() untilEditorGone,
    LaunchActions? actions,
  })  : _busy = busy,
        _openDraftId = openDraftId,
        _onboardingSeen = onboardingSeen,
        _saveOpenEdit = saveOpenEdit,
        _goHome = goHome,
        _untilEditorGone = untilEditorGone,
        _actions = actions ?? LaunchActions.instance;

  final bool Function() _busy;
  final String? Function() _openDraftId;
  final Future<bool> Function() _onboardingSeen;
  final Future<void> Function() _saveOpenEdit;
  final void Function() _goHome;
  final Future<void> Function() _untilEditorGone;
  final LaunchActions _actions;

  Future<void> handle(LaunchAction action) async {
    final seen = await _onboardingSeen();
    final open = _openDraftId();
    switch (routeFor(
      action,
      busy: _busy(),
      openDraftId: open,
      onboardingSeen: seen,
    )) {
      case LaunchRoute.bringForward:
        return;
      case LaunchRoute.waitForHome:
        _actions.post(action);
      case LaunchRoute.goHome:
        if (open != null) await _saveOpenEdit();
        _goHome();
        // Also when there was nothing to save: an editor still loading its
        // media has no draft id yet.
        await _untilEditorGone();
        _actions.post(action);
    }
  }
}
