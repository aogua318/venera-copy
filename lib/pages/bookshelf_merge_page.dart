import 'package:flutter/material.dart';
import 'package:flutter_reorderable_grid_view/widgets/reorderable_builder.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/utils/io.dart';
import 'package:venera/utils/translations.dart';

/// Merge multiple local comics into one comic. Each source comic becomes a
/// chapter of the merged comic, ordered by the user with drag and drop.
class BookshelfMergePage extends StatefulWidget {
  const BookshelfMergePage({super.key, required this.comics});

  final List<LocalComic> comics;

  @override
  State<BookshelfMergePage> createState() => _BookshelfMergePageState();
}

class _BookshelfMergePageState extends State<BookshelfMergePage> {
  late List<LocalComic> comics;

  bool merging = false;

  final _scrollController = ScrollController();

  @override
  void initState() {
    comics = List.of(widget.comics);
    super.initState();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var tiles = comics.map((comic) {
      return ComicTile(
        key: Key(comic.id),
        comic: comic,
        enableLongPressed: false,
      );
    }).toList();
    return Scaffold(
      appBar: Appbar(
        title: Text("Merge Comics".tl),
        actions: [
          Button.filled(
            isLoading: merging,
            onPressed: merge,
            child: Text("Merge".tl),
          ).paddingRight(8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              "Drag to adjust the merge order. The first comic's folder name is used for the merged comic. The source comics will be deleted after merging."
                  .tl,
              style: TextStyle(color: context.colorScheme.outline),
            ),
          ),
          Expanded(
            child: ReorderableBuilder<LocalComic>(
              scrollController: _scrollController,
              longPressDelay: App.isDesktop
                  ? const Duration(milliseconds: 100)
                  : const Duration(milliseconds: 500),
              onReorder: (reorderFunc) {
                setState(() {
                  comics = reorderFunc(comics);
                });
              },
              builder: (children) {
                return GridView(
                  controller: _scrollController,
                  gridDelegate: SliverGridDelegateWithComics(),
                  children: children,
                );
              },
              children: tiles,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> merge() async {
    setState(() {
      merging = true;
    });
    try {
      var merged = await _mergeComics(comics);
      if (mounted) {
        context.pop(merged);
      }
    } catch (e, s) {
      Log.error("Merge Comics", e.toString(), s);
      if (mounted) {
        context.showMessage(message: e.toString());
        setState(() {
          merging = false;
        });
      }
    }
  }

  Future<LocalComic> _mergeComics(List<LocalComic> sources) async {
    var first = sources.first;
    var dirName = sanitizeFileName(
      "${first.directory}_${sources.length}_Merge",
      maxLength: 120,
    );
    var dest = Directory(FilePath.join(LocalManager().path, dirName));
    int suffix = 1;
    var finalName = dirName;
    while (dest.existsSync()) {
      finalName = "${dirName}_$suffix";
      dest = Directory(FilePath.join(LocalManager().path, finalName));
      suffix++;
    }
    dest.createSync(recursive: true);

    // Cover: reuse the first comic's cover file.
    var coverFile = first.coverFile;
    var coverName = "cover.${coverFile.extension}";
    if (coverFile.existsSync()) {
      await coverFile.copyMem(FilePath.join(dest.path, coverName));
    } else {
      coverName = "";
    }

    var chapters = <String, String>{};
    int chapterIndex = 0;
    for (var source in sources) {
      var sourceChapters = <(String, Directory)>[]; // (title, directory)
      if (source.hasChapters) {
        var ids = source.chapters!.ids;
        var titles = source.chapters!.titles;
        for (var i = 0; i < ids.length; i++) {
          var cid = ids.elementAt(i);
          var dir = Directory(FilePath.join(
            source.baseDir,
            LocalManager.getChapterDirectoryName(cid),
          ));
          sourceChapters.add(("${source.title} - ${titles.elementAt(i)}", dir));
        }
      } else {
        sourceChapters.add((source.title, Directory(source.baseDir)));
      }
      for (var (title, dir) in sourceChapters) {
        var files = dir.listSync().whereType<File>().toList();
        files.removeWhere((e) {
          var name = e.name;
          return name.startsWith('cover.') || name.startsWith('.');
        });
        files.sort((a, b) {
          var ai = int.tryParse(a.name.split('.').first);
          var bi = int.tryParse(b.name.split('.').first);
          if (ai != null && bi != null) return ai.compareTo(bi);
          return a.name.compareTo(b.name);
        });
        if (files.isEmpty) continue;
        var chapterDirName = chapterIndex.toString();
        var chapterDir = Directory(FilePath.join(dest.path, chapterDirName));
        chapterDir.createSync();
        for (var i = 0; i < files.length; i++) {
          var src = files[i];
          var dst = File(
              FilePath.join(chapterDir.path, '${i + 1}.${src.extension}'));
          try {
            src.renameSync(dst.path);
          } catch (_) {
            await src.copyMem(dst.path);
          }
        }
        chapters[chapterIndex.toString()] = title;
        chapterIndex++;
      }
    }
    if (chapters.isEmpty) {
      dest.deleteSync(recursive: true);
      throw Exception("No pages found in the selected comics");
    }

    var comic = LocalComic(
      id: LocalManager().findValidId(ComicType.local),
      title: finalName,
      subtitle: first.subtitle,
      tags: first.tags,
      directory: finalName,
      chapters: ComicChapters(chapters),
      cover: coverName,
      comicType: ComicType.local,
      downloadedChapters: chapters.keys.toList(),
      createdAt: DateTime.now(),
    );
    await LocalManager().add(comic, comic.id);
    // Delete the source comics. Their page directories have been moved, so
    // only the leftover directories (covers) are removed from the disk.
    for (var source in sources) {
      LocalManager().deleteComic(source, true);
    }
    return comic;
  }
}
