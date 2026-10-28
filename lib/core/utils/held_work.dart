/// Work a screen would lose if it were closed from outside its own buttons:
/// an export under way, a result nobody has saved or shared, a caption run,
/// a voice take. A tap on the home screen widget or the icon's menu only
/// brings the app forward while any of it is held (`LaunchRouter`), so a tap
/// never throws work away.
class HeldWork {
  HeldWork();

  static final HeldWork instance = HeldWork();

  final Set<Object> _holders = {};

  bool get isHeld => _holders.isNotEmpty;

  /// Holding twice is holding once: one [release] lets go.
  void hold(Object holder) => _holders.add(holder);

  void release(Object holder) => _holders.remove(holder);
}
