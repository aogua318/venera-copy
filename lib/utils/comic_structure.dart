import 'package:venera/utils/io.dart';

/// Image extensions recognized in comic directories.
const comicImageExtensions = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'jpe'];

bool _isImageFile(File file) => comicImageExtensions.contains(file.extension);

bool _isHidden(FileSystemEntity entity) => entity.name.startsWith('.');

/// Natural comparison: digit runs are compared numerically, so "2" sorts
/// before "10".
int naturalCompare(String a, String b) {
  int ia = 0, ib = 0;
  while (true) {
    if (ia >= a.length && ib >= b.length) return 0;
    if (ia >= a.length) return -1;
    if (ib >= b.length) return 1;
    var ca = a[ia], cb = b[ib];
    var da = _isDigit(ca), db = _isDigit(cb);
    if (da && db) {
      var sa = ia, sb = ib;
      while (ia < a.length && _isDigit(a[ia])) {
        ia++;
      }
      while (ib < b.length && _isDigit(b[ib])) {
        ib++;
      }
      var c = (int.tryParse(a.substring(sa, ia)) ?? 0)
          .compareTo(int.tryParse(b.substring(sb, ib)) ?? 0);
      if (c != 0) return c;
    } else {
      var c = ca.compareTo(cb);
      if (c != 0) return c;
      ia++;
      ib++;
    }
  }
}

bool _isDigit(String ch) {
  var code = ch.codeUnitAt(0);
  return code >= 0x30 && code <= 0x39;
}

/// Natural-sorts comic page files by their full path.
void sortComicFiles(List<File> files) {
  files.sort((a, b) => naturalCompare(a.path, b.path));
}

/// Returns [path] relative to [fromDir] when it is inside it, otherwise
/// returns [path] unchanged.
String pathRelativeTo(String path, String fromDir) {
  var normalizedFrom =
      fromDir.replaceAll('\\', '/').replaceAll(RegExp('/+\$'), '');
  var normalizedPath = path.replaceAll('\\', '/');
  if (normalizedPath.startsWith('$normalizedFrom/')) {
    return normalizedPath.substring(normalizedFrom.length + 1);
  }
  if (normalizedPath == normalizedFrom) return '';
  return path;
}

/// Recursively collects all comic page files under [dir] (any depth),
/// excluding hidden files and files named `cover.*`. The result is sorted
/// naturally by path.
List<File> collectComicImages(Directory dir) {
  var result = <File>[];
  void walk(Directory d) {
    for (var entity in d.listSync()) {
      if (entity is File) {
        if (_isHidden(entity) || entity.name.startsWith('cover.')) continue;
        if (_isImageFile(entity)) result.add(entity);
      } else if (entity is Directory) {
        if (!_isHidden(entity)) walk(entity);
      }
    }
  }

  walk(dir);
  sortComicFiles(result);
  return result;
}

/// Analyzes the structure of a comic directory.
///
/// Single-branch nesting (each level contains exactly one subdirectory and no
/// images) is followed down to the content root. A content root holding two
/// or more subdirectories is a branching, multi-chapter structure; otherwise
/// it is a single-chapter comic.
///
/// Returns the content root and whether it is a multi-chapter comic.
(Directory, bool) analyzeComicStructure(Directory directory) {
  var current = directory;
  while (true) {
    var subdirs = <Directory>[];
    var hasImages = false;
    for (var entity in current.listSync()) {
      if (entity is Directory) {
        if (!_isHidden(entity)) subdirs.add(entity);
      } else if (entity is File) {
        if (!_isHidden(entity) && _isImageFile(entity)) hasImages = true;
      }
    }
    if (hasImages || subdirs.length != 1) {
      return (current, subdirs.length >= 2);
    }
    current = subdirs.first;
  }
}
