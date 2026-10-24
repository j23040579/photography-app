/// The app's portable, offline data model. No platform or UI dependencies.
enum PlaceCategory {
  restaurant('Restaurant'),
  party('Party'),
  travel('Travel'),
  outdoors('Outdoors'),
  everyday('Everyday'),
  celebration('Celebration');

  const PlaceCategory(this.label);
  final String label;

  static PlaceCategory fromName(String? value) => values.firstWhere(
    (category) => category.name == value,
    orElse: () => everyday,
  );
}

const _notProvided = Object();

class PhotoPrompt {
  const PhotoPrompt({
    required this.id,
    required this.text,
    required this.feature,
    this.completed = false,
    this.edited = false,
  });

  final String id;
  final String text;

  /// Model features encoded as category|subject type|composition style.
  final String feature;
  final bool completed;
  final bool edited;

  PhotoPrompt copyWith({
    String? id,
    String? text,
    String? feature,
    bool? completed,
    bool? edited,
  }) => PhotoPrompt(
    id: id ?? this.id,
    text: text ?? this.text,
    feature: feature ?? this.feature,
    completed: completed ?? this.completed,
    edited: edited ?? this.edited,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'feature': feature,
    'completed': completed,
    'edited': edited,
  };

  factory PhotoPrompt.fromJson(Map<String, dynamic> json) => PhotoPrompt(
    id: json['id'] as String,
    text: json['text'] as String,
    feature: json['feature'] as String? ?? '',
    completed: json['completed'] as bool? ?? false,
    edited: json['edited'] as bool? ?? false,
  );
}

class Memory {
  const Memory({
    required this.id,
    required this.path,
    required this.isVideo,
    required this.createdAt,
    this.caption = '',
    this.promptId,
  });

  final String id;

  /// Path of the app-owned local copy, never an upload destination.
  final String path;
  final bool isVideo;
  final DateTime createdAt;
  final String caption;
  final String? promptId;

  Memory copyWith({
    String? id,
    String? path,
    bool? isVideo,
    DateTime? createdAt,
    String? caption,
    Object? promptId = _notProvided,
  }) => Memory(
    id: id ?? this.id,
    path: path ?? this.path,
    isVideo: isVideo ?? this.isVideo,
    createdAt: createdAt ?? this.createdAt,
    caption: caption ?? this.caption,
    promptId: identical(promptId, _notProvided)
        ? this.promptId
        : promptId as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'isVideo': isVideo,
    'createdAt': createdAt.toIso8601String(),
    'caption': caption,
    'promptId': promptId,
  };

  factory Memory.fromJson(Map<String, dynamic> json) => Memory(
    id: json['id'] as String,
    path: json['path'] as String,
    isVideo: json['isVideo'] as bool? ?? false,
    createdAt: DateTime.parse(json['createdAt'] as String),
    caption: json['caption'] as String? ?? '',
    promptId: json['promptId'] as String?,
  );
}

class Album {
  Album({
    required this.id,
    required this.title,
    required this.category,
    required this.eventDate,
    required this.createdAt,
    List<PhotoPrompt> prompts = const [],
    List<Memory> memories = const [],
    this.notes = '',
    this.rating = 0,
    this.reminderAt,
    this.reminderPromptId,
  }) : prompts = List.unmodifiable(prompts),
       memories = List.unmodifiable(memories);

  final String id;
  final String title;
  final PlaceCategory category;
  final DateTime eventDate;
  final DateTime createdAt;
  final List<PhotoPrompt> prompts;
  final List<Memory> memories;
  final String notes;

  /// Zero is unrated; one to five are the user's star rating.
  final int rating;
  final DateTime? reminderAt;
  final String? reminderPromptId;

  Album copyWith({
    String? id,
    String? title,
    PlaceCategory? category,
    DateTime? eventDate,
    DateTime? createdAt,
    List<PhotoPrompt>? prompts,
    List<Memory>? memories,
    String? notes,
    int? rating,
    Object? reminderAt = _notProvided,
    Object? reminderPromptId = _notProvided,
  }) => Album(
    id: id ?? this.id,
    title: title ?? this.title,
    category: category ?? this.category,
    eventDate: eventDate ?? this.eventDate,
    createdAt: createdAt ?? this.createdAt,
    prompts: prompts ?? this.prompts,
    memories: memories ?? this.memories,
    notes: notes ?? this.notes,
    rating: rating ?? this.rating,
    reminderAt: identical(reminderAt, _notProvided)
        ? this.reminderAt
        : reminderAt as DateTime?,
    reminderPromptId: identical(reminderPromptId, _notProvided)
        ? this.reminderPromptId
        : reminderPromptId as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'category': category.name,
    'eventDate': eventDate.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'prompts': prompts.map((prompt) => prompt.toJson()).toList(),
    'memories': memories.map((memory) => memory.toJson()).toList(),
    'notes': notes,
    'rating': rating,
    'reminderAt': reminderAt?.toIso8601String(),
    'reminderPromptId': reminderPromptId,
  };

  factory Album.fromJson(Map<String, dynamic> json) => Album(
    id: json['id'] as String,
    title: json['title'] as String,
    category: PlaceCategory.fromName(json['category'] as String?),
    eventDate: DateTime.parse(json['eventDate'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String),
    prompts: (json['prompts'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              PhotoPrompt.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
    memories: (json['memories'] as List<dynamic>? ?? [])
        .map((item) => Memory.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(),
    notes: json['notes'] as String? ?? '',
    rating: (json['rating'] as num? ?? 0).toInt().clamp(0, 5).toInt(),
    reminderPromptId: json['reminderPromptId'] as String?,
    reminderAt: json['reminderAt'] == null
        ? null
        : DateTime.parse(json['reminderAt'] as String),
  );
}
