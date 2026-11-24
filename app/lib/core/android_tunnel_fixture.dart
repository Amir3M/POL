import 'package:flutter/services.dart';

const tunnelFixtureUrl = 'http://192.0.2.1:8080/';

/// The test bridge returns aggregate evidence from the local endpoint.
class AndroidTunnelFixture {
  const AndroidTunnelFixture();

  static const _channel = MethodChannel('pol/tunnel_fixture');

  Future<TunnelFixtureState> readState() async => TunnelFixtureState.fromMap(
    await _channel
            .invokeMapMethod<String, Object?>('state')
            .timeout(const Duration(seconds: 2)) ??
        const {},
  );

  Future<bool> isEnabled() async {
    try {
      return (await readState()).enabled;
    } on Exception {
      return false;
    }
  }

  Future<void> signIn() => _channel.invokeMethod<void>('signIn');

  Future<void> signOut() => _channel.invokeMethod<void>('signOut');

  Future<bool> renewSession() async =>
      await _channel.invokeMethod<bool>('renewSession') ?? false;

  Future<bool> openProbe() async =>
      await _channel.invokeMethod<bool>('openProbe') ?? false;

  Future<Map<String, Object?>?> deviceInfo() =>
      _channel.invokeMapMethod<String, Object?>('deviceInfo');
}

enum TunnelFixtureIssue {
  permissionDenied('Android VPN permission was declined.'),
  connect('Could not start the test VPN.'),
  disconnect('Could not stop the test VPN.'),
  revoked('Android revoked the test VPN connection.'),
  tunnelSetup('Android could not establish the test VPN interface.'),
  proxyAuthorization('The test proxy could not authorize the session.'),
  sessionStorage('Android could not read the stored test session.'),
  startSession('Could not start the test session.'),
  endSession('Could not end the test session.'),
  renewSession('Could not renew the test session.'),
  openPage('Could not open the test page.'),
  copyAddress('Could not copy the test address.');

  const TunnelFixtureIssue(this.message);

  final String message;
}

class TunnelFixtureState {
  TunnelFixtureState.fromMap(Map<String, Object?> state)
    : enabled = state['enabled'] == true,
      sessionReady = state['sessionReady'] == true,
      sessionRestored = state['sessionRestored'] == true,
      sessionRenewed = state['sessionRenewed'] == true,
      proxyAuthorized = state['proxyAuthorized'] == true,
      connecting = state['connecting'] == true,
      disconnecting = state['disconnecting'] == true,
      vpnEstablished = state['vpnEstablished'] == true,
      connected = state['connected'] == true,
      requests = _count(state['requests']) ?? 0,
      bytesUp = _count(state['bytesUp']) ?? 0,
      bytesDown = _count(state['bytesDown']) ?? 0,
      quotaLimit = _count(state['quotaLimit']),
      quotaRemaining = _count(state['quotaRemaining']),
      currentIssue = switch (state['failure']) {
        'vpn_revoked' => TunnelFixtureIssue.revoked,
        'tunnel_start_failed' => TunnelFixtureIssue.tunnelSetup,
        'core_stop_failed' => TunnelFixtureIssue.disconnect,
        'session_store_unavailable' => TunnelFixtureIssue.sessionStorage,
        'fixture_connection_failed' => TunnelFixtureIssue.proxyAuthorization,
        final String code when code.isNotEmpty => TunnelFixtureIssue.connect,
        _ => null,
      };

  final bool enabled;
  final bool sessionReady;
  final bool sessionRestored;
  final bool sessionRenewed;
  final bool proxyAuthorized;
  final bool connecting;
  final bool disconnecting;
  final bool vpnEstablished;
  final bool connected;
  final TunnelFixtureIssue? currentIssue;
  final int requests;
  final int bytesUp;
  final int bytesDown;
  final int? quotaLimit;
  final int? quotaRemaining;

  bool get transferVerified => requests > 0 && bytesUp > 0 && bytesDown > 0;

  bool get hasQuota {
    final limit = quotaLimit;
    final remaining = quotaRemaining;
    return sessionReady &&
        limit != null &&
        limit > 0 &&
        remaining != null &&
        remaining <= limit;
  }

  static int? _count(Object? value) =>
      value is int && value >= 0 ? value : null;
}
