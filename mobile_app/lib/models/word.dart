class Word {
  final String text;
  final String icon;
  final List<int> position;

  const Word({required this.text, required this.icon, required this.position});

  factory Word.fromJson(Map<String, dynamic> json) {
    return Word(
      text: json['text'] as String,
      icon: json['icon'] as String,
      position: (json['position'] as List<dynamic>).cast<int>(),
    );
  }
}
