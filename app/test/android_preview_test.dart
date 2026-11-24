import 'package:arman_vpn/ui/android_preview.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('preview exposes only offline status and attribution', (
    tester,
  ) async {
    await tester.pumpWidget(const AndroidPreviewApp());

    expect(find.text('POL VPN'), findsOneWidget);
    expect(find.text('VPN access unavailable'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextButton), findsOneWidget);

    await tester.tap(find.text('About POL VPN'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Licensed under GPL-3.0.'), findsOneWidget);
    expect(
      find.widgetWithText(
        SelectableText,
        'https://github.com/armanlife/arman-vpn-client',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });
}
