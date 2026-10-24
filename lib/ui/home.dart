import 'dart:io';
import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../services/app_store.dart';
import '../services/media_service.dart';
import '../services/reminder_service.dart';
import 'album_detail.dart';
import 'create_album.dart';
import 'onboarding.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store, required this.reminders});
  final AppStore store;
  final ReminderService reminders;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int page = 0;
  String query = '';
  PlaceCategory? filter;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => recover());
  }

  Future<void> recover() async {
    await widget.reminders.restoreReminders(widget.store.albums);
    final media = MediaService(widget.store);
    final recovered = await media.recoverLostCapture();
    final notice =
        widget.store.recoveryNotice ??
        media.recoveryNotice ??
        (recovered > 0 ? 'Recovered an interrupted camera memory.' : null);
    if (mounted && notice != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(notice)));
    }
  }

  Future<void> create() async {
    final album = await showDialog<Album>(
      context: context,
      builder: (_) =>
          CreateAlbumDialog(store: widget.store, reminders: widget.reminders),
    );
    if (album != null && mounted) {
      open(album);
    }
  }

  void open(Album album) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AlbumDetail(
        albumId: album.id,
        store: widget.store,
        reminders: widget.reminders,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 900;
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              if (desktop)
                Container(
                  width: 236,
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: Palette.line)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 30,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.camera_rounded,
                          color: Palette.wine,
                          size: 32,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "Jett's Archive",
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 4),
                        const Eyebrow('Collect the everyday'),
                        const SizedBox(height: 44),
                        for (int i = 0; i < 3; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              selected: page == i,
                              selectedTileColor: Palette.wine,
                              selectedColor: Palette.paper,
                              leading: Icon(
                                [
                                  Icons.space_dashboard_outlined,
                                  Icons.collections_bookmark_outlined,
                                  Icons.menu_book_outlined,
                                ][i],
                              ),
                              title: Text(
                                ['My journal', 'All albums', 'Field guide'][i],
                              ),
                              onTap: () => setState(() => page = i),
                            ),
                          ),
                        const Spacer(),
                        const Icon(
                          Icons.lock_outline_rounded,
                          color: Palette.sage,
                          size: 20,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Only yours.\nSaved on this device.',
                          style: TextStyle(
                            color: Palette.sage,
                            height: 1.6,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: ListenableBuilder(
                  listenable: widget.store,
                  builder: (context, _) => CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          desktop ? 44 : 20,
                          desktop ? 36 : 20,
                          desktop ? 44 : 20,
                          110,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1140),
                              child: page == 2 ? guide() : journal(desktop),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: desktop
            ? null
            : NavigationBar(
                selectedIndex: page,
                onDestinationSelected: (v) => setState(() => page = v),
                backgroundColor: Palette.paper,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.space_dashboard_outlined),
                    label: 'Journal',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.collections_bookmark_outlined),
                    label: 'Albums',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.menu_book_outlined),
                    label: 'Guide',
                  ),
                ],
              ),
        floatingActionButton: page == 2
            ? null
            : FloatingActionButton.extended(
                onPressed: create,
                backgroundColor: Palette.wine,
                foregroundColor: Palette.paper,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create album'),
              ),
      );
    },
  );
  Widget journal(bool desktop) {
    final albums =
        widget.store.albums
            .where(
              (a) =>
                  (filter == null || a.category == filter) &&
                  a.title.toLowerCase().contains(query.toLowerCase()),
            )
            .toList()
          ..sort((a, b) => b.eventDate.compareTo(a.eventDate));
    final memories = widget.store.albums.fold<int>(
      0,
      (sum, a) => sum + a.memories.length,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Eyebrow(
                page == 0 ? 'YOUR PERSONAL PHOTO JOURNAL' : 'THE COLLECTION',
              ),
            ),
            const Icon(
              Icons.offline_bolt_rounded,
              size: 16,
              color: Palette.sage,
            ),
            const SizedBox(width: 4),
            const Text(
              'Offline & private',
              style: TextStyle(color: Palette.sage, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (page == 0) ...[
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(desktop ? 38 : 24),
            decoration: BoxDecoration(
              color: Palette.wine,
              borderRadius: BorderRadius.circular(24),
            ),
            child: LayoutBuilder(
              builder: (context, c) => Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Eyebrow(
                          'LESS SCROLLING. MORE NOTICING.',
                          color: Palette.cream,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Life happens.\nKeep a little of it.',
                          style:
                              (desktop
                                      ? Theme.of(
                                          context,
                                        ).textTheme.displayMedium
                                      : Theme.of(
                                          context,
                                        ).textTheme.headlineLarge)
                                  ?.copyWith(color: Palette.cream),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'An occasion. A few photo ideas.\nA story only you can tell.',
                          style: TextStyle(
                            color: Palette.cream,
                            height: 1.6,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Palette.cream,
                            foregroundColor: Palette.wine,
                          ),
                          onPressed: create,
                          icon: const Icon(Icons.add),
                          label: const Text('Start a new album'),
                        ),
                      ],
                    ),
                  ),
                  if (c.maxWidth > 650)
                    const SizedBox(
                      width: 190,
                      height: 200,
                      child: JournalArtwork(),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              Text(
                '${widget.store.albums.length} albums',
                style: const TextStyle(color: Palette.sage),
              ),
              Text(
                '$memories memories kept',
                style: const TextStyle(color: Palette.sage),
              ),
            ],
          ),
          const SizedBox(height: 24),
          PaperCard(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const Icon(Icons.wb_twilight_rounded, color: Palette.sage),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Give tomorrow a head start.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Create your album a day ahead. A little planning helps you stay in the moment.',
                        style: TextStyle(color: Palette.sage, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Plan an album',
                  onPressed: create,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ] else ...[
          Text(
            'Every album,\na little time capsule.',
            style: Theme.of(context).textTheme.displayMedium,
          ),
          const SizedBox(height: 28),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                page == 0 ? 'Your little time capsules' : 'Browse your albums',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            if (page == 0)
              TextButton(
                onPressed: () => setState(() => page = 1),
                child: const Text('View all'),
              ),
          ],
        ),
        const SizedBox(height: 18),
        TextField(
          onChanged: (v) => setState(() => query = v),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Find an album…',
          ),
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: const Text('All occasions'),
                  selected: filter == null,
                  onSelected: (_) => setState(() => filter = null),
                ),
              ),
              for (final category in PlaceCategory.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(category.label),
                    selected: filter == category,
                    onSelected: (_) => setState(() => filter = category),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (albums.isEmpty)
          PaperCard(
            child: SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  const Icon(
                    Icons.auto_stories_outlined,
                    size: 44,
                    color: Palette.sage,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    widget.store.albums.isEmpty
                        ? 'The first page is yours.'
                        : 'No albums found.',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.store.albums.isEmpty
                        ? 'Dinner with friends? A weekend away?\nStart with an occasion and we’ll bring the ideas.'
                        : 'Try another search or occasion.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Palette.sage),
                  ),
                  const SizedBox(height: 22),
                  OutlinedButton.icon(
                    onPressed: create,
                    icon: const Icon(Icons.add),
                    label: const Text('Create an album'),
                  ),
                ],
              ),
            ),
          ),
        if (albums.isNotEmpty)
          LayoutBuilder(
            builder: (context, c) {
              final columns = c.maxWidth > 820
                  ? 3
                  : c.maxWidth > 500
                  ? 2
                  : 1;
              return Wrap(
                spacing: 18,
                runSpacing: 18,
                children: albums
                    .map(
                      (album) => SizedBox(
                        width: (c.maxWidth - (columns - 1) * 18) / columns,
                        child: albumCard(album),
                      ),
                    )
                    .toList(),
              );
            },
          ),
      ],
    );
  }

  Widget albumCard(Album album) {
    final photos = album.memories.where((m) => !m.isVideo);
    final photo = photos.isEmpty ? null : photos.first;
    return Material(
      color: Palette.paper,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => open(album),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 165,
              width: double.infinity,
              child: photo == null
                  ? Container(
                      color: album.category.index.isEven
                          ? Palette.sage
                          : Palette.wine,
                      child: Center(
                        child: Icon(
                          categoryIcon(album.category.name),
                          size: 54,
                          color: Palette.cream,
                        ),
                      ),
                    )
                  : Image.file(
                      File(photo.path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Center(
                        child: Icon(Icons.broken_image_outlined, size: 40),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Eyebrow(album.category.label)),
                      Text(
                        shortDate(album.eventDate),
                        style: const TextStyle(
                          color: Palette.sage,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    album.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(
                        Icons.photo_library_outlined,
                        size: 15,
                        color: Palette.sage,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${album.memories.length} memories',
                        style: const TextStyle(
                          color: Palette.sage,
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${album.prompts.where((p) => p.completed).length}/${album.prompts.length} ideas',
                        style: const TextStyle(
                          color: Palette.sage,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget guide() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Eyebrow('A field guide to noticing'),
      const SizedBox(height: 18),
      Text(
        'Good memories\nstart with curiosity.',
        style: Theme.of(context).textTheme.displayMedium,
      ),
      const SizedBox(height: 28),
      for (final entry in [
        (
          '01',
          'Plan a little ahead',
          'Create an album for tomorrow and choose your occasion. Read your photo list before you go; a reminder can give you a gentle nudge.',
        ),
        (
          '02',
          'Make the ideas yours',
          'Like an idea to teach your on-device suggestions what you enjoy. Shuffle to replace it or edit the words yourself. New albums get fresh combinations; ideas repeat after the category’s pool is used.',
        ),
        (
          '03',
          'Capture, then be there',
          'Take a photo with your camera, or import photos and videos you already have. Attach a photo to an idea or tick it off yourself. Always ask before photographing others.',
        ),
        (
          '04',
          'Keep the whole story',
          'Rate the occasion, write an album note, and add captions as your personal comments. Photos, videos, and suggestions are stored on this device. Uninstalling the app may remove them.',
        ),
        (
          '05',
          'A gentle reminder',
          'Set a date and time in an album. Allow notifications when asked. Battery settings and Focus/Do Not Disturb can delay reminders; Windows must allow desktop app notifications.',
        ),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: PaperCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.$1,
                  style: const TextStyle(
                    color: Palette.wine,
                    fontSize: 24,
                    fontFamily: 'Georgia',
                  ),
                ),
                const SizedBox(width: 22),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.$2,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        entry.$3,
                        style: const TextStyle(color: Palette.sage),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 14),
      OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => Onboarding(
              onFinish: () async {
                Navigator.of(context).pop();
              },
            ),
          ),
        ),
        icon: const Icon(Icons.replay_rounded),
        label: const Text('Replay the welcome guide'),
      ),
    ],
  );
}

class JournalArtwork extends StatelessWidget {
  const JournalArtwork({super.key});
  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      Transform.rotate(
        angle: .12,
        child: Container(width: 150, height: 180, color: Palette.sage),
      ),
      Transform.rotate(
        angle: -.12,
        child: Container(
          width: 150,
          height: 180,
          padding: const EdgeInsets.all(10),
          color: Palette.cream,
          child: Column(
            children: [
              Expanded(
                child: Container(
                  color: Palette.ink,
                  child: const Center(
                    child: Icon(
                      Icons.filter_vintage_rounded,
                      color: Palette.cream,
                      size: 62,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'the good little things',
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'Georgia',
                  color: Palette.wine,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
