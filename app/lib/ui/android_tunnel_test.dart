import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/android_core.dart';
import '../core/android_tunnel_fixture.dart';
import '../core/core_controller.dart';
import 'android_diagnostics.dart';
import 'format.dart';

class AndroidTunnelTestPage extends StatefulWidget {
  const AndroidTunnelTestPage({super.key, required this.fixture});

  final AndroidTunnelFixture fixture;

  @override
  State<AndroidTunnelTestPage> createState() => _AndroidTunnelTestPageState();
}

class _AndroidTunnelTestPageState extends State<AndroidTunnelTestPage> {
  final _core = CoreController.nativePower(AndroidCore.setOn);
  late final AppLifecycleListener _lifecycle;
  Timer? _poll;
  TunnelFixtureState? _state;
  int _refreshSequence = 0;
  bool _busy = false;
  bool? _requestedPower;
  String? _feedback;
  TunnelFixtureIssue? _lastIssue;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: _startPolling,
      onHide: _stopPolling,
    );
    _startPolling();
  }

  void _startPolling() {
    _poll ??= Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    unawaited(_refresh());
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _refresh() async {
    final sequence = ++_refreshSequence;
    TunnelFixtureState? state;
    try {
      final next = await widget.fixture.readState();
      if (next.enabled) state = next;
    } on Exception {
      // The report only contains known states and numeric counts.
    }
    if (mounted && sequence == _refreshSequence) {
      setState(() => _state = state);
    }
  }

  @override
  void dispose() {
    _stopPolling();
    _lifecycle.dispose();
    _core.dispose();
    super.dispose();
  }

  Future<void> _act(
    Future<void> Function() action, {
    required TunnelFixtureIssue failure,
    bool? requestedPower,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _requestedPower = requestedPower;
      _feedback = null;
    });
    try {
      await action();
    } on VpnNotAllowed {
      _showIssue(TunnelFixtureIssue.permissionDenied);
    } on Exception {
      _showIssue(failure);
    } finally {
      if (mounted) {
        await _refresh();
        if (mounted) {
          setState(() {
            _busy = false;
            _requestedPower = null;
          });
        }
      }
    }
  }

  void _showFeedback(String feedback) {
    if (mounted) setState(() => _feedback = feedback);
  }

  void _showIssue(TunnelFixtureIssue issue) {
    _lastIssue = issue;
    _showFeedback(issue.message);
  }

  Future<void> _setPower(bool on) => _act(
    () => _core.setOn(on),
    requestedPower: on,
    failure: on ? TunnelFixtureIssue.connect : TunnelFixtureIssue.disconnect,
  );

  Future<void> _renewSession() => _act(() async {
    if (!await widget.fixture.renewSession()) {
      _showIssue(TunnelFixtureIssue.renewSession);
    }
  }, failure: TunnelFixtureIssue.renewSession);

  Future<void> _openProbe() => _act(() async {
    if (!await widget.fixture.openProbe()) {
      _showFeedback('Copy the address and open it in your browser.');
    }
  }, failure: TunnelFixtureIssue.openPage);

  Future<void> _copyProbe() => _act(() async {
    await Clipboard.setData(const ClipboardData(text: tunnelFixtureUrl));
    _showFeedback('Test address copied.');
  }, failure: TunnelFixtureIssue.copyAddress);

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final theme = Theme.of(context);
    final sessionReady = state?.sessionReady ?? false;
    final connected = state?.connected ?? false;
    final interfaceActive = connected || state?.vpnEstablished == true;
    final starting = _requestedPower == true || state?.connecting == true;
    final stopping = _requestedPower == false || state?.disconnecting == true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('POL VPN'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AndroidDiagnosticsPage(
                  fixture: widget.fixture,
                  lastIssue: _lastIssue,
                ),
              ),
            ),
            child: const Text('Diagnostics'),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Local tunnel test',
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This debug build checks Android VPN traffic to a controlled local page.',
                ),
                const SizedBox(height: 20),
                _TestStage(
                  'Test session',
                  state?.sessionLabel ?? 'Unavailable',
                ),
                _TestStage(
                  'Proxy authorization',
                  state?.authorizationLabel ?? 'Unavailable',
                ),
                _TestStage(
                  'Android VPN',
                  starting
                      ? 'Connecting'
                      : stopping
                      ? 'Disconnecting'
                      : state?.vpnLabel ?? 'Unavailable',
                ),
                _TestStage(
                  'Test transfer',
                  state?.transferLabel ?? 'Unavailable',
                ),
                _TestStage('Test quota', state?.quotaLabel ?? 'Unavailable'),
                if (state != null && state.requests > 0)
                  Text(
                    '${formatBytes(state.bytesDown)} downloaded, ${formatBytes(state.bytesUp)} uploaded',
                  ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!sessionReady)
                      FilledButton(
                        onPressed: _busy || state == null
                            ? null
                            : () => _act(
                                widget.fixture.signIn,
                                failure: TunnelFixtureIssue.startSession,
                              ),
                        child: const Text('Start test session'),
                      )
                    else ...[
                      FilledButton(
                        onPressed: _busy || starting || stopping
                            ? null
                            : () => _setPower(!interfaceActive),
                        child: Text(interfaceActive ? 'Disconnect' : 'Connect'),
                      ),
                      if (connected)
                        TextButton(
                          onPressed: _busy || stopping ? null : _renewSession,
                          child: const Text('Renew test session'),
                        ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _act(
                                widget.fixture.signOut,
                                failure: TunnelFixtureIssue.endSession,
                              ),
                        child: const Text('End test session'),
                      ),
                    ],
                  ],
                ),
                if (connected) ...[
                  const SizedBox(height: 20),
                  SelectableText(tunnelFixtureUrl),
                  const SizedBox(height: 8),
                  const Text(
                    'Open the page in your browser and run its upload and download test. Return here to check the result.',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: _busy ? null : _openProbe,
                        child: const Text('Open test page'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _copyProbe,
                        child: const Text('Copy address'),
                      ),
                    ],
                  ),
                ],
                if (_feedback case final message?)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(liveRegion: true, child: Text(message)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TestStage extends StatelessWidget {
  const _TestStage(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label · ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
