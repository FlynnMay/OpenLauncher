import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/features/components/marquee.dart';
import 'package:openlauncher/features/modules/text_drawer.dart';

void main() {
  const long = 'A very long line of text that will not fit in the box';

  /// The text as a row or column gives it room: its natural size, in a width.
  Future<void> inLine(
    WidgetTester tester,
    Map<String, Object?> options, {
    double? height,
  }) => tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            height: height,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextVisual(
                  shrink: true,
                  values: {
                    'text': long,
                    'style': {'fontSize': 20},
                    ...options,
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Text text(WidgetTester tester) => tester.widget<Text>(find.text(long).first);

  testWidgets('at its natural size, text fades unless told otherwise', (
    tester,
  ) async {
    await inLine(tester, {});
    expect(text(tester).overflow, TextOverflow.fade);
    expect(text(tester).maxLines, 1);

    await inLine(tester, {'overflow': 'ellipsis'});
    expect(text(tester).overflow, TextOverflow.ellipsis);

    await inLine(tester, {'overflow': 'clip'});
    expect(text(tester).overflow, TextOverflow.clip);
    expect(text(tester).softWrap, isFalse);
  });

  testWidgets('at its natural size, text can wrap onto more lines', (
    tester,
  ) async {
    await inLine(tester, {'overflow': 'wrap'});
    expect(text(tester).maxLines, isNull);
    // Several lines tall, not one.
    expect(tester.getSize(find.text(long)).height, greaterThan(40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('at its natural size, wrapping stops where the height does', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            // Tight, as a flex child's room is.
            child: SizedBox(
              width: 200,
              height: 60,
              child: TextVisual(
                shrink: true,
                values: const {
                  'text': long,
                  'overflow': 'wrap',
                  'style': {'fontSize': 20},
                },
              ),
            ),
          ),
        ),
      ),
    );
    expect(text(tester).maxLines, 2);
    expect(text(tester).overflow, TextOverflow.ellipsis);
  });

  testWidgets('at its natural size, text can move along', (tester) async {
    await inLine(tester, {'overflow': 'scroll'});
    await tester.pump();
    expect(find.byType(Marquee), findsOneWidget);
    // Twice, so that its start follows its end round.
    expect(find.text(long), findsNWidgets(2));
    final before = tester.getTopLeft(find.text(long).first).dx;
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getTopLeft(find.text(long).first).dx, before - 40);
  });
}
