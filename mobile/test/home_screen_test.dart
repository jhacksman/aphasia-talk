import 'package:aphasia_talk/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_state_test.dart' show buildState, healthyBackend;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tap word -> sentences appear -> tap sentence -> output bar updates',
      (tester) async {
    final state = await buildState(healthyBackend());
    await state.init();

    await tester.pumpWidget(MaterialApp(home: HomeScreen(state: state)));
    await tester.pumpAndSettle();

    // The word grid shows the seeded word.
    expect(find.text('water'), findsOneWidget);
    expect(find.text('Tap a word, then a sentence below…'), findsOneWidget);

    // Tap the word; the generated sentence appears in the right pane.
    await tester.tap(find.text('water'));
    await tester.pumpAndSettle();
    expect(find.text('I am thirsty.'), findsOneWidget);
    expect(find.text('drink'), findsOneWidget); // related-word chip

    // Tap the sentence; it lands in the output bar (now present twice).
    await tester.tap(find.text('I am thirsty.'));
    await tester.pumpAndSettle();
    expect(find.text('I am thirsty.'), findsNWidgets(2));
    expect(find.text('Speak'), findsOneWidget);
  });

  testWidgets('word tiles meet the minimum touch-target size', (tester) async {
    final state = await buildState(healthyBackend());
    await state.init();

    await tester.pumpWidget(MaterialApp(home: HomeScreen(state: state)));
    await tester.pumpAndSettle();

    final tile = tester.getSize(
      find.ancestor(of: find.text('water'), matching: find.byType(Material)).first,
    );
    expect(tile.height, greaterThanOrEqualTo(64));
    expect(tile.width, greaterThanOrEqualTo(64));
  });
}
