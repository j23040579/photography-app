import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:photograph/domain/models.dart';
import 'package:photograph/domain/suggestion_engine.dart';

void main() {
  group('offline recommendations', () {
    test('every category has distinct photo compositions with its context', () {
      final engine = SuggestionEngine(seed: 42);
      for (final category in PlaceCategory.values) {
        final prompts = engine.generate(category, count: 12);
        expect(prompts.length, 12);
        expect(prompts.map((p) => p.text).toSet().length, 12);
        expect(
          prompts.every((p) => p.feature.startsWith('${category.name}|')),
          isTrue,
        );
        expect(prompts.every((p) => p.text.isNotEmpty && !p.completed), isTrue);
        expect(prompts.map((p) => p.id).toSet().length, 12);
      }
    });

    test(
      'history prevents repeats and survives a JSON persistence round-trip',
      () {
        final engine = SuggestionEngine(seed: 5);
        final first = engine.generate(PlaceCategory.restaurant, count: 40);
        final saved =
            jsonDecode(jsonEncode(engine.toJson())) as Map<String, dynamic>;
        final restored = SuggestionEngine(state: saved, seed: 6);
        final second = restored.generate(PlaceCategory.restaurant, count: 40);
        expect(
          first
              .map((p) => p.text)
              .toSet()
              .intersection(second.map((p) => p.text).toSet()),
          isEmpty,
        );
        expect(
          first
              .map((p) => p.id)
              .toSet()
              .intersection(second.map((p) => p.id).toSet()),
          isEmpty,
        );
      },
    );

    test('pool exhaustion cycles without duplicates inside a batch', () {
      final engine = SuggestionEngine(seed: 12);
      final pool = engine.generate(
        PlaceCategory.party,
        count: engine.poolSize(PlaceCategory.party),
      );
      expect(pool.length, 128);
      expect(pool.map((p) => p.text).toSet().length, 128);
      final next = engine.generate(PlaceCategory.party, count: 8);
      expect(next.length, 8);
      expect(next.map((p) => p.text).toSet().length, 8);
      expect(
        next.every((p) => pool.any((previous) => previous.text == p.text)),
        isTrue,
      );
    });

    test('explicit exclusions are respected even after history resets', () {
      final engine = SuggestionEngine(seed: 1);
      final all = engine.generate(PlaceCategory.travel, count: 128);
      final excluded = all.map((p) => p.text).toSet();
      final keep = excluded.first;
      excluded.remove(keep);
      final result = engine.generate(
        PlaceCategory.travel,
        count: 5,
        exclude: excluded,
      );
      expect(result.length, 1);
      expect(result.single.text, keep);
      expect(
        engine.generate(PlaceCategory.travel, exclude: {...excluded, keep}),
        isEmpty,
      );
      expect(engine.generate(PlaceCategory.travel, count: 0), isEmpty);
    });

    test(
      'feedback really updates model probabilities and persists learning',
      () {
        final engine = SuggestionEngine(seed: 42);
        final prompt = engine.generate(PlaceCategory.outdoors).first;
        final initial = engine.score(prompt);
        engine.feedback(prompt, true);
        expect(engine.score(prompt), greaterThan(initial));
        final afterLike = engine.score(prompt);
        engine.feedback(prompt, false);
        expect(engine.score(prompt), lessThan(afterLike));
        expect(engine.feedbackCount, 2);
        final restored = SuggestionEngine(
          state:
              jsonDecode(jsonEncode(engine.toJson())) as Map<String, dynamic>,
        );
        expect(restored.score(prompt), closeTo(engine.score(prompt), 1e-12));
        expect(restored.feedbackCount, 2);
        expect((restored.toJson()['weights'] as Map).isNotEmpty, isTrue);
      },
    );

    test('learning generalizes to another prompt sharing subject features', () {
      final engine = SuggestionEngine();
      const liked = PhotoPrompt(
        id: '1',
        text: 'First',
        feature: 'party|people|close',
      );
      const related = PhotoPrompt(
        id: '2',
        text: 'Related',
        feature: 'party|people|wide',
      );
      const unrelated = PhotoPrompt(
        id: '3',
        text: 'Unrelated',
        feature: 'outdoors|nature|wide',
      );
      for (var i = 0; i < 6; i++) {
        engine.feedback(liked, true);
      }
      expect(engine.score(related), greaterThan(engine.score(unrelated)));
    });
  });

  group('album storage model', () {
    test(
      'round-trips all album, photo, video, annotation and reminder fields',
      () {
        final when = DateTime(2026, 10, 25, 18);
        final album = Album(
          id: 'album-1',
          title: 'Dinner together',
          category: PlaceCategory.restaurant,
          eventDate: when,
          createdAt: DateTime(2026, 10, 24),
          prompts: const [
            PhotoPrompt(
              id: 'prompt-1',
              text: 'Our table',
              feature: 'restaurant|people|wide',
              completed: true,
              edited: true,
            ),
          ],
          memories: [
            Memory(
              id: 'photo',
              path: '/data/photo.jpg',
              isVideo: false,
              createdAt: when,
              caption: 'A happy table',
              promptId: 'prompt-1',
            ),
            Memory(
              id: 'video',
              path: '/data/video.mp4',
              isVideo: true,
              createdAt: when,
              caption: 'Cheers',
            ),
          ],
          notes: 'Come back next year',
          rating: 5,
          reminderAt: when.subtract(const Duration(hours: 1)),
        );
        final restored = Album.fromJson(
          jsonDecode(jsonEncode(album.toJson())) as Map<String, dynamic>,
        );
        expect(restored.toJson(), album.toJson());
        expect(restored.memories.last.isVideo, isTrue);
        expect(restored.prompts.single.edited, isTrue);
        expect(restored.copyWith(reminderAt: null).reminderAt, isNull);
        expect(
          restored.copyWith(notes: 'Updated').reminderAt,
          album.reminderAt,
        );
        expect(
          restored.memories.first.copyWith(promptId: null).promptId,
          isNull,
        );
        expect(restored.notes, 'Come back next year');
      },
    );

    test('album lists cannot mutate previously saved state', () {
      final list = <PhotoPrompt>[];
      final album = Album(
        id: '1',
        title: 'Today',
        category: PlaceCategory.everyday,
        eventDate: DateTime(2026),
        createdAt: DateTime(2026),
        prompts: list,
      );
      list.add(const PhotoPrompt(id: 'p', text: 'Photo', feature: 'x'));
      expect(album.prompts, isEmpty);
      expect(() => album.prompts.add(list.first), throwsUnsupportedError);
    });
  });
}
