import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_info.dart';

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
  const AndroidDiagnosticsPage({super.key});

  @override
  State<AndroidDiagnosticsPage> createState() => _AndroidDiagnosticsPageState();
}

class _AndroidDiagnosticsPageState extends State<AndroidDiagnosticsPage> {
  late final Future<String> _report = _readReport();
  bool _exporting = false;

  Future<String> _readReport() async {
    Map<Object?, Object?> info = const {};
    try {
      final response = await _previewChannel.invokeMethod<Object?>(
        'deviceInfo',
      );
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
      'VPN connection: Unavailable',
      'Authentication: Unavailable',
      'Quota: Unavailable',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics')),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: _report,
          builder: (context, snapshot) {
            final report = snapshot.data;
            if (report == null) {
              return const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'Loading diagnostics',
                ),
              );
            }
            return Align(
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
                    const SizedBox(height: 24),
                    Wrap(
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
                  ],
                ),
              ),
            );
          },
        ),
      ),
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
      final result = await _previewChannel.invokeMethod<Object?>(
        'exportDiagnostics',
        {'text': report},
      );
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
