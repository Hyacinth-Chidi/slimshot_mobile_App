import 'package:flutter/foundation.dart';

/// A simple singleton notifier that signals when drafts have changed.
/// Both HomeScreen and WorkspaceScreen listen to this so they stay
/// in sync even when kept alive by StatefulShellRoute.indexedStack.
class DraftRefreshNotifier extends ChangeNotifier {
  DraftRefreshNotifier._();
  static final DraftRefreshNotifier instance = DraftRefreshNotifier._();

  void refresh() {
    notifyListeners();
  }
}
