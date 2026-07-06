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

  testWidgets('question strip shows the question; tapping it offers replies',
      (tester) async {
    final state = await buildState(healthyBackend(heardQuestion: 'Are you hungry?'));
    await state.init();

    await tester.pumpWidget(MaterialApp(home: HomeScreen(state: state)));
    await tester.pumpAndSettle();

    // The restored question is on screen, alongside the Ask button.
    expect(find.text('Are you hungry?'), findsOneWidget);
    expect(find.text('Ask'), findsOneWidget);

    // Tapping the question fills the sentence pane with candidate replies.
    await tester.tap(find.text('Are you hungry?'));
    await tester.pumpAndSettle();
    expect(find.text('Yes, please.'), findsOneWidget);
    expect(find.text('No, thank you.'), findsOneWidget);

    // Dismissing returns the strip to its placeholder without moving anything.
    await tester.tap(find.byTooltip('Dismiss question'));
    await tester.pumpAndSettle();
    expect(find.text('Are you hungry?'), findsNothing);
    expect(find.text('When someone asks a question, it will appear here.'),
        findsOneWidget);
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
