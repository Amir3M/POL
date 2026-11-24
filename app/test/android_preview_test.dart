import 'package:arman_vpn/app_info.dart';
import 'package:arman_vpn/ui/android_preview.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _previewChannel = MethodChannel('pol/preview');
const _buildId = String.fromEnvironment('POL_BUILD_ID', defaultValue: 'local');

void main() {
  testWidgets('preview exposes only offline status and attribution', (
    tester,
  ) async {
    await tester.pumpWidget(const AndroidPreviewApp());

    expect(find.text('POL VPN'), findsOneWidget);
    expect(find.text('VPN access unavailable'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextButton), findsNWidgets(2));

    await tester.tap(find.text('About POL VPN'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Licensed under GPL-3.0.'), findsOneWidget);
    expect(find.text('Open-source licenses'), findsOneWidget);
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

  testWidgets('diagnostics copy and export the same offline report', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    String? copied;
    String? exported;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(_previewChannel, (call) async {
      switch (call.method) {
        case 'deviceInfo':
          return {
            'androidVersion': '15',
            'sdk': 35,
            'architecture': 'arm64-v8a',
            'unexpectedField': 'Private value outside the report schema',
          };
        case 'exportDiagnostics':
          exported = (call.arguments as Map)['text'] as String;
          return true;
        default:
          throw MissingPluginException();
      }
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_previewChannel, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(const AndroidPreviewApp());
    await tester.tap(find.text('Diagnostics'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Copy report'));
    await tester.pumpAndSettle();
    expect(copied, contains('App version: $appVersion\nBuild: $_buildId'));
    expect(copied, contains('Android version: 15\nAndroid SDK: 35'));
    expect(copied, contains('Architecture: arm64-v8a'));
    expect(copied, contains('VPN connection: Unavailable'));
    expect(copied, contains('Authentication: Unavailable'));
    expect(copied, contains('Quota: Unavailable'));
    expect(copied, isNot(contains('Private value')));
    expect(find.text('Diagnostics copied.'), findsOneWidget);

    await tester.tap(find.text('Export report'));
    await tester.pumpAndSettle();
    expect(exported, copied);
    expect(find.text('Diagnostics saved.'), findsOneWidget);
  });

  testWidgets('diagnostics omit unsupported details and handle export cancel', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    var failExport = false;
    messenger.setMockMethodCallHandler(_previewChannel, (call) async {
      return switch (call.method) {
        'deviceInfo' => {
          'androidVersion': 'Unexpected model label',
          'sdk': -1,
          'architecture': 'Unexpected serial number',
        },
        'exportDiagnostics' when failExport => throw PlatformException(
          code: 'test_failure',
          message: 'Private provider failure details',
        ),
        'exportDiagnostics' => false,
        _ => throw MissingPluginException(),
      };
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(_previewChannel, null),
    );

    await tester.pumpWidget(const AndroidPreviewApp());
    await tester.tap(find.text('Diagnostics'));
    await tester.pumpAndSettle();

    final report = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(report.data, contains('Android version: Unavailable'));
    expect(report.data, contains('Android SDK: Unavailable'));
    expect(report.data, contains('Architecture: Unavailable'));
    expect(report.data, isNot(contains('Unexpected')));

    await tester.tap(find.text('Export report'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Export report'),
          )
          .onPressed,
      isNotNull,
    );

    failExport = true;
    await tester.tap(find.text('Export report'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save diagnostics.'), findsOneWidget);
    expect(find.text('Private provider failure details'), findsNothing);
  });
}
