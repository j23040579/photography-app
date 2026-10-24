import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/models.dart';
import 'theme.dart';

/// Logical size of the card (4:5). It is exported at 3x, i.e. 1080 x 1350 px.
const double albumCardWidth = 360;
const double albumCardHeight = 450;

/// Photos shown on the card: up to [max] still photos (never videos) whose
/// files still exist, oldest first.
List<File> cardPhotos(Album album, {int max = 4}) {
  final photos = album.memories.where((m) => !m.isVideo).toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final files = <File>[];
  for (final memory in photos) {
    final file = File(memory.path);
    if (file.existsSync()) files.add(file);
    if (files.length == max) break;
  }
  return files;
}

/// Downscaled provider so large camera photos do not use much memory.
ImageProvider cardImage(File file) => ResizeImage(FileImage(file), width: 900);

String _date(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

IconData _categoryIcon(PlaceCategory category) => switch (category) {
  PlaceCategory.restaurant => Icons.restaurant,
  PlaceCategory.party => Icons.celebration,
  PlaceCategory.travel => Icons.flight,
  PlaceCategory.outdoors => Icons.park,
  PlaceCategory.everyday => Icons.wb_sunny_outlined,
  PlaceCategory.celebration => Icons.cake_outlined,
};

/// The picture that gets shared. Private captions and comments are never
/// drawn here; the album note is only drawn when [includeNote] is true.
class AlbumCard extends StatelessWidget {
  const AlbumCard({
    super.key,
    required this.album,
    required this.photos,
    this.includeNote = false,
  });

  final Album album;
  final List<File> photos;
  final bool includeNote;

  @override
  Widget build(BuildContext context) {
    final done = album.prompts.where((p) => p.completed).length;
    final progress = album.prompts.isEmpty
        ? '${album.memories.length} memories'
        : '$done of ${album.prompts.length} ideas captured';
    final note = album.notes.trim();
    return DefaultTextStyle(
      style: const TextStyle(
        color: Palette.ink,
        fontSize: 14,
        decoration: TextDecoration.none,
        fontWeight: FontWeight.normal,
      ),
      child: Container(
        width: albumCardWidth,
        height: albumCardHeight,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Palette.paper,
          border: Border.all(color: Palette.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    album.category.label.toUpperCase(),
                    style: const TextStyle(
                      color: Palette.sage,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
                Text(
                  _date(album.eventDate),
                  style: const TextStyle(color: Palette.sage, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              album.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Georgia',
                fontSize: 28,
                height: 1.15,
                color: Palette.ink,
              ),
            ),
            if (album.rating > 0) ...[
              const SizedBox(height: 6),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < album.rating
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 20,
                    color: Palette.wine,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Expanded(
              child: _Collage(photos: photos, category: album.category),
            ),
            if (includeNote && note.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    progress,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Palette.sage, fontSize: 12),
                  ),
                ),
                const Text(
                  "Jett's Archive",
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 14,
                    color: Palette.wine,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Collage extends StatelessWidget {
  const _Collage({required this.photos, required this.category});

  final List<File> photos;
  final PlaceCategory category;

  static const double _gap = 4;

  Widget _tile(File file) => Image(
    image: cardImage(file),
    fit: BoxFit.cover,
    width: double.infinity,
    height: double.infinity,
    errorBuilder: (_, _, _) => const ColoredBox(color: Palette.line),
  );

  @override
  Widget build(BuildContext context) {
    switch (photos.length) {
      case 0:
        return ColoredBox(
          color: Palette.cream,
          child: Center(
            child: Icon(
              _categoryIcon(category),
              size: 64,
              color: Palette.sage.withValues(alpha: 0.6),
            ),
          ),
        );
      case 1:
        return _tile(photos[0]);
      case 2:
        return Row(
          children: [
            Expanded(child: _tile(photos[0])),
            const SizedBox(width: _gap),
            Expanded(child: _tile(photos[1])),
          ],
        );
      case 3:
        return Row(
          children: [
            Expanded(flex: 3, child: _tile(photos[0])),
            const SizedBox(width: _gap),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  Expanded(child: _tile(photos[1])),
                  const SizedBox(height: _gap),
                  Expanded(child: _tile(photos[2])),
                ],
              ),
            ),
          ],
        );
      default:
        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _tile(photos[0])),
                  const SizedBox(width: _gap),
                  Expanded(child: _tile(photos[1])),
                ],
              ),
            ),
            const SizedBox(height: _gap),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _tile(photos[2])),
                  const SizedBox(width: _gap),
                  Expanded(child: _tile(photos[3])),
                ],
              ),
            ),
          ],
        );
    }
  }
}

/// Shows a preview of the card with a Share button (WhatsApp, Instagram,
/// Messages, email... on Android; the Windows share dialog on desktop).
Future<void> showAlbumCardDialog(BuildContext context, Album album) =>
    showDialog<void>(
      context: context,
      builder: (_) => _AlbumCardDialog(album: album),
    );

class _AlbumCardDialog extends StatefulWidget {
  const _AlbumCardDialog({required this.album});
  final Album album;

  @override
  State<_AlbumCardDialog> createState() => _AlbumCardDialogState();
}

class _AlbumCardDialogState extends State<_AlbumCardDialog> {
  final _boundaryKey = GlobalKey();
  late final List<File> photos = cardPhotos(widget.album);
  bool includeNote = false;
  bool sharing = false;
  String? error;

  Future<void> _share() async {
    setState(() {
      sharing = true;
      error = null;
    });
    try {
      // Make sure every photo is decoded before the card is captured.
      await Future.wait(
        photos
            .map(
              (f) => precacheImage(cardImage(f), context, onError: (_, _) {}),
            )
            .toList(),
      );
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('The preview is not ready.');
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('The card could not be created.');
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}${Platform.pathSeparator}'
        'album-card-${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'image/png')]),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not create or share the card on this device. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasNote = widget.album.notes.trim().isNotEmpty;
    return Dialog(
      backgroundColor: Palette.cream,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Share album card',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              AspectRatio(
                aspectRatio: albumCardWidth / albumCardHeight,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: RepaintBoundary(
                    key: _boundaryKey,
                    child: AlbumCard(
                      album: widget.album,
                      photos: photos,
                      includeNote: includeNote,
                    ),
                  ),
                ),
              ),
              if (hasNote)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Include my album note'),
                  subtitle: const Text('Photo captions always stay private.'),
                  value: includeNote,
                  onChanged: sharing
                      ? null
                      : (value) => setState(() => includeNote = value),
                ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: sharing ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: sharing ? null : _share,
                    icon: sharing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.share_outlined),
                    label: const Text('Share'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
