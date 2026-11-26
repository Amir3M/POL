import 'package:arman_vpn/ui/share_proxy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _page({
  List<ShareProxyEndpoint> endpoints = const [],
  Future<void> Function(String)? share,
}) => MaterialApp(
  home: Scaffold(
    body: ShareProxyCard(
      endpoints: endpoints,
      active: true,
      connected: true,
      busy: false,
      port: 10810,
      username: 'proxy-user',
      password: 'test-only-password',
      onRotate: () async {},
      onShare: share ?? (_) async {},
    ),
  ),
);

void main() {
  testWidgets('shows the no-network instruction on a narrow display', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 740);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_page());
    expect(
      find.text(
        'Connect to Wi-Fi or enable your mobile hotspot to share your proxy.',
      ),
      findsOneWidget,
    );
    expect(find.text('Copy address'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('proxy details mask the password and ask before sharing', (
    tester,
  ) async {
    String? shared;
    await tester.pumpWidget(
      _page(
        endpoints: const [
          ShareProxyEndpoint(address: '192.168.5.1', networkType: 'hotspot'),
          ShareProxyEndpoint(address: '192.168.2.7', networkType: 'wifi'),
        ],
        share: (text) async => shared = text,
      ),
    );
    expect(find.text('Password-protected'), findsOneWidget);
    expect(find.text('SOCKS5 192.168.5.1:10810 · Hotspot'), findsOneWidget);
    expect(find.text('test-only-password'), findsNothing);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('••••••••'), findsOneWidget);
    expect(find.text('test-only-password'), findsNothing);
    await tester.tap(find.byTooltip('Reveal password'));
    await tester.pumpAndSettle();
    expect(find.text('test-only-password'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide password'));
    await tester.pumpAndSettle();
    expect(find.text('test-only-password'), findsNothing);
    await tester.ensureVisible(find.text('Share connection link'));
    await tester.tap(find.text('Share connection link'));
    await tester.pumpAndSettle();
    expect(find.text('Share proxy credentials?'), findsOneWidget);
    expect(shared, isNull);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(shared, 'socks5://proxy-user:test-only-password@192.168.5.1:10810');
  });
}
