import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr/qr.dart';

import 'widgets.dart';

/// An address on an interface the Android host can share with nearby devices.
class ShareProxyEndpoint {
  const ShareProxyEndpoint({required this.address, required this.networkType});

  final String address;
  final String networkType;
}

class ShareProxyCard extends StatefulWidget {
  const ShareProxyCard({
    super.key,
    required this.endpoints,
    required this.active,
    required this.connected,
    required this.busy,
    required this.port,
    required this.username,
    required this.password,
    required this.onRotate,
    required this.onShare,
    this.alternatives = const [],
    this.onSelectEndpoint,
    this.problem,
  });

  final List<ShareProxyEndpoint> endpoints;
  final bool active;
  final bool connected;
  final bool busy;
  final int port;
  final String username;
  final String password;
  final Future<void> Function() onRotate;
  final Future<void> Function(String text) onShare;
  final List<ShareProxyEndpoint> alternatives;
  final Future<void> Function(String address)? onSelectEndpoint;
  final String? problem;

  bool get _available =>
      active && connected && !busy && port > 0 &&
      username.isNotEmpty && password.isNotEmpty;

  @override
  State<ShareProxyCard> createState() => _ShareProxyCardState();
}

class _ShareProxyCardState extends State<ShareProxyCard> {
  String? _selected;
  ValueNotifier<ShareProxyCard?>? _details;

  @override
  void didUpdateWidget(ShareProxyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_details case final details?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(_details, details)) details.value = widget;
      });
    }
  }

  @override
  void dispose() {
    final details = _details;
    if (details != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (identical(_details, details)) details.value = null;
      });
    }
    super.dispose();
  }

  ShareProxyEndpoint? get _endpoint {
    for (final endpoint in widget.endpoints) {
      if (endpoint.address == _selected) return endpoint;
    }
    return widget.endpoints.firstOrNull;
  }

  bool _isCurrent(ShareProxyCard snapshot, ShareProxyEndpoint endpoint) =>
      mounted &&
      widget._available &&
      widget.port == snapshot.port &&
      widget.username == snapshot.username &&
      widget.password == snapshot.password &&
      widget.endpoints.any((item) => item.address == endpoint.address);

  Future<void> _showDetails() async {
    if (_details != null) return;
    final details = ValueNotifier<ShareProxyCard?>(widget);
    _details = details;
    try {
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (_) => _ShareProxyDetails(
          updates: details,
          selected: _endpoint?.address,
          isCurrent: _isCurrent,
          onSelected: (address) {
            if (mounted) setState(() => _selected = address);
          },
        ),
      );
    } finally {
      if (identical(_details, details)) _details = null;
      details.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = _ShareCopy.of(context);
    final theme = Theme.of(context);
    final endpoint = _endpoint;
    final sharing = widget._available;
    final state = widget.busy
        ? copy.settingUp
        : widget.active && endpoint == null
        ? copy.noNetwork
        : widget.active && !widget.connected
        ? copy.waiting
        : sharing && endpoint != null
        ? copy.ready
        : copy.off;
    return Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.lan_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(copy.title, style: theme.textTheme.titleMedium),
              ),
              if (sharing && endpoint != null)
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline_rounded, size: 16),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          copy.protected,
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(state, style: theme.textTheme.bodyMedium),
          if (sharing && endpoint != null)
            _EndpointPicker(
              endpoints: widget.endpoints,
              selected: endpoint.address,
              port: widget.port,
              onChanged: (address) => setState(() => _selected = address),
            ),
          if (widget.problem case final problem? when problem.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                problem,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (sharing && endpoint != null)
                OutlinedButton.icon(
                  onPressed: () => _copy(
                    context,
                    _address(endpoint, widget.port),
                  ),
                  icon: const Icon(Icons.content_copy_rounded, size: 18),
                  label: Text(copy.copyAddress),
                ),
              TextButton(onPressed: _showDetails, child: Text(copy.details)),
            ],
          ),
        ],
      ),
    );
  }
}

String _address(ShareProxyEndpoint endpoint, int port) =>
    '${endpoint.address}:$port';

