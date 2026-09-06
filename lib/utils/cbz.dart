import 'dart:convert';
import 'package:flutter_7zip/flutter_7zip.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/utils/comic_structure.dart';
import 'package:venera/utils/ext.dart';
import 'package:venera/utils/file_type.dart';
import 'package:venera/utils/io.dart';
import 'package:zip_flutter/zip_flutter.dart';

class ComicMetaData {
  final String title;

  final String author;

  final List<String> tags;

  final List<ComicChapter>? chapters;

  Map<String, dynamic> toJson() => {
        'title': title,
        'author': author,
        'tags': tags,
        'chapters': chapters?.map((e) => e.toJson()).toList()
      };

  ComicMetaData.fromJson(Map<String, dynamic> json)
      : title = json['title'],
        author = json['author'],
        tags = List<String>.from(json['tags']),
        chapters = json['chapters'] == null
            ? null
            : List<ComicChapter>.from(
                json['chapters'].map((e) => ComicChapter.fromJson(e)));

  ComicMetaData({
    required this.title,
    required this.author,
    required this.tags,
    this.chapters,
  });
}

class ComicChapter {
  final String title;

  final int start;

  final int end;

  Map<String, dynamic> toJson() => {'title': title, 'start': start, 'end': end};

  ComicChapter.fromJson(Map<String, dynamic> json)
      : title = json['title'],
        start = json['start'],
        end = json['end'];

  ComicChapter({required this.title, required this.start, required this.end});
}

/// Comic Book Archive. Currently supports CBZ, ZIP and 7Z formats.
abstract class CBZ {
  static Future<FileType> checkType(File file) async {
    var header = <int>[];
    await for (var bytes in file.openRead()) {
      header.addAll(bytes);
      if (header.length >= 32) break;
    }
    return detectFileType(header);
  }

  static Future<void> extractArchive(File file, Directory out) async {
    var fileType = await checkType(file);
    if (fileType.mime == 'application/zip') {
      await ZipFile.openAndExtractAsync(file.path, out.path, 4);
    } else if (fileType.mime == "application/x-7z-compressed") {
      await SZArchive.extractIsolates(file.path, out.path, 4);
    } else {
      throw Exception('Unsupported archive type');
    }
  }

