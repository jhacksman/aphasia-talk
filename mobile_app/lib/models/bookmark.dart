class Bookmark {
  final int id;
  final String text;
  final String word;
  final String? category;
  final String createdAt;

  const Bookmark({
    required this.id,
    required this.text,
    required this.word,
    this.category,
    required this.createdAt,
  });

  factory Bookmark.fromJson(Map<String, dynamic> json) {
    return Bookmark(
      id: json['id'] as int,
      text: json['text'] as String,
      word: json['word'] as String,
      category: json['category'] as String?,
      createdAt: json['created_at'] as String,
    );
  }
}
