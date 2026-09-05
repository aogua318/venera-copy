import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// An action that can be triggered by a hardware key.
enum InputAction {
  nextPage,
  prevPage,
  toggleAutoScroll,
  nextChapter,
  prevChapter;

  static InputAction? tryParse(String name) {
    for (var value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  String get displayName => switch (this) {
    nextPage => "Next Page",
    prevPage => "Previous Page",
    toggleAutoScroll => "Toggle Auto Scroll",
    nextChapter => "Next Chapter",
    prevChapter => "Previous Chapter",
  };
}

/// A hardware key identified by the key id of its [LogicalKeyboardKey].
///
/// Gamepad buttons, DPad keys, keyboard keys and media keys are all delivered
/// to Flutter as key events on Android, so they are handled uniformly here.
/// Note that volume keys are consumed by the system and never reach Flutter.
class HardwareKey {
  const HardwareKey(this.keyId);

  HardwareKey.fromLogicalKey(LogicalKeyboardKey key) : this(key.keyId);

  final int keyId;

  String get id => "fl:$keyId";

  String get displayName {
    var key = LogicalKeyboardKey.findKeyByKeyId(keyId);
    return key?.debugName ?? "Key $keyId";
  }
}

/// Parses a "fl:keyId" mapping entry. Returns null if invalid.
HardwareKey? parseHardwareKey(String id) {
  var parts = id.split(':');
  if (parts.length != 2 || parts[0] != 'fl') return null;
  var keyId = int.tryParse(parts[1]);
  if (keyId == null) return null;
  return HardwareKey(keyId);
}

/// Listens to gamepad / dpad / media key events forwarded from the Android
/// platform via the "venera/keys" channel. These keys are intercepted by
/// [dispatchKeyEvent] before they reach Flutter, so they cannot trigger focus
/// navigation while a listener is active.
///
/// The platform channel is shared and reference counted: when a reader is
/// replaced by another one (next/prev comic), the new listener attaches
/// before the old one detaches, so the channel is never cancelled in between.
class HardwareKeyListener {
  static const _channel = EventChannel('venera/keys');

  static StreamSubscription? _source;

  static final _events = StreamController<HardwareKey>.broadcast();

  static int _refCount = 0;

  HardwareKeyListener({this.onKey});

  final void Function(HardwareKey key)? onKey;

  StreamSubscription? _sub;

  void listen() {
    _refCount++;
    if (_source == null) {
      _source = _channel.receiveBroadcastStream().listen(_onEvent);
    }
    _sub ??= _events.stream.listen(_dispatch);
  }

  void _onEvent(event) {
    // Events are sent as "<source>:<androidKeyCode>".
    var parts = event.toString().split(':');
    if (parts.length != 2) return;
    var code = int.tryParse(parts[1]);
    if (code == null) return;
    var key = HardwareKey(_androidKeyId + code);
    debugPrint("VeneraKeys: channel event $event -> ${key.id}");
    _events.add(key);
  }

  void _dispatch(HardwareKey key) {
    onKey?.call(key);
  }

  void cancel() {
    _sub?.cancel();
    _sub = null;
    _refCount--;
    if (_refCount <= 0) {
      _refCount = 0;
      _source?.cancel();
      _source = null;
    }
  }
}

/// Flutter assigns Android key events key ids in the Android plane
/// (0x002 << 32) | keyCode.
const int _androidKeyId = 0x00200000000;

/// Default key bindings. Keys are "fl:keyId", values are [InputAction] names.
/// Android key codes: BUTTON_A=96, B=97, Y=100, L1=102, R1=103, L2=104, R2=105,
/// MEDIA_PLAY_PAUSE=85.
final Map<String, String> defaultInputKeyMap = {
  "fl:${_androidKeyId + 96}": "nextPage", // Gamepad A
  "fl:${_androidKeyId + 97}": "prevPage", // Gamepad B
  "fl:${_androidKeyId + 103}": "nextPage", // Gamepad R1
  "fl:${_androidKeyId + 102}": "prevPage", // Gamepad L1
  "fl:${_androidKeyId + 105}": "nextChapter", // Gamepad R2
  "fl:${_androidKeyId + 104}": "prevChapter", // Gamepad L2
  "fl:${_androidKeyId + 100}": "toggleAutoScroll", // Gamepad Y
  "fl:${_androidKeyId + 85}": "toggleAutoScroll", // Media Play/Pause
  "fl:${_androidKeyId + 20}": "nextPage", // DPad Down
  "fl:${_androidKeyId + 19}": "prevPage", // DPad Up
  "fl:${_androidKeyId + 22}": "nextPage", // DPad Right
  "fl:${_androidKeyId + 21}": "prevPage", // DPad Left
};
