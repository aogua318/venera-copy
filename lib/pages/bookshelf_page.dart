import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/bookshelf.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/image_provider/history_image_provider.dart';
import 'package:venera/foundation/image_provider/local_comic_image.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/pages/bookshelf_merge_page.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';
import 'package:venera/pages/home_page.dart';
import 'package:venera/pages/reader/reader.dart';
import 'package:venera/utils/io.dart';
import 'package:venera/utils/translations.dart';

class BookshelfPage extends StatefulWidget {
  const BookshelfPage({super.key});

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  final _scrollController = ScrollController();

  bool selectionMode = false;

  Set<BookshelfItem> selected = {};

  String get _sortMode => appdata.settings['bookshelfSortMode'];

  void update() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void initState() {
    BookshelfManager().addListener(update);
    BookshelfManager().prune();
    super.initState();
  }

  @override
  void dispose() {
    BookshelfManager().removeListener(update);
    _scrollController.dispose();
    super.dispose();
  }

  void exitSelectionMode() {
    setState(() {
      selectionMode = false;
      selected.clear();
    });
  }

  void toggleSelect(BookshelfItem entry) {
    setState(() {
      if (!selected.remove(entry)) {
        selected.add(entry);
      }
      if (selected.isEmpty) {
        selectionMode = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    var items = BookshelfManager().sortedItems();
    return PopScope(
      canPop: !selectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && selectionMode) {
          exitSelectionMode();
        }
      },
      child: Scaffold(
        appBar: buildAppbar(items),
        body: buildBody(items),
      ),
    );
  }

  PreferredSizeWidget buildAppbar(List<BookshelfItem> items) {
    if (selectionMode) {
      return Appbar(
        leading: Tooltip(
          message: "Cancel".tl,
          child: IconButton(
            icon: const Icon(Icons.close),
            onPressed: exitSelectionMode,
          ),
        ),
        title: Text(selected.length.toString()),
        actions: [
          if (selected.length >= 2)
            IconButton(
              icon: const Icon(Icons.merge),
              tooltip: "Merge".tl,
              onPressed: openMergePage,
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: "Delete".tl,
            onPressed: deleteSelectedComics,
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_remove_outlined),
            tooltip: "Remove from bookshelf".tl,
            onPressed: () {
              for (var entry in selected) {
                BookshelfManager().remove(entry.id, entry.type);
              }
              exitSelectionMode();
            },
          ),
          MenuButton(entries: [
            MenuEntry(
              icon: Icons.select_all,
              text: "Select All".tl,
              onClick: () {
                setState(() {
                  selected = items.toSet();
                });
              },
            ),
            MenuEntry(
              icon: Icons.flip,
              text: "Invert Selection".tl,
              onClick: () {
                setState(() {
                  selected = items.toSet().difference(selected);
                });
              },
            ),
            MenuEntry(
              icon: Icons.deselect,
              text: "Select None".tl,
              onClick: () {
                setState(() {
                  selected.clear();
                });
              },
            ),
          ]),
        ],
      );
    }
    return Appbar(
      title: Text("Bookshelf".tl),
      actions: [
        IconButton(
          icon: const Icon(Icons.sort),
          onPressed: sort,
        ),
        IconButton(
          icon: const Icon(Icons.grid_view),
          tooltip: "View Mode".tl,
          onPressed: selectViewMode,
        ),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: import,
        ),
      ],
    );
  }

  Widget buildBody(List<BookshelfItem> items) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("The bookshelf is empty".tl),
            const SizedBox(height: 8),
            Button.filled(
              onPressed: import,
              child: Text("Import".tl),
            ),
          ],
        ),
      );
    }
    var viewMode = appdata.settings['bookshelfViewMode'] ?? 'grid';
    var entries = <(BookshelfItem, dynamic)>[];
    for (var entry in items) {
      var comic = entry.resolveComic();
      if (comic == null) continue;
      entries.add((entry, comic));
    }
    if (viewMode == 'list') {
      // Row cards with covers scaled to fill the row height.
      var children = <Widget>[];
      for (var (entry, comic) in entries) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: buildItem(entry, comic, viewMode),
          ),
        );
      }
      return GridView(
        controller: _scrollController,
        gridDelegate: SliverGridDelegateWithComics(),
        children: children,
      );
    } else if (viewMode == 'waterfall') {
      var crossAxisCount = (context.width / 150).floor().clamp(2, 6);
      return MasonryGridView.count(
        controller: _scrollController,
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        padding: const EdgeInsets.all(8),
        itemBuilder: (context, i) =>
            buildItem(entries[i].$1, entries[i].$2, viewMode),
        itemCount: entries.length,
      );
    } else {
      // Uniform grid. Cells are sized to fit one tile, the tile is centered
      // so the selection border aligns with it.
      var crossAxisCount = (context.width / 110).floor().clamp(2, 8);
      return GridView.count(
        controller: _scrollController,
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.62,
        children: [
          for (var (entry, comic) in entries)
            Padding(
              padding: const EdgeInsets.all(4),
              child: buildItem(entry, comic, viewMode),
            ),
        ],
      );
    }
  }

  Widget buildItem(BookshelfItem entry, dynamic comic, String viewMode) {
    var isSelected = selected.contains(entry);
    Widget child;
    if (viewMode == 'waterfall') {
      child = _WaterfallTile(
        comic: comic,
        onTap: () => onItemTap(entry, comic),
        onLongPressed: () => enterSelectionMode(entry),
      );
    } else if (viewMode == 'grid') {
      child = _WaterfallTile(
        fixedAspect: 0.72,
        comic: comic,
        onTap: () => onItemTap(entry, comic),
        onLongPressed: () => enterSelectionMode(entry),
      );
    } else if (viewMode == 'list') {
      // Row card: the cover scales to fill the row height, keeping its
      // natural aspect ratio.
      var scale = (appdata.settings['comicTileScale'] as num).toDouble();
      var height = 152 * scale - 24;
      child = _BookshelfListTile(
        comic: comic,
        height: height,
        onTap: () => onItemTap(entry, comic),
        onLongPressed: () => enterSelectionMode(entry),
      );
    } else {
      child = ComicTile(
        comic: comic,
        onTap: () => onItemTap(entry, comic),
        onLongPressed: () => enterSelectionMode(entry),
      );
    }
    if (isSelected) {
      child = Stack(
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: context.colorScheme.primary,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: Icon(
              Icons.check_circle,
              color: context.colorScheme.primary,
            ),
          ),
        ],
      );
    }
    // Rebuild elements when the view mode changes so selection marks always
    // follow the item's new position.
    return KeyedSubtree(
      key: ValueKey("$viewMode:${entry.id}:$isSelected"),
      child: child,
    );
  }

  void onItemTap(BookshelfItem entry, dynamic comic) {
    if (selectionMode) {
      toggleSelect(entry);
      return;
    }
    _openComic(entry, comic);
  }

  void enterSelectionMode(BookshelfItem entry) {
    setState(() {
      selectionMode = true;
      selected.add(entry);
    });
  }

  void _openComic(BookshelfItem entry, dynamic comic) {
    if (comic is LocalComic) {
      var history = HistoryManager().find(comic.id, ComicType.local);
      // Push to the root navigator so the reader is fullscreen and the
      // back button leaves the reader instead of staying in the pane.
      App.rootContext.to(() {
        return Reader(
          type: ComicType.local,
          cid: comic.id,
          name: comic.title,
          chapters: comic.chapters,
          initialPage: history?.page,
          initialChapter: history?.ep,
          initialChapterGroup: history?.group,
          history: history ?? History.fromModel(model: comic, ep: 0, page: 0),
          author: comic.subTitle ?? '',
          tags: comic.tags,
        );
      });
    } else {
      context.to(() => ComicPage(
            id: entry.id,
            sourceKey: entry.type.sourceKey,
          ));
    }
  }

  void selectViewMode() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return ContentDialog(
            title: "View Mode".tl,
            content: RadioGroup<String>(
              groupValue: appdata.settings['bookshelfViewMode'] ?? 'grid',
              onChanged: (v) {
                if (v != null) {
                  appdata.settings['bookshelfViewMode'] = v;
                  appdata.saveData();
                }
                // Apply and close the dialog immediately.
                this.setState(() {});
                context.pop();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    title: Text("List".tl),
                    value: 'list',
                  ),
                  RadioListTile<String>(
                    title: Text("Grid".tl),
                    value: 'grid',
                  ),
                  RadioListTile<String>(
                    title: Text("Waterfall".tl),
                    value: 'waterfall',
                  ),
                ],
              ),
            ),
            actions: [
              Button.filled(
                onPressed: context.pop,
                child: Text("Confirm".tl),
              ),
            ],
          );
        });
      },
    );
  }

  void sort() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return ContentDialog(
            title: "Sort".tl,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioGroup<String>(
                  groupValue: _sortMode,
                  onChanged: (v) {
                    setState(() {
                      if (v == _sortMode) {
                        // Selecting the same sort again reverses the order.
                        appdata.settings['bookshelfSortDesc'] =
                            !(appdata.settings['bookshelfSortDesc'] == true);
                      } else {
                        appdata.settings['bookshelfSortMode'] =
                            v ?? 'addedTime';
                        appdata.settings['bookshelfSortDesc'] = false;
                      }
                      appdata.saveData();
                    });
                    this.setState(() {});
                  },
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        title: Text("Added Time".tl),
                        value: 'addedTime',
                      ),
                      RadioListTile<String>(
                        title: Text("Name".tl),
                        value: 'name',
                      ),
                      RadioListTile<String>(
                        title: Text("Last Read Time".tl),
                        value: 'lastRead',
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  title: Text("Descending".tl),
                  value: appdata.settings['bookshelfSortDesc'] == true,
                  onChanged: (v) {
                    setState(() {
                      appdata.settings['bookshelfSortDesc'] = v;
                      appdata.saveData();
                    });
                    this.setState(() {});
                  },
                ),
              ],
            ),
            actions: [
              Button.filled(
                onPressed: context.pop,
                child: Text("Confirm".tl),
              ),
            ],
          );
        });
      },
    );
  }

  void openMergePage() async {
    var comics = selected
        .map((e) => LocalManager().find(e.id, e.type))
        .whereType<LocalComic>()
        .toList();
    if (comics.length < 2) {
      showToast(context: context, message: "Only local comics can be merged".tl);
      return;
    }
    var merged = await context.to(() => BookshelfMergePage(comics: comics));
    if (merged is LocalComic) {
      for (var comic in comics) {
        BookshelfManager().remove(comic.id, ComicType.local);
      }
      BookshelfManager().add(merged.id, ComicType.local);
      exitSelectionMode();
    }
  }

  /// Delete the selected comics from the app (and their files on disk for
  /// local comics), with a progress dialog.
  void deleteSelectedComics() async {
    var localComics = selected
        .map((e) => LocalManager().find(e.id, e.type))
        .whereType<LocalComic>()
        .toList();
    var confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return ContentDialog(
          title: "Delete".tl,
          content: Text(
            "Delete @a comics? Local comics will also be removed from the disk."
                .tlParams({'a': selected.length}),
          ),
          actions: [
            Button.text(
              onPressed: () => context.pop(false),
              child: Text("Cancel".tl),
            ),
            Button.filled(
              onPressed: () => context.pop(true),
              child: Text("Confirm".tl),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    var controller = showLoadingDialog(
      App.rootContext,
      allowCancel: false,
      withProgress: true,
      message: "Deleting comics".tl,
    );
    var startedAt = DateTime.now();
    setScreenOn(true);
    try {
      await LocalManager().batchDeleteComics(
        localComics,
        removeFileOnDisk: true,
        removeFavoriteAndHistory: true,
        onFileDeleteProgress: (done, total) {
          controller.setMessage("Deleting @a/@b"
              .tlParams({'a': done, 'b': total}));
          controller.setProgress(total == 0 ? null : done / total);
        },
      );
      // Remove all selected entries from the shelf (local comics are gone,
      // network comics are only removed from the shelf).
      for (var entry in selected) {
        BookshelfManager().remove(entry.id, entry.type);
      }
      exitSelectionMode();
    } finally {
      var elapsed = DateTime.now().difference(startedAt);
      const minDuration = Duration(milliseconds: 600);
      if (elapsed < minDuration) {
        await Future.delayed(minDuration - elapsed);
      }
      controller.close();
      setScreenOn(false);
    }
  }

  /// Run the same import flow as the home page's local import, then add the
  /// newly imported comics to the shelf.
  void import() async {
    var before = LocalManager()
        .getComics(LocalSortType.name)
        .map((e) => e.id)
        .toSet();
    await showDialog(
      barrierDismissible: false,
      context: App.rootContext,
      builder: (context) {
        return const ImportComicsWidget();
      },
    );
    var added = LocalManager()
        .getComics(LocalSortType.name)
        .where((e) => !before.contains(e.id))
        .toList();
    if (added.isNotEmpty) {
      BookshelfManager().addAll(added.map((e) => (e.id, ComicType.local)));
      if (mounted) {
        showToast(
          context: context,
          message: "Imported @c comics to bookshelf"
              .tlParams({'c': added.length}),
        );
      }
    }
  }
}

/// Aspect ratio cache for comic covers, keyed by "sourceKey@id".
final Map<String, double> _coverAspectCache = {};

ImageProvider? _coverProvider(dynamic comic) {
  if (comic is LocalComic) {
    return LocalComicImageProvider(comic);
  } else if (comic is History) {
    return HistoryImageProvider(comic);
  }
  return null;
}

/// A comic tile for the waterfall view. The height follows the natural
/// aspect ratio of the cover image.
class _WaterfallTile extends StatefulWidget {
  const _WaterfallTile({
    required this.comic,
    required this.onTap,
    required this.onLongPressed,
    this.fixedAspect,
  });

  final dynamic comic;

  final VoidCallback onTap;

  final VoidCallback onLongPressed;

  /// When set, the cover uses this fixed aspect ratio instead of the natural
  /// aspect ratio of the image.
  final double? fixedAspect;

  @override
  State<_WaterfallTile> createState() => _WaterfallTileState();
}

class _WaterfallTileState extends State<_WaterfallTile> {
  static const _defaultAspect = 0.7;

  ImageProvider? _provider;

  double _aspect = _defaultAspect;

  ImageStream? _stream;
  ImageStreamListener? _listener;

  double? get _fixedAspect => widget.fixedAspect;

  String get _cacheKey => "${widget.comic.sourceKey}@${widget.comic.id}";

  @override
  void initState() {
    super.initState();
    _provider = _coverProvider(widget.comic);
    if (widget.fixedAspect != null) {
      _aspect = widget.fixedAspect!;
      return;
    }
    var cached = _coverAspectCache[_cacheKey];
    if (cached != null) {
      _aspect = cached;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveAspectRatio();
  }

  void _resolveAspectRatio() {
    var provider = _provider;
    if (widget.fixedAspect != null ||
        provider == null ||
        _coverAspectCache.containsKey(_cacheKey)) {
      return;
    }
    _stream?.removeListener(_listener!);
    var stream = provider.resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      var aspect = info.image.width / info.image.height;
      _coverAspectCache[_cacheKey] = aspect;
      if (mounted) {
        setState(() {
          _aspect = aspect;
        });
      }
      stream.removeListener(listener);
    }, onError: (_, __) {});
    _listener = listener;
    _stream = stream;
    stream.addListener(listener);
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      onLongPress: widget.onLongPressed,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _provider == null
                ? Container(
                    width: double.infinity,
                    color: context.colorScheme.secondaryContainer,
                    child: const SizedBox(height: 100),
                  )
                : AspectRatio(
                    aspectRatio: _aspect,
                    child: Image(
                      image: _provider!,
                      width: double.infinity,
                      fit: _fixedAspect != null
                          ? BoxFit.contain
                          : BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.comic.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ts.s12,
          ),
        ],
      ),
    );
  }
}

