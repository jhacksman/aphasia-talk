class Sentence {
  final String text;
  bool bookmarked;

  Sentence({required this.text, this.bookmarked = false});

  factory Sentence.fromJson(Map<String, dynamic> json) {
    return Sentence(
      text: json['text'] as String,
      bookmarked: json['bookmarked'] as bool? ?? false,
    );
  }
}
