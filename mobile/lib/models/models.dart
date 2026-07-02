/// Data models mirroring the backend API schemas (backend/app/schemas.py).
library;

class Word {
  const Word({required this.text, required this.icon, required this.row, required this.col});

  final String text;
  final String icon; // Tabler icon name from the backend, e.g. "ti-droplet".
  final int row;
  final int col;

  factory Word.fromJson(Map<String, dynamic> json) {
    final pos = (json['position'] as List?) ?? const [0, 0];
    return Word(
      text: json['text'] as String,
      icon: (json['icon'] as String?) ?? '',
      row: (pos.isNotEmpty ? pos[0] as num : 0).toInt(),
      col: (pos.length > 1 ? pos[1] as num : 0).toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'icon': icon,
        'position': [row, col],
      };
}

class WordCategory {
  const WordCategory({required this.name, required this.colorHex, required this.words});

  final String name;
  final String colorHex; // e.g. "#4CAF50" (Fitzgerald Key color).
  final List<Word> words;

  factory WordCategory.fromJson(Map<String, dynamic> json) {
    final words = ((json['words'] as List?) ?? const [])
        .map((w) => Word.fromJson(w as Map<String, dynamic>))
        .toList()
      // Stable ordering by grid position — buttons must never move.
      ..sort((a, b) => a.row != b.row ? a.row.compareTo(b.row) : a.col.compareTo(b.col));
    return WordCategory(
      name: json['name'] as String,
      colorHex: (json['color'] as String?) ?? '#1A6FC4',
      words: words,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'color': colorHex,
        'words': words.map((w) => w.toJson()).toList(),
      };
}

class Sentence {
  const Sentence({required this.text, this.bookmarked = false});

  final String text;
  final bool bookmarked;

  Sentence copyWith({bool? bookmarked}) =>
      Sentence(text: text, bookmarked: bookmarked ?? this.bookmarked);

  factory Sentence.fromJson(Map<String, dynamic> json) => Sentence(
        text: json['text'] as String,
        bookmarked: (json['bookmarked'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {'text': text, 'bookmarked': bookmarked};
}

class GenerateResult {
  const GenerateResult({required this.sentences, required this.relatedWords});

  final List<Sentence> sentences;
  final List<String> relatedWords;

  factory GenerateResult.fromJson(Map<String, dynamic> json) => GenerateResult(
        sentences: ((json['sentences'] as List?) ?? const [])
            .map((s) => Sentence.fromJson(s as Map<String, dynamic>))
            .toList(),
        relatedWords: ((json['related_words'] as List?) ?? const [])
            .map((w) => w.toString())
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'sentences': sentences.map((s) => s.toJson()).toList(),
        'related_words': relatedWords,
      };
}

class VisionResult {
  const VisionResult({
    required this.identifiedObject,
    required this.confidence,
    required this.sentences,
    required this.relatedWords,
  });

  final String identifiedObject;
  final double confidence;
  final List<Sentence> sentences;
  final List<String> relatedWords;

  factory VisionResult.fromJson(Map<String, dynamic> json) {
    final gen = GenerateResult.fromJson(json);
    return VisionResult(
      identifiedObject: (json['identified_object'] as String?) ?? 'this',
      confidence: ((json['confidence'] as num?) ?? 0).toDouble(),
      sentences: gen.sentences,
      relatedWords: gen.relatedWords,
    );
  }
}

class Bookmark {
  const Bookmark({required this.id, required this.text, required this.word, this.category});

  final int id;
  final String text;
  final String word;
  final String? category;

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
        id: (json['id'] as num).toInt(),
        text: json['text'] as String,
        word: json['word'] as String,
        category: json['category'] as String?,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'text': text, 'word': word, 'category': category};
}

class Profile {
  const Profile({this.name, this.birthYear, this.region, this.idiolectNotes});

  final String? name;
  final int? birthYear;
  final String? region;
  final String? idiolectNotes;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        name: json['name'] as String?,
        birthYear: (json['birth_year'] as num?)?.toInt(),
        region: json['region'] as String?,
        idiolectNotes: json['idiolect_notes'] as String?,
      );

  /// Only includes the fields being set; the backend merges partial updates
  /// (so we never wipe fields the app doesn't edit, like idiolect_notes).
  Map<String, dynamic> toUpdateJson() => {
        'name': name,
        'birth_year': birthYear,
        'region': region,
      };
}

class TranscribeResult {
  const TranscribeResult({required this.text, required this.confidence});

  final String text;
  final double confidence;

  factory TranscribeResult.fromJson(Map<String, dynamic> json) => TranscribeResult(
        text: (json['text'] as String?) ?? '',
        confidence: ((json['confidence'] as num?) ?? 0).toDouble(),
      );
}
