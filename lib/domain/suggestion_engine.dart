import 'dart:math';

import 'models.dart';

/// A small, inspectable on-device recommendation model.
///
/// Category-specific subjects and composition cues supply the actual words.
/// Online logistic regression learns preferences from thumbs-up/down feedback;
/// an exploration term keeps recommendations varied. This is not a language
/// model, does not inspect images and never sends data to a server. Persist
/// [toJson] after generation or feedback to retain learning and novelty history.
class SuggestionEngine {
  SuggestionEngine({Map<String, dynamic>? state, int? seed})
    : _random = Random(seed) {
    final weights = state?['weights'];
    if (weights is Map) {
      for (final entry in weights.entries) {
        if (entry.key is String && entry.value is num) {
          final value = (entry.value as num).toDouble();
          if (value.isFinite) _weights[entry.key as String] = value;
        }
      }
    }
    final seen = state?['seen'];
    if (seen is Map) {
      for (final category in PlaceCategory.values) {
        final values = seen[category.name];
        if (values is List) {
          _seen[category.name] = values.whereType<String>().toSet();
        }
      }
    }
    _serial = (state?['serial'] as num?)?.toInt() ?? 0;
    _feedbackCount = (state?['feedbackCount'] as num?)?.toInt() ?? 0;
  }

  final Random _random;
  final Map<String, double> _weights = {};
  final Map<String, Set<String>> _seen = {};
  int _serial = 0;
  int _feedbackCount = 0;

  int get feedbackCount => _feedbackCount;

  /// Number of distinct curated compositions available for this category.
  int poolSize(PlaceCategory category) =>
      _subjects[category]!.length * _styles.length;

  /// Suggests photo prompts, avoiding past suggestions until a category's pool
  /// is exhausted. A new cycle then starts. [exclude] is always respected (for
  /// example, pass all current album prompt texts when replacing a prompt).
  /// A single batch never contains duplicate text, including across cycles.
  List<PhotoPrompt> generate(
    PlaceCategory category, {
    int count = 5,
    Set<String> exclude = const {},
  }) {
    if (count <= 0) return [];
    final pool = _pool(category);
    final history = _seen.putIfAbsent(category.name, () => <String>{});
    final selected = <PhotoPrompt>[];
    final batchTexts = <String>{...exclude};

    while (selected.length < count) {
      var candidates = pool
          .where(
            (candidate) =>
                !history.contains(candidate.text) &&
                !batchTexts.contains(candidate.text),
          )
          .toList();
      if (candidates.isEmpty) {
        // History is the only restriction that may reset. Existing album text
        // and this batch stay excluded, so the UI never gets duplicates.
        candidates = pool
            .where((candidate) => !batchTexts.contains(candidate.text))
            .toList();
        if (candidates.isEmpty) break;
        history.clear();
      }

      // Sampling via Gumbel noise balances learned preference and exploration.
      // We score once per candidate; a random comparator would violate sort's
      // contract and make rankings unreliable.
      PhotoPrompt? best;
      var bestScore = -double.infinity;
      for (final candidate in candidates) {
        final probability = score(candidate);
        final logit = log(probability / (1 - probability));
        final uniform = _random.nextDouble().clamp(0.000001, 0.999999);
        final exploration = -log(-log(uniform));
        final rank = logit + 0.85 * exploration;
        if (rank > bestScore) {
          bestScore = rank;
          best = candidate;
        }
      }
      final chosen = best!.copyWith(id: '${category.name}_${++_serial}');
      selected.add(chosen);
      history.add(chosen.text);
      batchTexts.add(chosen.text);
    }
    return selected;
  }

  /// Estimated preference probability, initially 0.5 for every prompt.
  double score(PhotoPrompt prompt) {
    final logit = _features(
      prompt,
    ).fold<double>(0, (total, feature) => total + (_weights[feature] ?? 0));
    return (1 / (1 + exp(-logit.clamp(-12, 12))))
        .clamp(0.000001, 0.999999)
        .toDouble();
  }

  /// One stochastic gradient descent update on binary cross-entropy.
  /// Related compositions share feature weights and benefit from each example.
  void feedback(PhotoPrompt prompt, bool liked) {
    final error = (liked ? 1.0 : 0.0) - score(prompt);
    const learningRate = 0.25;
    const regularization = 0.005;
    for (final feature in _features(prompt)) {
      final old = _weights[feature] ?? 0;
      _weights[feature] = (old + learningRate * (error - regularization * old))
          .clamp(-4, 4)
          .toDouble();
    }
    _feedbackCount++;
  }

  List<String> _features(PhotoPrompt prompt) {
    final parts = prompt.feature.split('|');
    if (parts.length != 3) return ['bias'];
    return [
      'bias',
      'category:${parts[0]}',
      'subject:${parts[1]}',
      'style:${parts[2]}',
      'context:${parts[0]}:${parts[1]}',
    ];
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'weights': Map<String, double>.from(_weights),
    'seen': _seen.map((key, value) => MapEntry(key, value.toList())),
    'serial': _serial,
    'feedbackCount': _feedbackCount,
  };