  /// Import a comic book archive. Returns null when the comic is skipped
  /// (a comic or directory with the same name already exists).
  static Future<LocalComic?> import(File file) async {
    var cache = Directory(FilePath.join(App.cachePath, 'cbz_import'));
    if (cache.existsSync()) cache.deleteSync(recursive: true);
    cache.createSync();
    await extractArchive(file, cache);
    var f = cache.listSync();
    if (f.length == 1 && f.first is Directory) {
      cache = f.first as Directory;
    }
    var metaDataFile = File(FilePath.join(cache.path, 'metadata.json'));
    ComicMetaData? metaData;
    if (metaDataFile.existsSync()) {
      try {
        metaData =
            ComicMetaData.fromJson(jsonDecode(metaDataFile.readAsStringSync()));
      } catch (_) {}
    }
    metaData ??= ComicMetaData(
      title: file.name.substring(0, file.name.lastIndexOf('.')),
      author: "",
      tags: [],
    );
    var old = LocalManager().findByName(metaData.title);
    if (old != null) {
      // Skip existing comics instead of throwing.
      cache.deleteSync(recursive: true);
      return null;
    }
    var destName = sanitizeFileName(metaData.title);
    var dest = Directory(FilePath.join(LocalManager().path, destName));
    if (dest.existsSync()) {
      // A directory with the same name already exists, skip.
      cache.deleteSync(recursive: true);
      return null;
    }
    var files = cache.listSync().whereType<File>().toList();
    files.removeWhere((e) {
      var ext = e.path.split('.').last;
      return !['jpg', 'jpeg', 'png', 'webp', 'gif', 'jpe'].contains(ext);
    });
    var (contentRoot, isMultiChapter) = analyzeComicStructure(cache);

    // Build the chapter list from the archive structure (or metadata).
    var chapterList = <(String, List<File>)>[];
    if (metaData.chapters != null) {
      // Legacy metadata-defined chapters over the flattened page list.
      var pages = collectComicImages(contentRoot);
      for (var chapter in metaData.chapters!) {
        var start = (chapter.start - 1).clamp(0, pages.length);
        var end = chapter.end.clamp(0, pages.length);
        if (end > start) {
          chapterList.add((chapter.title, pages.sublist(start, end)));
        }
      }
    } else if (isMultiChapter) {
      // Branching structure: each subdirectory becomes a chapter. Page files
      // directly under the content root become an extra leading chapter.
      var rootImages = files
          .where((e) => !e.name.startsWith('cover.'))
          .toList()
        ..sort((a, b) => naturalCompare(a.path, b.path));
      if (rootImages.isNotEmpty) {
        chapterList.add((metaData.title, rootImages));
      }
      var subdirs = contentRoot
          .listSync()
          .whereType<Directory>()
          .where((e) => !e.name.startsWith('.'))
          .toList()
        ..sort((a, b) => naturalCompare(a.path, b.path));
      for (var subdir in subdirs) {
        var pages = collectComicImages(subdir);
        if (pages.isNotEmpty) {
          chapterList.add((subdir.name, pages));
        }
      }
    } else {
      // Single-chapter comic (nested single branches are flattened).
      chapterList.add((metaData.title, collectComicImages(contentRoot)));
    }
    if (chapterList.every((c) => c.$2.isEmpty)) {
      cache.deleteSync(recursive: true);
      throw Exception('No images found in the archive');
    }

    // Cover: a file named 'cover.*' anywhere, otherwise the first page of
    // the first chapter. The cover is excluded from the pages.
    File? coverFile;
    for (var (_, pages) in chapterList) {
      coverFile = pages.firstWhereOrNull((e) => e.name.startsWith('cover.'));
      if (coverFile != null) {
        pages.remove(coverFile);
        break;
      }
    }
    coverFile ??= () {
      for (var (_, pages) in chapterList) {
        if (pages.isNotEmpty) {
          return pages.removeAt(0);
        }
      }
      return null;
    }();
    if (coverFile == null) {
      cache.deleteSync(recursive: true);
      throw Exception('No images found in the archive');
    }

    dest.createSync();
    coverFile.copyMem(FilePath.join(dest.path, 'cover.${coverFile.extension}'));
    var useChapters = metaData.chapters != null || isMultiChapter;
    var chapterMap = <String, String>{};
    int chapterIndex = 0;
    for (var (title, pages) in chapterList) {
      if (pages.isEmpty) continue;
      if (!useChapters) {
        // Single-chapter comic: pages go directly into the comic directory.
        for (var i = 0; i < pages.length; i++) {
          var src = pages[i];
          var dst =
              File(FilePath.join(dest.path, '${i + 1}.${src.extension}'));
          try {
            src.renameSync(dst.path);
          } catch (_) {
            await src.copyMem(dst.path);
          }
        }
        break;
      }
      var chapterDir = Directory(FilePath.join(dest.path, '$chapterIndex'));
      chapterDir.createSync();
      for (var i = 0; i < pages.length; i++) {
        var src = pages[i];
        var dst =
            File(FilePath.join(chapterDir.path, '${i + 1}.${src.extension}'));
        try {
          src.renameSync(dst.path);
        } catch (_) {
          await src.copyMem(dst.path);
        }
      }
      chapterMap[chapterIndex.toString()] = title;
      chapterIndex++;
    }
    var comic = LocalComic(
      id: LocalManager().findValidId(ComicType.local),
      title: metaData.title,
      subtitle: metaData.author,
      tags: metaData.tags,
      comicType: ComicType.local,
      directory: dest.name,
      chapters: chapterMap.isEmpty ? null : ComicChapters(chapterMap),
      downloadedChapters: chapterMap.keys.toList(),
      cover: 'cover.${coverFile.extension}',
      createdAt: DateTime.now(),
    );
    await cache.delete(recursive: true);
    return comic;
  }

