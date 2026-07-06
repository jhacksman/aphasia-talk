import 'dart:convert';

import 'package:aphasia_talk/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  ApiService serviceWith(MockClient client) =>
      ApiService(baseUrl: 'http://spark:8080/', client: client);

  test('generate posts word+category and parses the response', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'sentences': [
            {'text': 'I am thirsty.', 'bookmarked': true},
          ],
          'related_words': ['drink'],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final result = await serviceWith(client).generate('water', category: 'Needs');

    // Trailing slash on the base URL must not produce a double slash.
    expect(captured.url.toString(), 'http://spark:8080/generate');
    expect(jsonDecode(captured.body), {'word': 'water', 'category': 'Needs'});
    expect(result.sentences.single.text, 'I am thirsty.');
    expect(result.relatedWords, ['drink']);
  });

  test('non-2xx responses raise ApiException', () async {
    final client = MockClient((request) async => http.Response('boom', 500));
    expect(
      () => serviceWith(client).fetchWords(),
      throwsA(isA<ApiException>()),
    );
  });

  test('malformed JSON raises ApiException, not a raw FormatException', () async {
    final client = MockClient((request) async => http.Response('not json', 200));
    expect(
      () => serviceWith(client).generate('water'),
      throwsA(isA<ApiException>()),
    );
  });

  test('health returns false on any failure instead of throwing', () async {
    final client = MockClient((request) async => http.Response('nope', 503));
    expect(await serviceWith(client).health(), isFalse);
  });

  test('vision uploads multipart image and parses result', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/vision');
      expect(request.headers['content-type'], contains('multipart/form-data'));
      return http.Response(
        jsonEncode({
          'identified_object': 'cup',
          'confidence': 0.9,
          'sentences': [
            {'text': 'I want a drink.', 'bookmarked': false},
          ],
          'related_words': ['water'],
        }),
        200,
      );
    });

    final result = await serviceWith(client).vision([1, 2, 3]);
    expect(result.identifiedObject, 'cup');
    expect(result.sentences.single.text, 'I want a drink.');
  });

  test('ask uploads multipart audio and parses the logged question', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/ask');
      expect(request.headers['content-type'], contains('multipart/form-data'));
      return http.Response(
        jsonEncode({'text': 'Are you hungry?', 'turn_id': 4}),
        200,
      );
    });

    final result = await serviceWith(client).ask([1, 2, 3]);
    expect(result.text, 'Are you hungry?');
    expect(result.turnId, 4);
  });

  test('respond posts the question and parses replies', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'sentences': [
            {'text': 'Yes, please.', 'bookmarked': false},
          ],
          'related_words': ['yes'],
        }),
        200,
      );
    });

    final result = await serviceWith(client).respond('Are you hungry?');
    expect(captured.url.path, '/respond');
    expect(jsonDecode(captured.body), {'question': 'Are you hungry?'});
    expect(result.sentences.single.text, 'Yes, please.');
  });

  test('latestHeardQuestion returns the newest heard turn, skipping spoken', () async {
    final client = MockClient((request) async => http.Response(
          jsonEncode({
            'turns': [
              {'id': 9, 'role': 'spoken', 'text': 'Yes.', 'created_at': 'x'},
              {'id': 8, 'role': 'heard', 'text': 'Are you hungry?', 'created_at': 'x'},
            ],
          }),
          200,
        ));
    expect(await serviceWith(client).latestHeardQuestion(), 'Are you hungry?');
  });

  test('bookmarks CRUD hits the right endpoints', () async {
    final calls = <String>[];
    final client = MockClient((request) async {
      calls.add('${request.method} ${request.url.path}');
      if (request.method == 'POST') {
        return http.Response(
          jsonEncode({
            'id': 7,
            'text': 'I am thirsty.',
            'word': 'water',
            'category': 'Needs',
            'created_at': '2026-01-01T00:00:00Z',
          }),
          200,
        );
      }
      if (request.method == 'DELETE') {
        return http.Response(jsonEncode({'deleted': 7}), 200);
      }
      return http.Response(jsonEncode({'bookmarks': []}), 200);
    });

    final service = serviceWith(client);
    final created = await service.addBookmark('I am thirsty.', 'water', category: 'Needs');
    expect(created.id, 7);
    await service.deleteBookmark(7);
    expect(await service.fetchBookmarks(), isEmpty);
    expect(calls, ['POST /bookmarks', 'DELETE /bookmarks/7', 'GET /bookmarks']);
  });
}
