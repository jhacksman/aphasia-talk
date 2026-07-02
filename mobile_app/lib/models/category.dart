import 'word.dart';

class Category {
  final String name;
  final String color;
  final List<Word> words;

  const Category({
    required this.name,
    required this.color,
    required this.words,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      name: json['name'] as String,
      color: json['color'] as String,
      words: (json['words'] as List<dynamic>)
          .map((w) => Word.fromJson(w as Map<String, dynamic>))
          .toList(),
    );
  }
}