  static Future<File> export(LocalComic comic, String outFilePath) async {
    var cache = Directory(FilePath.join(App.cachePath, 'cbz_export'));
    if (cache.existsSync()) cache.deleteSync(recursive: true);
    cache.createSync();
    List<ComicChapter>? chapters;
    if (comic.chapters == null) {
      var images = await LocalManager().getImages(comic.id, comic.comicType, 1);
      int i = 1;
      for (var image in images) {
        var src = File(image.replaceFirst('file://', ''));
        var width = images.length.toString().length;
        var dstName =
            '${i.toString().padLeft(width, '0')}.${image.split('.').last}';
        var dst = File(FilePath.join(cache.path, dstName));
        await src.copyMem(dst.path);
        i++;
      }
    } else {
      chapters = [];
      var allImages = <String>[];
      for (var c in comic.downloadedChapters) {
        var chapterName = comic.chapters![c];
        var images = await LocalManager().getImages(
          comic.id,
          comic.comicType,
          c,
        );
        allImages.addAll(images);
        var chapter = ComicChapter(
          title: chapterName!,
          start: chapters.length + 1,
          end: chapters.length + images.length,
        );
        chapters.add(chapter);
      }
      int i = 1;
      for (var image in allImages) {
        var src = File(image);
        var width = allImages.length.toString().length;
        var dstName =
            '${i.toString().padLeft(width, '0')}.${image.split('.').last}';
        var dst = File(FilePath.join(cache.path, dstName));
        await src.copyMem(dst.path);
        i++;
      }
    }
    var cover = comic.coverFile;
    await cover.copyMem(
        FilePath.join(cache.path, 'cover.${cover.path.split('.').last}'));
    final metaData = ComicMetaData(
      title: comic.title,
      author: comic.subtitle,
      tags: comic.tags,
      chapters: chapters,
    );
    await File(FilePath.join(cache.path, 'metadata.json')).writeAsString(
      jsonEncode(metaData),
    );
    await File(FilePath.join(cache.path, 'ComicInfo.xml')).writeAsString(
      _buildComicInfoXml(metaData),
    );
    var cbz = File(outFilePath);
    if (cbz.existsSync()) cbz.deleteSync();
    await _compress(cache.path, cbz.path);
    cache.deleteSync(recursive: true);
    return cbz;
  }

  static String _buildComicInfoXml(ComicMetaData data) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="utf-8"?>');
    buffer.writeln('<ComicInfo xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">');

    buffer.writeln('  <Title>${_escapeXml(data.title)}</Title>');
    buffer.writeln('  <Series>${_escapeXml(data.title)}</Series>');

    if (data.author.isNotEmpty) {
      buffer.writeln('  <Writer>${_escapeXml(data.author)}</Writer>');
    }

    if (data.tags.isNotEmpty) {
      var tags = data.tags;
      if (tags.length > 5) {
        tags = tags.sublist(0, 5);
      }
      buffer.writeln('  <Genre>${_escapeXml(tags.join(', '))}</Genre>');
    }

    if (data.chapters != null && data.chapters!.isNotEmpty) {
      final chaptersInfo = data.chapters!.map((chapter) =>
        '${_escapeXml(chapter.title)}: ${chapter.start}-${chapter.end}'
      ).join('; ');
      buffer.writeln('  <Notes>Chapters: $chaptersInfo</Notes>');
    }

    buffer.writeln('  <Manga>Unknown</Manga>');
    buffer.writeln('  <BlackAndWhite>Unknown</BlackAndWhite>');

    final now = DateTime.now();
    buffer.writeln('  <Year>${now.year}</Year>');

    buffer.writeln('</ComicInfo>');
    return buffer.toString();
  }

  static String _escapeXml(String text) {
    return text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
  }

  static _compress(String src, String dst) async {
    await ZipFile.compressFolderAsync(src, dst, 4);
  }
}

