import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_info.dart';
import '../core/android_core.dart';
import '../core/android_online_diagnostics.dart';
import '../core/android_tunnel_fixture.dart';
import 'format.dart';

const _previewChannel = MethodChannel('pol/preview');
const _buildId = String.fromEnvironment('POL_BUILD_ID', defaultValue: 'local');
const _androidArchitectures = {
  'arm64-v8a',
  'armeabi-v7a',
  'x86',
  'x86_64',
  'riscv64',
};
final _androidVersionPattern = RegExp(r'^\d{1,2}(?:\.\d{1,2}){0,2}$');

class AndroidDiagnosticsPage extends StatefulWidget {
  const AndroidDiagnosticsPage({
    super.key,
    this.fixture,
    this.lastIssue,
    this.online,
  }) : assert(fixture == null || online == null);

  final AndroidTunnelFixture? fixture;
  final TunnelFixtureIssue? lastIssue;
  final AndroidOnlineDiagnostics? online;

  @override
  State<AndroidDiagnosticsPage> createState() => _AndroidDiagnosticsPageState();
}

class _AndroidDiagnosticsPageState extends State<AndroidDiagnosticsPage> {
  late final Future<String> _report = _readReport();
  bool _exporting = false;

  Future<String> _readReport() async {
    final fixture = widget.fixture;
    final lastIssue = widget.lastIssue;
    final online = widget.online;
    Map<Object?, Object?> info = const {};
    try {
      final response = fixture == null
          ? await _previewChannel.invokeMethod<Object?>('deviceInfo')
          : await fixture.deviceInfo();
      if (response is Map<Object?, Object?>) info = response;
    } on Exception {
      // Android details are optional. Keep raw channel errors out of reports.
    }

    final version = info['androidVersion'];
    final sdk = info['sdk'];
    final architecture = info['architecture'];
    const unavailable = 'Unavailable';
    final androidVersion =
        version is String && _androidVersionPattern.hasMatch(version)
        ? version
        : unavailable;
    final androidSdk = sdk is int && sdk > 0 ? '$sdk' : unavailable;
    final androidArchitecture = _androidArchitectures.contains(architecture)
        ? architecture
        : unavailable;
    return [
      'POL VPN diagnostics',
      'App version: $appVersion',
      'Build: $_buildId',
      'Android version: $androidVersion',
      'Android SDK: $androidSdk',
      'Architecture: $androidArchitecture',
      ...await _connectionDetails(fixture),
      if (lastIssue != null) 'Last test issue: ${lastIssue.message}',
      if (online != null) ...await _onlineDetails(online),
    ].join('\n');
  }

  Future<List<String>> _connectionDetails(AndroidTunnelFixture? fixture) async {
    TunnelFixtureState? state;
    try {
      state = await fixture?.readState();
    } on Exception {
      // Keep channel failures and values outside the report schema private.
    }
    if (state == null || !state.enabled) {
      return const [
        'VPN connection: Unavailable',
        'Authentication: Unavailable',
        'Quota: Unavailable',
      ];
    }
    return [
      'Mode: Local tunnel test',
      'VPN connection: ${state.vpnLabel}',
      'TUN interface: ${state.vpnEstablished ? 'Established' : 'Pending'}',
      'Authentication: ${state.sessionLabel}',
      'Restored test session: ${state.sessionRestored ? 'Yes' : 'No'}',
      'Proxy authorization: ${state.authorizationLabel}',
      'Quota: ${state.quotaLabel}',
      'Test transfer: ${state.transferLabel}',
      'Test requests: ${state.requests}',
      'Test upload bytes: ${state.bytesUp}',
      'Test download bytes: ${state.bytesDown}',
      if (state.currentIssue case final issue?)
        'Current test issue: ${issue.message}',
    ];
  }

  Future<List<String>> _onlineDetails(AndroidOnlineDiagnostics online) async {
    final state = await online.readState();
    final quota = state?.quota;
    final quotaLabel = switch (quota) {
      null => 'Unknown',
      _ when quota.unlimited => 'Unlimited',
      _ when quota.remaining == 0 => 'Exhausted',
      _ =>
        '${formatBytes(quota.remaining!)} remaining of ${formatBytes(quota.limit!)}',
    };
    return [
      'Online stage: ${state?.stage.label ?? 'Unavailable'}',
      'HTTP status: ${state?.httpStatus ?? 'Unavailable'}',
      'Reason: ${state?.reason?.label ?? 'Unavailable'}',
      'Provider quota: $quotaLabel',
    ];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _report,
      builder: (context, snapshot) {
        final report = snapshot.data;
        return Scaffold(
          appBar: AppBar(title: const Text('Diagnostics')),
          body: SafeArea(
            child: report == null
                ? const Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: 'Loading diagnostics',
                    ),
                  )
                : Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          SelectableText(
                            report,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          bottomNavigationBar: report == null
              ? null
              : SafeArea(
                  minimum: const EdgeInsets.all(16),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => _copy(report),
                        child: const Text('Copy report'),
                      ),
                      FilledButton(
                        onPressed: _exporting ? null : () => _export(report),
                        child: const Text('Export report'),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Future<void> _copy(String report) async {
    try {
      await Clipboard.setData(ClipboardData(text: report));
      _showFeedback('Diagnostics copied.');
    } on Exception {
      _showFeedback('Could not copy diagnostics.');
    }
  }

  Future<void> _export(String report) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final result = widget.fixture == null
          ? await _previewChannel.invokeMethod<Object?>('exportDiagnostics', {
              'text': report,
            })
          : await AndroidCore.saveFile(
                  'pol-vpn-diagnostics.txt',
                  Uint8List.fromList(utf8.encode(report)),
                  mime: 'text/plain',
                ) !=
                null;
      if (result == true) {
        _showFeedback('Diagnostics saved.');
      } else if (result != false) {
        _showFeedback('Could not save diagnostics.');
      }
    } on Exception {
      _showFeedback('Could not save diagnostics.');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showFeedback(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

extension TunnelFixtureText on TunnelFixtureState {
  String get sessionLabel => !sessionReady
      ? 'Signed out'
      : sessionRenewed
      ? 'Renewed'
      : sessionRestored
      ? 'Restored'
      : 'Ready';

  String get authorizationLabel => proxyAuthorized ? 'Authorized' : 'Pending';

  String get vpnLabel => disconnecting
      ? 'Disconnecting'
      : connected
      ? 'Connected'
      : currentIssue != null
      ? 'Test VPN failed'
      : vpnEstablished
      ? 'Interface active'
      : connecting
      ? 'Connecting'
      : 'Disconnected';

  String get transferLabel => transferVerified
      ? 'Upload and download verified'
      : requests > 0
      ? 'Traffic received'
      : 'Awaiting browser traffic';

  String get quotaLabel {
    if (!hasQuota) return sessionReady ? 'Unknown' : 'Unavailable';
    if (quotaRemaining == 0) return 'Exhausted';
    return '${formatBytes(quotaRemaining!)} remaining of ${formatBytes(quotaLimit!)}';
  }
}