  List<PhotoPrompt> _pool(PlaceCategory category) => [
    for (final subject in _subjects[category]!)
      for (final style in _styles)
        PhotoPrompt(
          id: '',
          text: '${subject.text} ${style.text}',
          feature: '${category.name}|${subject.kind}|${style.kind}',
        ),
  ];
}

class _Subject {
  const _Subject(this.kind, this.text);
  final String kind;
  final String text;
}

class _Style {
  const _Style(this.kind, this.text);
  final String kind;
  final String text;
}

const _styles = [
  _Style('close', 'Move in close and let one small detail fill the frame.'),
  _Style('wide', 'Step back and include the surroundings to tell the story.'),
  _Style('light', 'Find soft natural light and notice where the shadows fall.'),
  _Style('angle', 'Try a low viewpoint for a fresh perspective.'),
  _Style('color', 'Make one color the main character of your photo.'),
  _Style(
    'candid',
    'Wait for an unposed moment instead of arranging the scene.',
  ),
  _Style('frame', 'Use a doorway, window or nearby shape to frame the scene.'),
  _Style('story', 'Include a little detail that will help you remember today.'),
];

const _subjects = <PlaceCategory, List<_Subject>>{
  PlaceCategory.restaurant: [
    _Subject(
      'food',
      'Photograph the first dish that arrives at your restaurant table.',
    ),
    _Subject(
      'food',
      'Capture the dessert you would order at this restaurant again.',
    ),
    _Subject(
      'food',
      'Photograph an ingredient or garnish that makes your meal special.',
    ),
    _Subject(
      'details',
      'Take a photo of the restaurant menu beside your chosen dish.',
    ),
    _Subject('place', 'Capture the restaurant entrance before you sit down.'),
    _Subject(
      'details',
      'Photograph the restaurant table setting before the meal begins.',
    ),
    _Subject(
      'people',
      'Ask your dining companion for a photo with their favorite dish.',
    ),
    _Subject(
      'people',
      'Take a group photo of everyone sharing your restaurant table.',
    ),
    _Subject('movement', 'Photograph a drink being poured at your table.'),
    _Subject(
      'details',
      'Capture the restaurant decoration that catches your eye first.',
    ),
    _Subject('food', 'Take a before-the-first-bite photo of your meal.'),
    _Subject(
      'story',
      'Photograph the empty plates that tell the story of a good meal.',
    ),
    _Subject('place', 'Capture the view from your seat in the restaurant.'),
    _Subject(
      'details',
      'Photograph the cafe cup or glass you keep reaching for.',
    ),
    _Subject(
      'people',
      'With permission, capture someone at your table enjoying a laugh.',
    ),
    _Subject(
      'story',
      'Photograph one restaurant detail you want to remember a year from now.',
    ),
  ],
  PlaceCategory.party: [
    _Subject(
      'people',
      'Take a party photo with three friends, or everyone in your group.',
    ),
    _Subject(
      'people',
      'Ask someone you just met at the party for a photo together.',
    ),
    _Subject(
      'people',
      'Photograph the party host with their favorite decoration.',
    ),
    _Subject(
      'details',
      'Capture the most colorful detail in the party decorations.',
    ),
    _Subject(
      'movement',
      'Photograph a dance move that sums up the party mood.',
    ),
    _Subject(
      'food',
      'Take a photo of the party snack everyone keeps choosing.',
    ),
    _Subject(
      'people',
      'Capture a group of friends recreating an old party pose.',
    ),
    _Subject(
      'details',
      'Photograph your favorite party outfit detail, with permission.',
    ),
    _Subject('story', 'Capture the party setup before the guests arrive.'),
    _Subject('movement', 'Photograph a toast with the party gathered around.'),
    _Subject('people', 'Ask a friend to take a party photo of you laughing.'),
    _Subject('place', 'Take a photo that shows the whole party space.'),
    _Subject('details', 'Photograph the party playlist or music setup.'),
    _Subject(
      'people',
      'Take a party photo with the friend you have known longest.',
    ),
    _Subject(
      'story',
      'Capture one little party moment you would otherwise forget.',
    ),
    _Subject('food', 'Photograph a drink beside the party decorations.'),
  ],
  PlaceCategory.travel: [
    _Subject(
      'place',
      'Photograph the first sign that tells you you have arrived somewhere new.',
    ),
    _Subject(
      'place',
      'Capture a street on your journey that you want to walk down again.',
    ),
    _Subject(
      'details',
      'Photograph your travel ticket beside something from the destination; hide personal details.',
    ),
    _Subject('food', 'Take a photo of a local meal you tried on this trip.'),
    _Subject(
      'people',
      'Take a travel photo of your companions exploring together.',
    ),
    _Subject('place', 'Capture the view from your accommodation on this trip.'),
    _Subject(
      'details',
      'Photograph a texture or pattern that feels unique to this destination.',
    ),
    _Subject(
      'movement',
      'Capture a train, bus or boat that is part of your journey.',
    ),
    _Subject(
      'story',
      'Photograph the souvenir that tells the best story from your trip.',
    ),
    _Subject(
      'place',
      'Capture a quiet corner away from the busiest travel spot.',
    ),
    _Subject(
      'details',
      'Photograph your packed bag before the next part of your journey.',
    ),
    _Subject(
      'people',
      'Ask your travel companion for a photo of you at your favorite stop.',
    ),
    _Subject('place', 'Photograph the destination skyline or horizon.'),
    _Subject(
      'food',
      'Capture a market stall or shopfront during your travels, with permission.',
    ),
    _Subject(
      'story',
      'Take a photo of a small discovery that was not on your itinerary.',
    ),
    _Subject(
      'movement',
      'Photograph the journey from a safe, stationary viewpoint.',
    ),
  ],
  PlaceCategory.outdoors: [
    _Subject(
      'nature',
      'Photograph a leaf with a shape you have not noticed before.',
    ),
    _Subject('place', 'Capture the outdoor path stretching ahead of you.'),
    _Subject('nature', 'Take a photo of the sky above your outdoor adventure.'),
    _Subject(
      'details',
      'Photograph a tiny natural texture on bark, stone or sand.',
    ),
    _Subject(
      'people',
      'Capture your outdoor companions taking a well-earned break.',
    ),
    _Subject('nature', 'Photograph a reflection in a puddle, pond or stream.'),
    _Subject('movement', 'Capture leaves or grasses moving in the breeze.'),
    _Subject(
      'place',
      'Take a photo from your favorite viewpoint on this walk.',
    ),
    _Subject(
      'details',
      'Photograph the footprints or trail marks on your outdoor route.',
    ),
    _Subject(
      'nature',
      'Capture a flower or plant without picking or disturbing it.',
    ),
    _Subject('people', 'Take a photo of your group enjoying the open air.'),
    _Subject(
      'story',
      'Photograph a spot where you paused to enjoy the outdoors.',
    ),
    _Subject('nature', 'Capture sunlight passing through the trees.'),
    _Subject(
      'place',
      'Photograph the boundary between the outdoors and the city.',
    ),
    _Subject(
      'details',
      'Take a photo of the outdoor gear that made today possible.',
    ),
    _Subject(
      'story',
      'Capture one natural detail you might walk past tomorrow.',
    ),
  ],
  PlaceCategory.everyday: [
    _Subject(
      'food',
      'Photograph the breakfast that started your ordinary day.',
    ),
    _Subject(
      'details',
      'Capture an everyday object that you use more than you notice.',
    ),
    _Subject('place', 'Take a photo of your favorite quiet corner at home.'),
    _Subject(
      'people',
      'With permission, photograph someone who made your day better.',
    ),
    _Subject('story', 'Photograph a small thing you finished today.'),
    _Subject(
      'details',
      'Capture your current book, sketch or other everyday project.',
    ),
    _Subject('nature', 'Photograph the view outside your window today.'),
    _Subject(
      'food',
      'Take a photo of your everyday coffee, tea or favorite drink.',
    ),
    _Subject('movement', 'Capture a small moment in your daily routine.'),
    _Subject(
      'story',
      'Photograph something that made you smile on an ordinary day.',
    ),
    _Subject('place', 'Capture a familiar street as you see it today.'),
    _Subject(
      'details',
      'Photograph the item you would put in a time capsule of today.',
    ),
    _Subject(
      'people',
      'Take a relaxed everyday photo with someone you care about.',
    ),
    _Subject(
      'nature',
      'Capture the light falling into your room at this time of day.',
    ),
    _Subject(
      'story',
      'Photograph a small mess that tells an honest story of your day.',
    ),
    _Subject(
      'details',
      'Capture the little detail that makes your space feel like yours.',
    ),
  ],
  PlaceCategory.celebration: [
    _Subject(
      'people',
      'Photograph the person at the heart of today\'s celebration.',
    ),
    _Subject(
      'details',
      'Capture a handmade detail in the celebration decorations.',
    ),
    _Subject(
      'food',
      'Take a photo of the celebration cake before it is served.',
    ),
    _Subject(
      'people',
      'Gather different generations for a celebration photo together.',
    ),
    _Subject('movement', 'Capture a round of applause during the celebration.'),
    _Subject(
      'story',
      'Photograph a gift or message that has special meaning today.',
    ),
    _Subject(
      'place',
      'Take a photo of the celebration space before everyone arrives.',
    ),
    _Subject(
      'people',
      'Capture a hug between two people celebrating together, with permission.',
    ),
    _Subject(
      'details',
      'Photograph the invitation or place card from this celebration.',
    ),
    _Subject(
      'food',
      'Capture a family recipe or special dish served for the occasion.',
    ),
    _Subject(
      'movement',
      'Photograph the moment the celebration candles are lit.',
    ),
    _Subject(
      'story',
      'Take a photo that shows what makes this milestone personal.',
    ),
    _Subject(
      'people',
      'Photograph the people who helped make this celebration happen.',
    ),
    _Subject(
      'details',
      'Capture the celebration flowers or table centerpiece.',
    ),
    _Subject('place', 'Photograph the view from the celebration table.'),
    _Subject(
      'story',
      'Capture the happy aftermath when the celebration winds down.',
    ),
  ],
};
