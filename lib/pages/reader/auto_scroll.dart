part of 'reader.dart';

/// Drives a [ScrollPosition] at a constant speed for auto scrolling
/// in continuous reading mode.
///
/// The speed is expressed as "milliseconds per screen height": a value of
/// 5000 means one viewport is scrolled in 5 seconds. Each frame the position
/// is advanced by `speed * deltaTime`, so frame drops do not change the speed.
class AutoScrollEngine {
  AutoScrollEngine({
    required this.getPosition,
    required this.msPerScreen,
    required this.onReachEnd,
  });

  final ScrollPosition Function() getPosition;

  /// Milliseconds needed to scroll one screen (viewport dimension).
  final int Function() msPerScreen;

  /// Called when the end of the scroll range is reached. The engine is
  /// stopped before this callback is invoked.
  final VoidCallback onReachEnd;

  Ticker? _ticker;
  Duration _lastElapsed = Duration.zero;
  bool _forward = true;

  bool get isRunning => _ticker?.isActive ?? false;

  /// Start scrolling. Returns false if the scroll position is not ready yet.
  bool start({bool forward = true}) {
    _forward = forward;
    if (isRunning) return true;
    if (!getPosition().hasContentDimensions) return false;
    _lastElapsed = Duration.zero;
    _ticker = Ticker(_onTick)..start();
    return true;
  }

  /// Stop scrolling while keeping the current position.
  void pause() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
  }

  void _onTick(Duration elapsed) {
    if (_lastElapsed == Duration.zero) {
      _lastElapsed = elapsed;
      return;
    }
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1000;
    _lastElapsed = elapsed;
    if (dt <= 0) return;
    final position = getPosition();
    if (!position.hasContentDimensions) return;
    final min = position.minScrollExtent;
    final max = position.maxScrollExtent;
    if (max - min < 10) {
      pause();
      onReachEnd();
      return;
    }
    final speed = position.viewportDimension / msPerScreen();
    final target = (position.pixels + (_forward ? speed : -speed) * dt).clamp(
      min,
      max,
    );
    position.jumpTo(target);
    if (_forward ? position.pixels >= max : position.pixels <= min) {
      pause();
      onReachEnd();
    }
  }
}