/// A row card for the list view. The cover keeps its natural aspect ratio
/// and scales to fill the row height.
class _BookshelfListTile extends StatefulWidget {
  const _BookshelfListTile({
    required this.comic,
    required this.height,
    required this.onTap,
    required this.onLongPressed,
  });

  final dynamic comic;

  final double height;

  final VoidCallback onTap;

  final VoidCallback onLongPressed;

  @override
  State<_BookshelfListTile> createState() => _BookshelfListTileState();
}

class _BookshelfListTileState extends State<_BookshelfListTile> {
  ImageProvider? _provider;

  double _aspect = 0.72;

  ImageStream? _stream;
  ImageStreamListener? _listener;

  String get _cacheKey => "${widget.comic.sourceKey}@${widget.comic.id}";

  @override
  void initState() {
    super.initState();
    _provider = _coverProvider(widget.comic);
    var cached = _coverAspectCache[_cacheKey];
    if (cached != null) {
      _aspect = cached;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveAspectRatio();
  }

  void _resolveAspectRatio() {
    var provider = _provider;
    if (provider == null || _coverAspectCache.containsKey(_cacheKey)) {
      return;
    }
    _stream?.removeListener(_listener!);
    var stream = provider.resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      var aspect = info.image.width / info.image.height;
      _coverAspectCache[_cacheKey] = aspect;
      if (mounted) {
        setState(() {
          _aspect = aspect;
        });
      }
      stream.removeListener(listener);
    }, onError: (_, __) {});
    _listener = listener;
    _stream = stream;
    stream.addListener(listener);
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var subtitle = widget.comic.subtitle?.toString() ?? '';
    return InkWell(
      onTap: widget.onTap,
      onLongPress: widget.onLongPressed,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: _provider == null
                  ? 36.0
                  : (widget.height * _aspect).clamp(36.0, 280.0),
              height: widget.height,
              color: context.colorScheme.secondaryContainer,
              child: _provider == null
                  ? null
                  : Image(
                      image: _provider!,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.comic.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ts.s14,
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts.s12
                        .copyWith(color: context.colorScheme.outline),
                  ).paddingTop(4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
