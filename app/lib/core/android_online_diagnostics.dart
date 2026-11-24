import 'package:flutter/services.dart';

/// Reads a status snapshot, with no provider requests or authentication actions.
class AndroidOnlineDiagnostics {
  const AndroidOnlineDiagnostics() : _localState = null;

  const AndroidOnlineDiagnostics.approvalRequired()
    : _localState = const OnlineDiagnosticsState._(
        stage: OnlineDiagnosticsStage.configuration,
        reason: OnlineDiagnosticsReason.approvalRequired,
      );

  static const _channel = MethodChannel('pol/online_diagnostics');

  final OnlineDiagnosticsState? _localState;

  Future<OnlineDiagnosticsState?> readState() async {
    final localState = _localState;
    if (localState != null) return localState;
    try {
      final reply = await _channel
          .invokeMethod<Object?>('state')
          .timeout(const Duration(seconds: 2));
      return OnlineDiagnosticsState.tryParse(reply);
    } on Exception {
      // Native responses and channel errors may contain private details.
      return null;
    }
  }
}

enum OnlineDiagnosticsStage {
  configuration('configuration', 'Configuration'),
  signIn('sign_in', 'Sign-in'),
  guardian('guardian', 'Direct Guardian request'),
  proxyPass('proxy_pass', 'Proxy pass'),
  http2('http2', 'HTTP/2 session'),
  traffic('traffic', 'Traffic verification');

  const OnlineDiagnosticsStage(this.code, this.label);

  final String code;
  final String label;

  static OnlineDiagnosticsStage? parse(Object? value) {
    for (final stage in values) {
      if (stage.code == value) return stage;
    }
    return null;
  }
}

enum OnlineDiagnosticsReason {
  approvalRequired('approval_required', 'Provider approval required'),
  requestFailed('request_failed', 'Request failed'),
  invalidResponse('invalid_response', 'Invalid provider response'),
  rejected('rejected', 'Provider rejected the request'),
  unauthorized('unauthorized', 'Provider authorization failed'),
  notEntitled('not_entitled', 'Account lacks VPN entitlement'),
  quotaExhausted('quota_exhausted', 'Quota exhausted'),
  regionUnavailable('region_unavailable', 'Service unavailable in this region'),
  redirectRefused('redirect_refused', 'Redirect refused'),
  cancelled('cancelled', 'Cancelled'),
  sessionRequired('session_required', 'Sign-in required'),
  sessionStorage('session_storage', 'Session storage unavailable');

  const OnlineDiagnosticsReason(this.code, this.label);

  final String code;
  final String label;

  static OnlineDiagnosticsReason? parse(Object? value) {
    for (final reason in values) {
      if (reason.code == value) return reason;
    }
    return null;
  }
}

class OnlineDiagnosticsState {
  const OnlineDiagnosticsState._({
    required this.stage,
    this.httpStatus,
    this.reason,
    this.quota,
  });

  final OnlineDiagnosticsStage stage;
  final int? httpStatus;
  final OnlineDiagnosticsReason? reason;
  final OnlineDiagnosticsQuota? quota;

  static OnlineDiagnosticsState? tryParse(Object? reply) {
    if (reply is! Map<Object?, Object?> || reply['enabled'] != true) {
      return null;
    }
    final stage = OnlineDiagnosticsStage.parse(reply['stage']);
    if (stage == null) return null;
    final status = reply['httpStatus'];
    return OnlineDiagnosticsState._(
      stage: stage,
      httpStatus: status is int && status >= 100 && status <= 599
          ? status
          : null,
      reason: OnlineDiagnosticsReason.parse(reply['reason']),
      quota: OnlineDiagnosticsQuota.tryParse(reply['quota']),
    );
  }
}

class OnlineDiagnosticsQuota {
  const OnlineDiagnosticsQuota._({this.limit, this.remaining});

  final int? limit;
  final int? remaining;

  bool get unlimited => limit == null;

  static OnlineDiagnosticsQuota? tryParse(Object? value) {
    if (value is! Map<Object?, Object?>) return null;
    final limit = value['limit'];
    final remaining = value['remaining'];
    if (value['unlimited'] == true && limit == null && remaining == null) {
      return const OnlineDiagnosticsQuota._();
    }
    if (value['unlimited'] == false &&
        limit is int &&
        limit >= 0 &&
        remaining is int &&
        remaining >= 0 &&
        remaining <= limit) {
      return OnlineDiagnosticsQuota._(limit: limit, remaining: remaining);
    }
    return null;
  }
}
