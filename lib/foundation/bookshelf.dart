import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/utils/io.dart';

/// An entry of the bookshelf.
class BookshelfItem {
  BookshelfItem({required this.id, required this.type, required this.addedAt});

  final String id;

  final ComicType type;

  final int addedAt;

  Map<String, dynamic> toJson() => {'id': id, 'type': type.value, 'addedAt': addedAt};

  static BookshelfItem fromJson(Map<String, dynamic> json) {
    return BookshelfItem(
      id: json['id'],
      type: ComicType(json['type']),
      addedAt: json['addedAt'] ?? 0,
    );
  }

  /// Resolve the comic for display. Local comics are preferred, then history
  /// records. Returns null when the comic is no longer available.
  dynamic resolveComic() {
    var local = LocalManager().find(id, type);
    if (local != null) return local;
    return HistoryManager().find(id, type);
  }

  /// Title used for name sorting.
  String get title => resolveComic()?.title ?? id;

  /// The time of the last reading, used for sorting. Falls back to epoch.
  int get lastReadTime {
    var history = HistoryManager().find(id, type);
    if (history == null) return 0;
    return history.time.millisecondsSinceEpoch;
  }

  @override
  bool operator ==(Object other) =>
      other is BookshelfItem && other.id == id && other.type == type;

  @override
  int get hashCode => Object.hash(id, type);
}

/// Manages an ordered list of comics. The storage order is the manual order;
/// other sort modes are views over it and do not destroy the manual order.
class BookshelfManager with ChangeNotifier {
  BookshelfManager._() {
    _load();
  }

  static BookshelfManager? _instance;

  factory BookshelfManager() {
    return _instance ??= BookshelfManager._();
  }

  final List<BookshelfItem> _items = [];

  static File get _file => File(FilePath.join(App.dataPath, 'bookshelf.json'));

  void _load() {
    try {
      if (!_file.existsSync()) return;
      var json = jsonDecode(_file.readAsStringSync());
      if (json is List) {
        _items.addAll(json.map((e) => BookshelfItem.fromJson(e)));
      }
    } catch (e) {
      // Ignore broken bookshelf data, start with an empty shelf.
    }
  }

  void _save() {
    _file.writeAsStringSync(jsonEncode(
      _items.map((e) => e.toJson()).toList(),
    ));
    notifyListeners();
  }

  List<BookshelfItem> get items => List.unmodifiable(_items);

  bool contains(String id, ComicType type) =>
      _items.any((e) => e.id == id && e.type == type);

  void add(String id, ComicType type) {
    if (contains(id, type)) return;
    _items.add(BookshelfItem(
      id: id,
      type: type,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    _save();
  }

  void addAll(Iterable<(String, ComicType)> comics) {
    var changed = false;
    for (var (id, type) in comics) {
      if (!contains(id, type)) {
        _items.add(BookshelfItem(
          id: id,
          type: type,
          addedAt: DateTime.now().millisecondsSinceEpoch,
        ));
        changed = true;
      }
    }
    if (changed) {
      _save();
    }
  }

  void remove(String id, ComicType type) {
    _items.removeWhere((e) => e.id == id && e.type == type);
    _save();
  }

  /// The items in the order defined by the current sort settings. This is
  /// the single source of truth used by both the bookshelf page and the
  /// reader's prev/next comic feature.
  List<BookshelfItem> sortedItems() {
    var mode = appdata.settings['bookshelfSortMode'] ?? 'addedTime';
    var desc = appdata.settings['bookshelfSortDesc'] == true;
    var items = List.of(_items);
    switch (mode) {
      case 'name':
        items.sort((a, b) => a.title.compareTo(b.title));
      case 'lastRead':
        items.sort((a, b) => b.lastReadTime.compareTo(a.lastReadTime));
      case 'addedTime':
      default:
        items.sort((a, b) => a.addedAt.compareTo(b.addedAt));
    }
    if (desc) {
      items = items.reversed.toList();
    }
    return items;
  }

  /// Remove entries whose comic no longer exists (e.g. deleted local comics).
  void prune() {
    var before = _items.length;
    _items.removeWhere((e) => e.resolveComic() == null);
    if (_items.length != before) {
      _save();
    }
  }
}
