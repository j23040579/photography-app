import 'dart:io';
import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../services/app_store.dart';
import '../services/media_service.dart';
import '../services/reminder_service.dart';
import 'camera_screen.dart';
import 'memory_viewer.dart';
import 'theme.dart';

class AlbumDetail extends StatefulWidget {
  const AlbumDetail({
    super.key,
    required this.albumId,
    required this.store,
    required this.reminders,
  });
  final String albumId;
  final AppStore store;
  final ReminderService reminders;
  @override
  State<AlbumDetail> createState() => _AlbumDetailState();
}

class _AlbumDetailState extends State<AlbumDetail> {
  int tab = 0;
  bool busy = false;
  Album get album => widget.store.album(widget.albumId);
  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> act(Future<void> Function() action) async {
    if (busy) {
      return;
    }
    setState(() => busy = true);
    try {
      await action();
    } catch (error) {
      message(
        error is StateError
            ? error.message
            : error is ArgumentError
            ? error.message.toString()
            : 'Could not finish that action. Check permissions and available storage, then try again.',
      );
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<String?> textDialog(
    String title,
    String initial, {
    int lines = 3,
    int max = 1000,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: lines,
            minLines: lines,
            maxLength: max,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // The dialog transition can still reference the controller on this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    return result;
  }

  Future<bool> confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep it'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> capture({String? promptId}) async {
    final path = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const CameraScreen()));
    if (path != null) {
      await widget.store.addMemory(
        widget.albumId,
        File(path),
        isVideo: false,
        promptId: promptId,
      );
      message('A little moment, safely kept.');
    }
  }

  Future<void> import({bool video = false, String? promptId}) async {
    final media = MediaService(widget.store);
    if (video) {
      await media.importVideo(widget.albumId, promptId: promptId);
    } else {
      await media.importPhoto(widget.albumId, promptId: promptId);
    }
  }

  Future<void> editPrompt(PhotoPrompt prompt) async {
    final text = await textDialog(
      'Make this idea yours',
      prompt.text,
      max: 240,
    );
    if (text == null) {
      return;
    }
    if (text.isEmpty) {
      message('Keep a few words in your photo idea.');
      return;
    }
    await widget.store.saveAlbum(
      album.copyWith(
        prompts: album.prompts
            .map(
              (p) =>
                  p.id == prompt.id ? p.copyWith(text: text, edited: true) : p,
            )
            .toList(),
      ),
    );
  }

