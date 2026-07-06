import 'package:aphasia_talk/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WordCategory', () {
    test('parses and sorts words by stable [row, col] position', () {
      final category = WordCategory.fromJson({
        'name': 'Needs',
        'color': '#4CAF50',
        'words': [
          {'text': 'help', 'icon': 'ti-help', 'position': [1, 2]},
          {'text': 'water', 'icon': 'ti-droplet', 'position': [0, 0]},
          {'text': 'food', 'icon': 'ti-soup', 'position': [0, 1]},
        ],
      });
      expect(category.words.map((w) => w.text).toList(), ['water', 'food', 'help']);
    });

    test('round-trips through toJson for the offline cache', () {
      final original = WordCategory.fromJson({
        'name': 'People',
        'color': '#F5D63D',
        'words': [
          {'text': 'I', 'icon': 'ti-user', 'position': [0, 0]},
        ],
      });
      final restored = WordCategory.fromJson(original.toJson());
      expect(restored.name, 'People');
      expect(restored.colorHex, '#F5D63D');
      expect(restored.words.single.text, 'I');
      expect(restored.words.single.row, 0);
    });
  });

  group('GenerateResult', () {
    test('parses sentences with bookmark flags and related words', () {
      final result = GenerateResult.fromJson({
        'sentences': [
          {'text': 'I am thirsty.', 'bookmarked': true},
          {'text': 'Can I have water?', 'bookmarked': false},
        ],
        'related_words': ['drink', 'cup'],
      });
      expect(result.sentences.first.bookmarked, isTrue);
      expect(result.sentences.last.bookmarked, isFalse);
      expect(result.relatedWords, ['drink', 'cup']);
    });

    test('tolerates missing fields', () {
      final result = GenerateResult.fromJson(const {});
      expect(result.sentences, isEmpty);
      expect(result.relatedWords, isEmpty);
    });
  });

  group('VisionResult', () {
    test('parses identified object and confidence', () {
      final result = VisionResult.fromJson({
        'identified_object': 'cup',
        'confidence': 0.94,
        'sentences': [
          {'text': 'I would like a drink.', 'bookmarked': false},
        ],
        'related_words': ['water'],
      });
      expect(result.identifiedObject, 'cup');
      expect(result.confidence, closeTo(0.94, 1e-9));
      expect(result.sentences, hasLength(1));
    });

    test('empty identified_object falls back to "this" (bookmark min_length)', () {
      final result = VisionResult.fromJson({
        'identified_object': '  ',
        'confidence': 0.5,
        'sentences': const [],
        'related_words': const [],
      });
      expect(result.identifiedObject, 'this');
    });
  });

  group('Profile', () {
    test('update payload only carries app-editable fields', () {
      const profile = Profile(
          name: 'Margaret', birthYear: 1948, region: 'uk', pronouns: 'she/her');
      final json = profile.toUpdateJson();
      expect(json, {
        'name': 'Margaret',
        'birth_year': 1948,
        'region': 'uk',
        'pronouns': 'she/her',
      });
      // idiolect_notes intentionally absent so the backend's partial merge
      // never wipes it.
      expect(json.containsKey('idiolect_notes'), isFalse);
    });
  });
}
