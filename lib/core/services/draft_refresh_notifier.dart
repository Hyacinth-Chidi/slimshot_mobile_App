import 'package:flutter/foundation.dart';

class DraftRefreshNotifier extends ChangeNotifier {
  DraftRefreshNotifier._();
  static final DraftRefreshNotifier instance = DraftRefreshNotifier._();

  void refresh() {
    notifyListeners();
  }
}