  Future<void> reminder({String? promptId}) async {
    if (!widget.reminders.available) {
      message(widget.reminders.status);
      return;
    }
    final now = DateTime.now();
    final initial = album.reminderAt?.isAfter(now) == true
        ? album.reminderAt!
        : album.eventDate.isAfter(now)
        ? album.eventDate
        : now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: album.reminderAt == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : TimeOfDay.fromDateTime(album.reminderAt!),
    );
    if (time == null) {
      return;
    }
    final at = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    final previous = album;
    final next = album.copyWith(reminderAt: at, reminderPromptId: promptId);
    await widget.reminders.scheduleAlbum(next);
    try {
      await widget.store.saveAlbum(next);
    } catch (_) {
      await widget.reminders.cancelAlbum(album.id);
      if (previous.reminderAt?.isAfter(DateTime.now()) ?? false) {
        await widget.reminders.scheduleAlbum(previous);
      }
      rethrow;
    }
    message(
      'Reminder set. Your device may delay it under battery or Focus settings.',
    );
  }

  Future<void> deleteAlbum() async {
    if (!await confirm(
      'Delete this album?',
      'Its photo ideas, notes, and app-owned media copies will be removed. Original files outside the app are kept.',
    )) {
      return;
    }
    await widget.reminders.cancelAlbum(album.id);
    await widget.store.deleteAlbum(album.id);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        "Jett's Archive",
        style: TextStyle(fontFamily: 'Georgia'),
      ),
      actions: [
        PopupMenuButton<String>(
          enabled: !busy,
          onSelected: (value) => act(() async {
            if (value == 'delete') {
              await deleteAlbum();
            }
            if (value == 'rename') {
              final name = await textDialog(
                'Rename album',
                album.title,
                lines: 1,
                max: 80,
              );
              if (name != null && name.isNotEmpty) {
                await widget.store.saveAlbum(album.copyWith(title: name));
              }
            }
          }),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename album')),
            PopupMenuItem(value: 'delete', child: Text('Delete album')),
          ],
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        if (!widget.store.albums.any((a) => a.id == widget.albumId)) {
          return const SizedBox.shrink();
        }
        final current = album;
        final done = current.prompts.where((p) => p.completed).length;
        return Column(
          children: [
            if (busy) const LinearProgressIndicator(value: 0.5, minHeight: 2),
            Expanded(
              child: AbsorbPointer(
                absorbing: busy,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 48),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1050),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                categoryIcon(current.category.name),
                                color: Palette.sage,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Eyebrow(current.category.label),
                              const Spacer(),
                              Text(
                                shortDate(current.eventDate),
                                style: const TextStyle(color: Palette.sage),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Text(
                            current.title,
                            style: Theme.of(context).textTheme.displayMedium,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'One occasion. A handful of ways to remember it.',
                            style: TextStyle(color: Palette.sage),
                          ),
                          const SizedBox(height: 24),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              FilledButton.icon(
                                onPressed: () => act(() => capture()),
                                icon: const Icon(Icons.camera_alt_outlined),
                                label: const Text('Take a photo'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => act(() => import()),
                                icon: const Icon(
                                  Icons.add_photo_alternate_outlined,
                                ),
                                label: const Text('Add photos'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => act(() => import(video: true)),
                                icon: const Icon(Icons.video_library_outlined),
                                label: const Text('Add videos'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          PaperCard(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(
                                  current.reminderAt == null
                                      ? Icons.notifications_none_rounded
                                      : Icons.notifications_active_outlined,
                                  color: Palette.sage,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        current.reminderAt == null
                                            ? 'Don’t let the little moments slip by.'
                                            : current.reminderAt!.isAfter(
                                                DateTime.now(),
                                              )
                                            ? 'A gentle nudge, scheduled.'
                                            : 'Your reminder time has passed.',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        current.reminderAt == null
                                            ? 'Plan a day ahead and set a reminder.'
                                            : '${shortDate(current.reminderAt!)} · ${TimeOfDay.fromDateTime(current.reminderAt!).format(context)}',
                                        style: const TextStyle(
                                          color: Palette.sage,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => act(() => reminder()),
                                  child: Text(
                                    current.reminderAt == null
                                        ? 'Set reminder'
                                        : 'Change',
                                  ),
                                ),
                                if (current.reminderAt != null)
                                  IconButton(
                                    tooltip: 'Remove reminder',
                                    onPressed: () => act(() async {
                                      await widget.reminders.cancelAlbum(
                                        current.id,
                                      );
                                      await widget.store.saveAlbum(
                                        album.copyWith(
                                          reminderAt: null,
                                          reminderPromptId: null,
                                        ),
                                      );
                                    }),
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SegmentedButton<int>(
                              segments: [
                                ButtonSegment(
                                  value: 0,
                                  icon: const Icon(Icons.auto_awesome_outlined),
                                  label: Text(
                                    'Photo ideas ($done/${current.prompts.length})',
                                  ),
                                ),
                                ButtonSegment(
                                  value: 1,
                                  icon: const Icon(Icons.collections_outlined),
                                  label: Text(
                                    'Memories (${current.memories.length})',
                                  ),
                                ),
                                const ButtonSegment(
                                  value: 2,
                                  icon: Icon(Icons.edit_note_rounded),
                                  label: Text('Notes'),
                                ),
                              ],
                              selected: {tab},
                              onSelectionChanged: (v) =>
                                  setState(() => tab = v.first),
                              showSelectedIcon: false,
                            ),
                          ),
                          const SizedBox(height: 26),
                          if (tab == 0) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'A little inspiration',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineMedium,
                                  ),
                                ),
                                const Icon(
                                  Icons.offline_bolt_outlined,
                                  size: 16,
                                  color: Palette.sage,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Like what speaks to you. Shuffle or edit anything. These ideas are for photos; your videos are welcome too.',
                              style: TextStyle(color: Palette.sage),
                            ),
                            const SizedBox(height: 20),
                            for (final (i, prompt) in current.prompts.indexed)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: promptCard(prompt, i),
                              ),
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'Ideas adapt to your likes and shuffles, right on your device.',
                                style: TextStyle(
                                  color: Palette.sage,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                          if (tab == 1) memories(current),
                          if (tab == 2) notes(current),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
  Widget promptCard(PhotoPrompt prompt, int index) => PaperCard(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${index + 1}'.padLeft(2, '0'),
              style: const TextStyle(
                fontFamily: 'Georgia',
                fontSize: 26,
                color: Palette.sage,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    prompt.text,
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.5,
                      color: prompt.completed ? Palette.sage : Palette.ink,
                      decoration: prompt.completed
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  if (prompt.edited)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Eyebrow('Made your own'),
                    ),
                ],
              ),
            ),
            Checkbox(
              value: prompt.completed,
              onChanged: (value) => act(() async {
                await widget.store.saveAlbum(
                  album.copyWith(
                    prompts: album.prompts
                        .map(
                          (p) => p.id == prompt.id
                              ? p.copyWith(completed: value ?? false)
                              : p,
                        )
                        .toList(),
                  ),
                );
              }),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              onPressed: () => act(() => capture(promptId: prompt.id)),
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: const Text('Capture'),
            ),
            TextButton.icon(
              onPressed: () => act(() => import(promptId: prompt.id)),
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('Attach'),
            ),
            IconButton(
              tooltip: 'I like this idea',
              onPressed: () => act(() async {
                await widget.store.recordFeedback(prompt, true);
                message('Noted. More ideas like this, just for you.');
              }),
              icon: const Icon(Icons.thumb_up_outlined, size: 19),
            ),
            IconButton(
              tooltip: 'Replace this idea',
              onPressed: () => act(
                () => widget.store.replacePrompt(widget.albumId, prompt.id),
              ),
              icon: const Icon(Icons.shuffle_rounded, size: 20),
            ),
            IconButton(
              tooltip: 'Remind me about this photo',
              onPressed: () => act(() => reminder(promptId: prompt.id)),
              icon: const Icon(Icons.notification_add_outlined, size: 20),
            ),
            IconButton(
              tooltip: 'Edit this idea',
              onPressed: () => act(() => editPrompt(prompt)),
              icon: const Icon(Icons.edit_outlined, size: 20),
            ),
          ],
        ),
      ],
    ),
  );
  Widget memories(Album current) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'The moments you kept',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 8),
      const Text(
        'Photos, videos, and all the little details.',
        style: TextStyle(color: Palette.sage),
      ),
      const SizedBox(height: 22),
      if (current.memories.isEmpty)
        const PaperCard(
          child: SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                Icon(Icons.photo_album_outlined, size: 40, color: Palette.sage),
                SizedBox(height: 18),
                Text(
                  'Your story is waiting to be captured.',
                  style: TextStyle(fontSize: 18),
                ),
                SizedBox(height: 8),
                Text(
                  'Use Take a photo, Add photos, or Add videos above.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Palette.sage),
                ),
              ],
            ),
          ),
        ),
      if (current.memories.isNotEmpty)
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth > 750
                ? 3
                : c.maxWidth > 440
                ? 2
                : 1;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: current.memories
                  .map(
                    (m) => SizedBox(
                      width: (c.maxWidth - (cols - 1) * 16) / cols,
                      child: memoryCard(m),
                    ),
                  )
                  .toList(),
            );
          },
        ),
    ],
  );
  Widget memoryCard(Memory memory) => PaperCard(
    padding: const EdgeInsets.all(10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => MemoryViewer(memory: memory),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: double.infinity,
              height: 200,
              child: memory.isVideo
                  ? Container(
                      color: Palette.ink,
                      child: const Center(
                        child: Icon(
                          Icons.play_circle_outline_rounded,
                          size: 58,
                          color: Palette.cream,
                        ),
                      ),
                    )
                  : Image.file(
                      File(memory.path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Center(
                        child: Icon(Icons.broken_image_outlined, size: 40),
                      ),
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 12, 6, 0),
          child: Text(
            memory.caption.isEmpty ? 'Add a little context…' : memory.caption,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: memory.caption.isEmpty ? Palette.sage : Palette.ink,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => act(() async {
                  final caption = await textDialog(
                    'Your memory, in words',
                    memory.caption,
                  );
                  if (caption != null) {
                    await widget.store.saveCaption(
                      widget.albumId,
                      memory.id,
                      caption,
                    );
                  }
                }),
                child: Text(
                  memory.caption.isEmpty ? 'Add comment' : 'Edit comment',
                ),
              ),
            ),
            IconButton(
              tooltip: 'Remove memory',
              onPressed: () => act(() async {
                if (await confirm(
                  'Remove this memory?',
                  'Only the app’s copy is removed. Original files outside the app are kept.',
                )) {
                  await widget.store.removeMemory(widget.albumId, memory.id);
                }
              }),
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
            ),
          ],
        ),
      ],
    ),
  );
  Widget notes(Album current) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'How will you remember it?',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 22),
      PaperCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Eyebrow('Rate the occasion'),
            const SizedBox(height: 12),
            Wrap(
              children: [
                for (int i = 1; i <= 5; i++)
                  IconButton(
                    tooltip: '$i stars',
                    onPressed: () => act(
                      () => widget.store.saveAlbum(album.copyWith(rating: i)),
                    ),
                    icon: Icon(
                      current.rating >= i
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: Palette.wine,
                      size: 34,
                    ),
                  ),
                if (current.rating > 0)
                  TextButton(
                    onPressed: () => act(
                      () => widget.store.saveAlbum(album.copyWith(rating: 0)),
                    ),
                    child: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            const Eyebrow('Your album notes'),
            const SizedBox(height: 12),
            Text(
              current.notes.isEmpty
                  ? 'The best part? The unexpected moment?\nWrite down what the camera couldn’t capture.'
                  : current.notes,
              style: TextStyle(
                height: 1.7,
                color: current.notes.isEmpty ? Palette.sage : Palette.ink,
              ),
            ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: () => act(() async {
                final text = await textDialog(
                  'The story behind the photos',
                  current.notes,
                  lines: 6,
                  max: 5000,
                );
                if (text != null) {
                  await widget.store.saveAlbum(album.copyWith(notes: text));
                }
              }),
              icon: const Icon(Icons.edit_note_rounded),
              label: Text(
                current.notes.isEmpty ? 'Write a note' : 'Edit notes',
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
