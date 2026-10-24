import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photograph/domain/models.dart';
import 'package:photograph/ui/album_card.dart';
import 'package:photograph/ui/theme.dart';

Album _album({String notes = ''}) => Album(
  id: 'a1',
  title: 'Birthday dinner',
  category: PlaceCategory.restaurant,
  eventDate: DateTime(2026, 10, 24),
  createdAt: DateTime(2026, 10, 1),
  prompts: const [
    PhotoPrompt(id: '1', text: 'The table', feature: '', completed: true),
    PhotoPrompt(id: '2', text: 'The dessert', feature: ''),
  ],
  rating: 4,
  notes: notes,
);

Widget _host(Widget child) => MaterialApp(
  theme: photographTheme(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('card shows title, progress and rating with no photos', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(AlbumCard(album: _album(), photos: const [])),
    );
    expect(find.text('Birthday dinner'), findsOneWidget);
    expect(find.text('RESTAURANT'), findsOneWidget);
    expect(find.text('1 of 2 ideas captured'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(4));
  });

  testWidgets('album note only appears when included', (tester) async {
    final album = _album(notes: 'Best pasta ever');
    await tester.pumpWidget(_host(AlbumCard(album: album, photos: const [])));
    expect(find.text('Best pasta ever'), findsNothing);
    await tester.pumpWidget(
      _host(AlbumCard(album: album, photos: const [], includeNote: true)),
    );
    expect(find.text('Best pasta ever'), findsOneWidget);
  });
}
