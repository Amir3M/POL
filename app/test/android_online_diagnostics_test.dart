import 'package:arman_vpn/core/android_online_diagnostics.dart';
import 'package:arman_vpn/ui/android_diagnostics.dart';
import 'package:arman_vpn/ui/android_preview.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _onlineChannel = MethodChannel('pol/online_diagnostics');
const _previewChannel = MethodChannel('pol/preview');

void main() {
  test('accepts only enabled stages and real HTTP status codes', () {
    OnlineDiagnosticsState? parse(Map<String, Object?> overrides) =>
        OnlineDiagnosticsState.tryParse({
          'enabled': true,
          'stage': 'http2',
          'reason': 'request_failed',
          ...overrides,
        });

    expect(parse({'enabled': false}), isNull);
    expect(parse({'stage': 'Unexpected provider message'}), isNull);
    expect(parse({'httpStatus': 401})?.stage, OnlineDiagnosticsStage.http2);
    expect(parse({'httpStatus': 401})?.httpStatus, 401);
    expect(
      parse({'httpStatus': 401})?.reason,
      OnlineDiagnosticsReason.requestFailed,
    );
    for (final status in [99, 600, 401.0, '401', null]) {
      expect(parse({'httpStatus': status})?.httpStatus, isNull);
    }
    expect(parse({'reason': 'Unexpected provider message'})?.reason, isNull);
  });

  test('rejects contradictory or incomplete provider quota', () {
    const finite = {'unlimited': false, 'limit': 1024, 'remaining': 0};
    final unlimited = OnlineDiagnosticsQuota.tryParse({'unlimited': true});
    final exhausted = OnlineDiagnosticsQuota.tryParse(finite);
    expect(unlimited?.unlimited, isTrue);
    expect(exhausted?.unlimited, isFalse);
    expect(exhausted?.remaining, 0);
    expect(
      OnlineDiagnosticsQuota.tryParse({...finite, 'unlimited': true}),
      isNull,
    );
    expect(
      OnlineDiagnosticsQuota.tryParse({...finite, 'remaining': -1}),
      isNull,
    );
    expect(
      OnlineDiagnosticsQuota.tryParse({...finite, 'remaining': 1025}),
      isNull,
    );
    expect(
      OnlineDiagnosticsQuota.tryParse({...finite, 'remaining': null}),
      isNull,
    );
  });

  testWidgets('debug preview shows its local approval status', (tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    var onlineCalls = 0;
    messenger.setMockMethodCallHandler(_onlineChannel, (call) async {
      onlineCalls++;
      return null;
    });
    messenger.setMockMethodCallHandler(_previewChannel, (call) async => null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(_onlineChannel, null);
      messenger.setMockMethodCallHandler(_previewChannel, null);
    });

    await tester.pumpWidget(const AndroidPreviewApp());
    await tester.tap(find.text('Diagnostics'));
    await tester.pumpAndSettle();
    final report = tester.widget<SelectableText>(find.byType(SelectableText));
    if (const bool.fromEnvironment('POL_TUNNEL_TEST')) {
      expect(report.data, isNot(contains('Online stage:')));
    } else {
      expect(report.data, contains('Online stage: Configuration'));
      expect(report.data, contains('Reason: Provider approval required'));
      expect(report.data, contains('HTTP status: Unavailable'));
    }
    expect(onlineCalls, 0);
  });

  testWidgets('online snapshots expose only typed status and quota details', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    String? copied;
    String? exported;
    messenger.setMockMethodCallHandler(_onlineChannel, (call) async {
      expect(call.method, 'state');
      expect(call.arguments, isNull);
      return {
        'enabled': true,
        'stage': 'guardian',
        'httpStatus': 403,
        'reason': 'not_entitled',
        'quota': {'unlimited': false, 'limit': 2048, 'remaining': 1024},
        'rawError': 'PRIVATE marker',
        'providerUrl': 'PRIVATE marker',
        'providerBody': 'PRIVATE marker',
      };
    });
    messenger.setMockMethodCallHandler(_previewChannel, (call) async {
      if (call.method == 'exportDiagnostics') {
        exported = call.arguments['text'] as String;
        return true;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = call.arguments['text'] as String;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_onlineChannel, null);
      messenger.setMockMethodCallHandler(_previewChannel, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      const AndroidPreviewApp(
        home: AndroidDiagnosticsPage(online: AndroidOnlineDiagnostics()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy report'));
    await tester.pumpAndSettle();

    expect(copied, contains('Online stage: Direct Guardian request'));
    expect(copied, contains('HTTP status: 403'));
    expect(copied, contains('Reason: Account lacks VPN entitlement'));
    expect(copied, contains('Provider quota:'));
    expect(copied, contains('1.0 KB'));
    expect(copied, isNot(contains('PRIVATE marker')));

    await tester.tap(find.text('Export report'));
    await tester.pumpAndSettle();
    expect(exported, copied);
  });

  testWidgets('channel errors render unavailable metadata', (tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_onlineChannel, (call) async {
      throw PlatformException(code: 'failed', message: 'PRIVATE marker');
    });
    messenger.setMockMethodCallHandler(_previewChannel, (call) async => null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(_onlineChannel, null);
      messenger.setMockMethodCallHandler(_previewChannel, null);
    });

    await tester.pumpWidget(
      const AndroidPreviewApp(
        home: AndroidDiagnosticsPage(online: AndroidOnlineDiagnostics()),
      ),
    );
    await tester.pumpAndSettle();
    final report = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(report.data, contains('Online stage: Unavailable'));
    expect(report.data, contains('Reason: Unavailable'));
    expect(report.data, contains('Provider quota: Unknown'));
    expect(report.data, isNot(contains('PRIVATE marker')));
  });
}
