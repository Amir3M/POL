import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../app_info.dart';
import '../core/android_online_diagnostics.dart';
import 'android_diagnostics.dart';

const _debugOnlineDiagnostics =
    kDebugMode && !bool.fromEnvironment('POL_TUNNEL_TEST')
    ? AndroidOnlineDiagnostics.approvalRequired()
    : null;

class AndroidPreviewApp extends StatelessWidget {
  const AndroidPreviewApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'POL VPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF0C0C0C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE5E5E5),
          onPrimary: Color(0xFF0C0C0C),
          surface: Color(0xFF191919),
          onSurface: Color(0xFFFFFFFF),
          onSurfaceVariant: Color(0xFFBDBDBD),
        ),
      ),
      home: home ?? const _PreviewScreen(),
    );
  }
}

class _PreviewScreen extends StatelessWidget {
  const _PreviewScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'POL VPN',
                      style: theme.textTheme.headlineLarge,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'VPN access unavailable',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Offline preview. Account setup and VPN connections require service authorization.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AndroidDiagnosticsPage(
                              online: _debugOnlineDiagnostics,
                            ),
                          ),
                        ),
                        child: const Text('Diagnostics'),
                      ),
                      TextButton(
                        onPressed: () => _showAbout(context),
                        child: const Text('About POL VPN'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About POL VPN'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Version $appVersion'),
              SizedBox(height: 12),
              Text(
                'POL VPN is an independent, unofficial project based on Arman VPN. '
                'It has no affiliation with Mozilla or Firefox.',
              ),
              SizedBox(height: 12),
              Text('Licensed under GPL-3.0.'),
              SizedBox(height: 12),
              Text('POL VPN source'),
              SelectableText('https://github.com/Amir3M/POL'),
              SizedBox(height: 12),
              Text('Arman VPN upstream'),
              SelectableText('https://github.com/armanlife/arman-vpn-client'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'POL VPN',
              applicationVersion: appVersion,
            ),
            child: const Text('Open-source licenses'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