String _connectionLink(ShareProxyCard state, ShareProxyEndpoint endpoint) =>
    Uri(
      scheme: 'socks5',
      userInfo:
          '${Uri.encodeComponent(state.username)}:${Uri.encodeComponent(state.password)}',
      host: endpoint.address,
      port: state.port,
    ).toString();

Future<void> _copy(BuildContext context, String value) async {
  final text = _ShareCopy.of(context);
  try {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text.copied)),
    );
  } on PlatformException {
    if (context.mounted) showError(context, text.actionFailed);
  }
}

class _EndpointPicker extends StatelessWidget {
  const _EndpointPicker({
    required this.endpoints,
    required this.selected,
    required this.port,
    required this.onChanged,
  });

  final List<ShareProxyEndpoint> endpoints;
  final String selected;
  final int port;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final copy = _ShareCopy.of(context);
    final style = Theme.of(context).textTheme.bodyMedium;
    final options = {for (final endpoint in endpoints) endpoint.address: endpoint};
    return DropdownButton<String>(
      isExpanded: true,
      value: selected,
      style: style,
      items: [
        for (final endpoint in options.values)
          DropdownMenuItem(
            value: endpoint.address,
            child: Text(
              'SOCKS5 ${_address(endpoint, port)} · ${copy.network(endpoint.networkType)}',
              textDirection: TextDirection.ltr,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: options.length > 1
          ? (address) {
              if (address != null) onChanged(address);
            }
          : null,
    );
  }
}

class _ShareProxyDetails extends StatefulWidget {
  const _ShareProxyDetails({
    required this.updates,
    required this.selected,
    required this.isCurrent,
    required this.onSelected,
  });

  final ValueListenable<ShareProxyCard?> updates;
  final String? selected;
  final bool Function(ShareProxyCard, ShareProxyEndpoint) isCurrent;
  final ValueChanged<String> onSelected;

  @override
  State<_ShareProxyDetails> createState() => _ShareProxyDetailsState();
}

class _ShareProxyDetailsState extends State<_ShareProxyDetails> {
  String? _selected;
  bool _reveal = false;
  bool _rotating = false;
  bool _switchingEndpoint = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.selected;
  }

  Future<bool> _confirm(
    _ShareCopy copy, {
    required String title,
    required String message,
    required String action,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(copy.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _expose(
    ShareProxyCard snapshot,
    ShareProxyEndpoint endpoint,
    _Exposure action,
  ) async {
    final copy = _ShareCopy.of(context);
    if (!await _confirm(
          copy,
          title: copy.shareWarningTitle,
          message: copy.shareWarning,
          action: copy.continueLabel,
        ) ||
        !mounted ||
        !widget.isCurrent(snapshot, endpoint)) {
      return;
    }
    try {
      if (action == _Exposure.copy) {
        await _copy(
          context,
          'SOCKS5\n${copy.host}: ${endpoint.address}\n'
          '${copy.port}: ${snapshot.port}\n'
          '${copy.username}: ${snapshot.username}\n'
          '${copy.password}: ${snapshot.password}',
        );
      } else if (action == _Exposure.share) {
        await snapshot.onShare(_connectionLink(snapshot, endpoint));
      } else {
        await _showQr(snapshot, endpoint, copy);
      }
    } on Exception {
      if (mounted) showError(context, copy.actionFailed);
    }
  }

  Future<void> _showQr(
    ShareProxyCard snapshot,
    ShareProxyEndpoint endpoint,
    _ShareCopy copy,
  ) {
    final qr = QrImage(
      QrCode.fromData(
        data: _connectionLink(snapshot, endpoint),
        errorCorrectLevel: QrErrorCorrectLevel.M,
      ),
    );
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(copy.qr),
        content: ValueListenableBuilder<ShareProxyCard?>(
          valueListenable: widget.updates,
          builder: (context, _, _) => widget.isCurrent(snapshot, endpoint)
              ? SizedBox.square(
                  dimension: (MediaQuery.sizeOf(context).width - 104)
                      .clamp(128, 280).toDouble(),
                  child: CustomPaint(painter: _ProxyQrPainter(qr)),
                )
              : Text(copy.expired),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(copy.close),
          ),
        ],
      ),
    );
  }

  Future<void> _rotate(
    ShareProxyCard snapshot,
    ShareProxyEndpoint endpoint,
  ) async {
    final copy = _ShareCopy.of(context);
    if (!await _confirm(
          copy,
          title: copy.rotate,
          message: copy.rotateWarning,
          action: copy.rotate,
        ) ||
        !mounted ||
        !widget.isCurrent(snapshot, endpoint)) {
      return;
    }
    setState(() {
      _rotating = true;
      _reveal = false;
    });
    try {
      await snapshot.onRotate();
    } on Exception {
      if (mounted) showError(context, copy.actionFailed);
    } finally {
      if (mounted) setState(() => _rotating = false);
    }
  }

  Future<void> _switchEndpoint(
    Future<void> Function(String address) select,
    String address,
  ) async {
    final copy = _ShareCopy.of(context);
    setState(() {
      _switchingEndpoint = true;
      _reveal = false;
    });
    try {
      await select(address);
      if (mounted) widget.onSelected(address);
    } on Exception {
      if (mounted) showError(context, copy.actionFailed);
    } finally {
      if (mounted) setState(() => _switchingEndpoint = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = _ShareCopy.of(context);
    final theme = Theme.of(context);
    return ValueListenableBuilder<ShareProxyCard?>(
      valueListenable: widget.updates,
      builder: (context, state, _) {
        final endpoint =
            state?.endpoints.where((item) => item.address == _selected).firstOrNull ??
            state?.endpoints.firstOrNull;
        final chooseEndpoint = state?.onSelectEndpoint;
        final options = {
          for (final item in state?.endpoints ?? const <ShareProxyEndpoint>[])
            item.address: item,
          for (final item in state?.alternatives ?? const <ShareProxyEndpoint>[])
            item.address: item,
        };
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .88,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(copy.title, style: theme.textTheme.titleLarge),
                      ),
                      IconButton(
                        tooltip: copy.close,
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  if (chooseEndpoint != null && options.length > 1)
                    DropdownButton<String>(
                      isExpanded: true,
                      value: endpoint?.address,
                      hint: Text(copy.chooseNetwork),
                      items: [
                        for (final item in options.values)
                          DropdownMenuItem(
                            value: item.address,
                            child: Text(
                              '${copy.network(item.networkType)} · ${item.address}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _rotating || _switchingEndpoint || state?.busy == true
                          ? null
                          : (address) {
                              if (address != null && address != endpoint?.address) {
                                _switchEndpoint(chooseEndpoint, address);
                              }
                            },
                    ),
                  if (state != null &&
                      state._available &&
                      endpoint != null &&
                      !_switchingEndpoint) ...[
                    Text(copy.protected),
                    const SizedBox(height: 6),
                    _EndpointPicker(
                      endpoints: state.endpoints,
                      selected: endpoint.address,
                      port: state.port,
                      onChanged: (address) {
                        setState(() {
                          _selected = address;
                          _reveal = false;
                        });
                        widget.onSelected(address);
                      },
                    ),
                    _detail(copy.networkTitle, copy.network(endpoint.networkType)),
                    _detail(copy.host, endpoint.address),
                    _detail(copy.port, '${state.port}'),
                    _detail(copy.username, state.username),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: _detail(
                            copy.password,
                            _reveal ? state.password : '••••••••',
                          ),
                        ),
                        IconButton(
                          tooltip: _reveal ? copy.hide : copy.reveal,
                          onPressed: _rotating
                              ? null
                              : () => setState(() => _reveal = !_reveal),
                          icon: Icon(
                            _reveal
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _rotating
                              ? null
                              : () => _expose(state, endpoint, _Exposure.copy),
                          icon: const Icon(Icons.content_copy_rounded, size: 18),
                          label: Text(copy.copyDetails),
                        ),
                        OutlinedButton.icon(
                          onPressed: _rotating
                              ? null
                              : () => _expose(state, endpoint, _Exposure.share),
                          icon: const Icon(Icons.share_outlined, size: 18),
                          label: Text(copy.share),
                        ),
                        OutlinedButton.icon(
                          onPressed: _rotating
                              ? null
                              : () => _expose(state, endpoint, _Exposure.qr),
                          icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                          label: Text(copy.qr),
                        ),
                        TextButton(
                          onPressed:
                              _rotating ? null : () => _rotate(state, endpoint),
                          child: Text(copy.rotate),
                        ),
                      ],
                    ),
                  ] else
                    Text(_switchingEndpoint || state?.busy == true
                        ? copy.settingUp
                        : state?.active == true && endpoint == null
                        ? copy.noNetwork
                        : copy.off),
                  const Divider(height: 28),
                  Text(copy.setup, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(copy.sameNetwork),
                  for (final entry in copy.instructions.entries)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 12),
                      title: Text(entry.key),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text(entry.value)],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 6),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

enum _Exposure { copy, share, qr }

class _ProxyQrPainter extends CustomPainter {
  const _ProxyQrPainter(this.qr);

  final QrImage qr;

  @override
  void paint(Canvas canvas, Size size) {
    final white = Paint()..color = Colors.white;
    final black = Paint()..color = Colors.black;
    canvas.drawRect(Offset.zero & size, white);
    const quietZone = 4;
    final side = size.shortestSide / (qr.moduleCount + quietZone * 2);
    for (var row = 0; row < qr.moduleCount; row++) {
      for (var column = 0; column < qr.moduleCount; column++) {
        if (!qr.isDark(row, column)) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            (column + quietZone) * side,
            (row + quietZone) * side,
            side,
            side,
          ),
          black,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ProxyQrPainter oldDelegate) =>
      !identical(qr, oldDelegate.qr);
}

class _ShareCopy {
  const _ShareCopy(this.fa);
  final bool fa;

  factory _ShareCopy.of(BuildContext context) =>
      _ShareCopy(Localizations.localeOf(context).languageCode == 'fa');

  String _t(String en, String faText) => fa ? faText : en;
  String get title => _t('Share Proxy', 'اشتراک‌گذاری پراکسی');
  String get protected => _t('Password-protected', 'محافظت‌شده با رمز');
  String get ready => _t('Sharing on your local network', 'در حال اشتراک‌گذاری روی شبکهٔ محلی');
  String get off => _t('Sharing is off', 'اشتراک‌گذاری خاموش است');
  String get waiting => _t('Connect AMiR VPN to start sharing.', 'برای اشتراک‌گذاری AMiR VPN را وصل کنید.');
  String get settingUp => _t('Setting up sharing…', 'در حال راه‌اندازی اشتراک‌گذاری…');
  String get noNetwork => _t(
    'Connect to Wi-Fi or enable your mobile hotspot to share your proxy.',
    'برای اشتراک‌گذاری پراکسی به وای‌فای وصل شوید یا نقطهٔ اتصال گوشی را روشن کنید.',
  );
  String get details => _t('Details', 'جزئیات');
  String get copyAddress => _t('Copy address', 'کپی نشانی');
  String get copyDetails => _t('Copy connection details', 'کپی اطلاعات اتصال');
  String get copied => _t('Copied', 'کپی شد');
  String get share => _t('Share connection link', 'اشتراک‌گذاری پیوند اتصال');
  String get qr => _t('Show QR code', 'نمایش کد QR');
  String get rotate => _t('Regenerate credentials', 'ساخت اطلاعات ورود تازه');
  String get expired => _t('This connection code expired.', 'این کد اتصال منقضی شد.');
  String get host => _t('IPv4 address', 'نشانی IPv4');
  String get port => _t('Port', 'درگاه');
  String get username => _t('Username', 'نام کاربری');
  String get password => _t('Password', 'رمز عبور');
  String get hide => _t('Hide password', 'پنهان کردن رمز');
  String get reveal => _t('Reveal password', 'نمایش رمز');
  String get chooseNetwork => _t('Choose local network', 'انتخاب شبکهٔ محلی');
  String get networkTitle => _t('Network type', 'نوع شبکه');
  String get close => _t('Close', 'بستن');
  String get cancel => _t('Cancel', 'لغو');
  String get continueLabel => _t('Continue', 'ادامه');
  String get actionFailed => _t('Could not complete the action. Try again.', 'انجام عملیات ممکن نشد. دوباره تلاش کنید.');
  String get shareWarningTitle => _t('Share proxy credentials?', 'اطلاعات ورود پراکسی را به اشتراک می‌گذارید؟');
  String get shareWarning => _t(
    'Connection details, links, and QR codes contain your proxy password. Share them only with devices or people you trust on this network.',
    'اطلاعات اتصال، پیوند و کد QR شامل رمز پراکسی هستند. فقط با دستگاه‌ها یا افراد مورد اعتماد در همین شبکه به اشتراک بگذارید.',
  );
  String get rotateWarning => _t(
    'The current credentials will stop working. Connected clients will need the new username and password.',
    'اطلاعات ورود فعلی غیرفعال می‌شوند. دستگاه‌های دیگر به نام کاربری و رمز جدید نیاز خواهند داشت.',
  );
  String get setup => _t('Set up another device', 'راه‌اندازی دستگاه دیگر');
  String get sameNetwork => _t(
    'Join the same Wi-Fi network or connect to this phone’s hotspot.',
    'به همان شبکهٔ وای‌فای یا نقطهٔ اتصال این گوشی وصل شوید.',
  );

  String network(String value) {
    final label = value.toLowerCase();
    if (label.contains('hotspot')) return _t('Hotspot', 'نقطهٔ اتصال');
    if (label.contains('wifi') || label.contains('wi-fi')) return _t('Wi-Fi', 'وای‌فای');
    if (label.contains('ethernet')) return _t('Ethernet', 'اترنت');
    if (label.contains('usb')) return _t('USB tethering', 'اتصال USB');
    return _t('Local network', 'شبکهٔ محلی');
  }

  Map<String, String> get instructions => {
    'Telegram': _t(
      'Open Settings → Data and Storage → Proxy Settings. Add a SOCKS5 proxy and enter the address, port, username, and password.',
      'در تنظیمات به داده و ذخیره‌سازی و سپس تنظیمات پراکسی بروید. پراکسی SOCKS5 اضافه کنید و نشانی، درگاه، نام کاربری و رمز را وارد کنید.',
    ),
    'Windows': _t(
      'In a Windows app that supports authenticated SOCKS5, open its proxy settings and enter the connection details.',
      'در تنظیمات برنامه‌ای در ویندوز که از SOCKS5 با رمز پشتیبانی می‌کند، اطلاعات اتصال را وارد کنید.',
    ),
    'Linux': _t(
      'Open the proxy settings of a client that supports authenticated SOCKS5 and enter the connection details.',
      'در تنظیمات پراکسی برنامه‌ای که از SOCKS5 با رمز پشتیبانی می‌کند، اطلاعات اتصال را وارد کنید.',
    ),
    'Firefox': _t(
      'Use a trusted Firefox extension that supports SOCKS5 username and password if your browser settings do not offer those fields.',
      'اگر تنظیمات فایرفاکس نام کاربری و رمز SOCKS5 ندارد، از افزونهٔ معتبری که از این قابلیت پشتیبانی می‌کند استفاده کنید.',
    ),
    _t('Other apps', 'برنامه‌های دیگر'): _t(
      'Select SOCKS5 in the app’s proxy settings. Enter the IPv4 address, port, username, and password. QR and links work with clients that support SOCKS5 import.',
      'در تنظیمات پراکسی برنامه، SOCKS5 را انتخاب کنید و نشانی، درگاه، نام کاربری و رمز را وارد کنید. کد QR و پیوند برای برنامه‌هایی است که وارد کردن اتصال SOCKS5 را پشتیبانی می‌کنند.',
    ),
  };
}
