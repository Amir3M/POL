import 'dart:convert';

import 'package:arman_vpn/core/android_tunnel_fixture.dart';
import 'package:arman_vpn/ui/android_diagnostics.dart';
import 'package:arman_vpn/ui/android_preview.dart';
import 'package:arman_vpn/ui/android_tunnel_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _fixture = AndroidTunnelFixture();
const _fixtureChannel = MethodChannel('pol/tunnel_fixture');
const _androidChannel = MethodChannel('app/android');

void main() {
  test('test status requires real transfer counters and valid quota', () {
    final pending = TunnelFixtureState.fromMap({
      'sessionReady': true,
      'requests': 1,
      'bytesDown': 65536,
      'bytesUp': 0,
      'quotaLimit': 1048576,
      'quotaRemaining': 'Secret marker outside the report schema',
    });
    expect(pending.transferLabel, 'Traffic received');
    expect(pending.quotaLabel, 'Unknown');

    final complete = TunnelFixtureState.fromMap({
      'sessionReady': true,
      'requests': 2,
      'bytesDown': 65536,
      'bytesUp': 4096,
      'quotaLimit': 1048576,
      'quotaRemaining': 0,
    });
    expect(complete.transferVerified, isTrue);
    expect(complete.quotaLabel, 'Exhausted');
  });

  testWidgets('fixture requires native agreement to enable', (tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    Object? response = {'enabled': false};
    messenger.setMockMethodCallHandler(_fixtureChannel, (call) async {
      expect(call.method, 'state');
      return response;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(_fixtureChannel, null),
    );
    expect(await _fixture.isEnabled(), isFalse);
    response = {'enabled': true};
    expect(await _fixture.isEnabled(), isTrue);
    response = {'enabled': 'true'};
    expect(await _fixture.isEnabled(), isFalse);
  });

  testWidgets('fixture uses Android power and waits for browser transfers', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final messenger = tester.binding.defaultBinaryMessenger;
    final state = <String, Object?>{'enabled': true};
    final powerCalls = <bool>[];
    var opens = 0;
    String? clipboard;
    messenger.setMockMethodCallHandler(_fixtureChannel, (call) async {
      switch (call.method) {
        case 'state':
          return state;
        case 'signIn':
          state['sessionReady'] = true;
          return true;
        case 'renewSession':
          expect(state['connected'], isTrue);
          state.addAll({'sessionRenewed': true, 'quotaRemaining': 262144});
          return true;
        case 'openProbe':
          expect(call.arguments, isNull);
          opens++;
          return true;
        case 'signOut':
          state
            ..clear()
            ..['enabled'] = true;
          return true;
        default:
          throw MissingPluginException();
      }
    });
    messenger.setMockMethodCallHandler(_androidChannel, (call) async {
      expect(call.method, 'setOn');
      final on = call.arguments['on'] as bool;
      powerCalls.add(on);
      state.addAll({
        'proxyAuthorized': on,
        'vpnEstablished': on,
        'connected': on,
        if (on) 'quotaLimit': 1048576,
        if (on) 'quotaRemaining': 524288,
      });
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = call.arguments['text'] as String;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_fixtureChannel, null);
      messenger.setMockMethodCallHandler(_androidChannel, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      const AndroidPreviewApp(home: AndroidTunnelTestPage(fixture: _fixture)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Test session · Signed out'), findsOneWidget);
    expect(find.text('Connect'), findsNothing);

    await tester.tap(find.text('Start test session'));
    await tester.pumpAndSettle();
    expect(find.text('Test session · Ready'), findsOneWidget);
    expect(find.text('Test quota · Unknown'), findsOneWidget);
    expect(find.text('Renew test session'), findsNothing);

    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(powerCalls, [true]);
    expect(find.text('Proxy authorization · Authorized'), findsOneWidget);
    expect(find.text('Android VPN · Connected'), findsOneWidget);
    expect(
      find.text('Test transfer · Awaiting browser traffic'),
      findsOneWidget,
    );
    expect(find.textContaining('512 KB'), findsOneWidget);

    await tester.tap(find.text('Renew test session'));
    await tester.pumpAndSettle();
    expect(find.text('Test session · Renewed'), findsOneWidget);
    expect(find.textContaining('256 KB'), findsOneWidget);
    expect(powerCalls, [true]);

    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      'http://192.0.2.1:8080/',
    );

    await tester.tap(find.text('Open test page'));
    await tester.pumpAndSettle();
    expect(opens, 1);
    await tester.tap(find.text('Copy address'));
    await tester.pumpAndSettle();
    expect(clipboard, tunnelFixtureUrl);

    state.addAll({'requests': 1, 'bytesDown': 65536, 'bytesUp': 0});
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Test transfer · Traffic received'), findsOneWidget);

    state.addAll({'requests': 2, 'bytesUp': 4096});
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(
      find.text('Test transfer · Upload and download verified'),
      findsOneWidget,
    );

    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(powerCalls, [true, false]);
    expect(find.text('Android VPN · Disconnected'), findsOneWidget);

    await tester.tap(find.text('End test session'));
    await tester.pumpAndSettle();
    expect(find.text('Test session · Signed out'), findsOneWidget);
    expect(find.text('Test quota · Unavailable'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('denied consent and fixture diagnostics use safe fields', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final messenger = tester.binding.defaultBinaryMessenger;
    String? clipboard;
    String? exported;
    messenger.setMockMethodCallHandler(_fixtureChannel, (call) async {
      if (call.method == 'deviceInfo') {
        return {'architecture': 'arm64-v8a'};
      }
      expect(call.method, 'state');
      return {
        'enabled': true,
        'sessionReady': true,
        'sessionRestored': true,
        'quotaLimit': 2048,
        'quotaRemaining': 1024,
        'sessionId': 'sensitive probe marker',
        'failure': 'sensitive proxy marker',
      };
    });
    messenger.setMockMethodCallHandler(_androidChannel, (call) async {
      if (call.method == 'saveFile') {
        expect(call.arguments['name'], 'pol-vpn-diagnostics.txt');
        expect(call.arguments['mime'], 'text/plain');
        exported = utf8.decode(call.arguments['bytes'] as Uint8List);
        return 'pol-vpn-diagnostics.txt';
      }
      expect(call.method, 'setOn');
      throw PlatformException(
        code: 'vpn_denied',
        message: 'private IPC marker',
      );
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = call.arguments['text'] as String;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_fixtureChannel, null);
      messenger.setMockMethodCallHandler(_androidChannel, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      const AndroidPreviewApp(home: AndroidTunnelTestPage(fixture: _fixture)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Test session · Restored'), findsOneWidget);

    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Android VPN permission was declined.'), findsOneWidget);
    expect(find.textContaining('private IPC marker'), findsNothing);

    await tester.tap(find.text('Diagnostics'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy report'));
    await tester.pumpAndSettle();
    expect(clipboard, contains('Mode: Local tunnel test'));
    expect(clipboard, contains('Architecture: arm64-v8a'));
    expect(clipboard, contains('VPN connection: Test VPN failed'));
    expect(clipboard, contains('TUN interface: Pending'));
    expect(clipboard, contains('Authentication: Restored'));
    expect(clipboard, contains('Quota:'));
    expect(
      clipboard,
      contains('Last test issue: Android VPN permission was declined.'),
    );
    expect(clipboard, isNot(contains('marker')));

    await tester.tap(find.text('Export report'));
    await tester.pumpAndSettle();
    expect(exported, clipboard);
    expect(find.text('Diagnostics saved.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
