import 'package:flutter_test/flutter_test.dart';
import 'package:mongol_notebook/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MongolNotebookApp());

    // Verify that the home screen title is present
    expect(find.text('ᠮᠣᠩᠭᠣᠯ ᠲᠡᠮᠳᠡᠭᠯᠡᠯ'), findsOneWidget);
  });
}
