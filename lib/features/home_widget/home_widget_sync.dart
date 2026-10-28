import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/models/draft_project.dart';
import '../../core/services/draft_refresh_notifier.dart';
import '../../core/services/draft_service.dart';

/// The channel the home screen widget and the app's launch actions share
/// (`HomeWidgetChannel.kt`).
const String kHomeWidgetChannel = 'slimshot_ai/home_widget';

/// What the "Continue editing" widget shows: the last edit.
@immutable
class HomeWidgetEdit {
  const HomeWidgetEdit({
    required this.draftId,
    required this.coverPath,
    required this.editedAt,
    required this.clips,
    required this.lengthSeconds,
  });

  final String draftId;

  /// The draft's cover — the one chosen, else the first frame the editor
  /// saved — or null.
  final String? coverPath;

  final DateTime editedAt;
  final int clips;

  /// The edit's own length; null for a draft saved before it was kept.
  final double? lengthSeconds;

  /// What crosses the channel. The widget works the date out itself when it
  /// draws, so it says "today" for as long as that is true.
  Map<String, Object?> toWire() => {
        'draftId': draftId,
        'coverPath': coverPath,
        'editedAtMillis': editedAt.millisecondsSinceEpoch,
        'clips': clips,
        'lengthSeconds': lengthSeconds,
      };
}

/// The draft saved last, whatever order [drafts] are in; null for none.
HomeWidgetEdit? lastEditOf(List<DraftProject> drafts) {
  if (drafts.isEmpty) return null;
  final latest =
      drafts.reduce((a, b) => b.updatedAt.isAfter(a.updatedAt) ? b : a);
  return HomeWidgetEdit(
    draftId: latest.id,
    coverPath: latest.thumbnailPath,
    editedAt: latest.updatedAt,
    clips: latest.segments.length,
    lengthSeconds: latest.editedSeconds,
  );
}

/// Keeps the widget on the last edit: sends it now and again whenever a
/// draft is saved or deleted ([DraftRefreshNotifier]).
class HomeWidgetSync {
  HomeWidgetSync({
    MethodChannel? channel,
    Future<List<DraftProject>> Function()? drafts,
  })  : _channel = channel ?? const MethodChannel(kHomeWidgetChannel),
        _drafts = drafts ?? DraftService.getDrafts;

  final MethodChannel _channel;
  final Future<List<DraftProject>> Function() _drafts;
  bool _started = false;

  /// The latest [sync] begun; an earlier one whose read lands after it is
  /// dropped, or a slow read could put back a draft just deleted.
  int _ticket = 0;

  void start() {
    if (_started) return;
    _started = true;
    DraftRefreshNotifier.instance.addListener(_onDraftsChanged);
    unawaited(sync());
  }

  void _onDraftsChanged() => unawaited(sync());

  Future<void> sync() async {
    final ticket = ++_ticket;
    try {
      final edit = lastEditOf(await _drafts());
      if (ticket != _ticket) return;
      await _channel.invokeMethod<void>('setLastEdit', edit?.toWire());
    } catch (_) {
      // No widget on this platform, or drafts that could not be read: the
      // widget keeps what it last showed, and the next change tries again.
    }
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    DraftRefreshNotifier.instance.removeListener(_onDraftsChanged);
  }
}
