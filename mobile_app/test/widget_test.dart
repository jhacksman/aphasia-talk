import 'package:flutter_test/flutter_test.dart';

import 'package:aphasia_talk/models/word.dart';
import 'package:aphasia_talk/models/category.dart';
import 'package:aphasia_talk/models/sentence.dart';
import 'package:aphasia_talk/models/bookmark.dart';

void main() {
  group('Word', () {
    test('fromJson parses correctly', () {
      final w = Word.fromJson({
        'text': 'water',
        'icon': 'ti-droplet',
        'position': [0, 0],
      });
      expect(w.text, 'water');
      expect(w.icon, 'ti-droplet');
      expect(w.position, [0, 0]);
    });
  });

  group('Category', () {
    test('fromJson parses with words', () {
      final c = Category.fromJson({
        'name': 'Needs',
        'color': '#4CAF50',
        'words': [
          {'text': 'water', 'icon': 'ti-droplet', 'position': [0, 0]},
          {'text': 'food', 'icon': 'ti-soup', 'position': [0, 1]},
        ],
      });
      expect(c.name, 'Needs');
      expect(c.words.length, 2);
      expect(c.words[0].text, 'water');
    });
  });

  group('Sentence', () {
    test('fromJson defaults bookmarked to false', () {
      final s = Sentence.fromJson({'text': 'I am thirsty.'});
      expect(s.text, 'I am thirsty.');
      expect(s.bookmarked, false);
    });

    test('fromJson reads bookmarked flag', () {
      final s = Sentence.fromJson({'text': 'I am thirsty.', 'bookmarked': true});
      expect(s.bookmarked, true);
    });
  });

  group('Bookmark', () {
    test('fromJson parses all fields', () {
      final b = Bookmark.fromJson({
        'id': 1,
        'text': 'I am thirsty.',
        'word': 'water',
        'category': 'Needs',
        'created_at': '2026-06-15T10:30:00Z',
      });
      expect(b.id, 1);
      expect(b.text, 'I am thirsty.');
      expect(b.word, 'water');
      expect(b.category, 'Needs');
    });
  });
}
