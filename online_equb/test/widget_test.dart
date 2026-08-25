import 'package:flutter_test/flutter_test.dart';
import 'package:equb_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const EqubApp(firebaseReady: false));
    expect(find.byType(EqubApp), findsOneWidget);
  });
}
