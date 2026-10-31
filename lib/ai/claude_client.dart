import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_config.dart';

class ClaudeApiException implements Exception {
  final int? status;
  final String message;
  ClaudeApiException(this.message, {this.status});
  @override
  String toString() => message;
}

/// Callbacks fired while a streamed response arrives.
class StreamHandlers {
  final void Function(int index, Map<String, dynamic> block)? onBlockStart;
  final void Function(int index, Map<String, dynamic> block)? onBlockUpdate;
  final void Function(int index, Map<String, dynamic> block)? onBlockStop;
  const StreamHandlers({this.onBlockStart, this.onBlockUpdate, this.onBlockStop});
}

class StreamResult {
  final List<Map<String, dynamic>> content;
  final String? stopReason;
  final Map<String, dynamic>? stopDetails;
  final String? model;
  const StreamResult(this.content, this.stopReason, this.stopDetails, this.model);
}

/// Minimal Claude Messages API client over raw HTTP + SSE (there is no
/// official Dart SDK).
class ClaudeClient {
  /// Overridable for tests.
  static String base = 'https://api.anthropic.com';
  static const apiVersion = '2026-10-21';

  http.Client? _active;

  Map<String, String> _headers(String key, {List<String> betas = const []}) => {
    'content-type': 'application/json',
    'x-api-key': key,
    'anthropic-version': apiVersion,
    if (betas.isNotEmpty) 'anthropic-beta': betas.join(','),
  };

  static String _errorMessage(int status, String body) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      final m = (j['error'] as Map?)?['message'];
      if (m != null) return '$m';
    } catch (_) {}
    return switch (status) {
      401 => 'Invalid API key',
      403 => 'This API key does not have permission for that',
      429 => 'Rate limited. Wait a moment and try again',
      529 => 'Claude is overloaded right now. Try again shortly',
      _ => 'Request failed ($status)',
    };
  }

  /// Lists every model the key can use (follows pagination).
  Future<List<ModelInfo>> listModels(String key) async {
    final out = <ModelInfo>[];
    String? after;
    final client = http.Client();
    try {
      for (var page = 0; page < 10; page++) {
        final uri = Uri.parse('$base/v1/models').replace(queryParameters: {'limit': '100', 'after_id': ?after});
        final res = await client.get(uri, headers: _headers(key)).timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) {
          throw ClaudeApiException(_errorMessage(res.statusCode, res.body), status: res.statusCode);
        }
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        for (final m in (j['data'] as List? ?? const [])) {
          out.add(ModelInfo.fromApi((m as Map).cast<String, dynamic>()));
        }
        if (j['has_more'] != true) break;
        after = j['last_id']?.toString();
      }
    } on TimeoutException {
      throw ClaudeApiException('Connection timed out');
    } finally {
      client.close();
    }
    return out;
  }

  /// Streams one Messages API call, reassembling content blocks.
  Future<StreamResult> stream({
    required String key,
    required Map<String, dynamic> body,
    List<String> betas = const [],
    StreamHandlers handlers = const StreamHandlers(),
  }) async {
    final client = http.Client();
    _active = client;
    final blocks = <int, Map<String, dynamic>>{};
    final partialJson = <int, StringBuffer>{};
    String? stopReason, model;
    Map<String, dynamic>? stopDetails;
    try {
      final req = http.Request('POST', Uri.parse('$base/v1/messages'))
        ..headers.addAll(_headers(key, betas: betas))
        ..body = jsonEncode({...body, 'stream': true});
      final res = await client.send(req).timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) {
        final text = await res.stream.bytesToString();
        throw ClaudeApiException(_errorMessage(res.statusCode, text), status: res.statusCode);
      }
      await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data.isEmpty) continue;
        final ev = jsonDecode(data) as Map<String, dynamic>;
        switch (ev['type']) {
          case 'message_start':
            model = (ev['message'] as Map?)?['model']?.toString();
          case 'content_block_start':
            final i = ev['index'] as int;
            final b = Map<String, dynamic>.from(ev['content_block'] as Map);
            blocks[i] = b;
            handlers.onBlockStart?.call(i, b);
          case 'content_block_delta':
            final i = ev['index'] as int;
            final b = blocks[i];
            if (b == null) break;
            final d = (ev['delta'] as Map).cast<String, dynamic>();
            switch (d['type']) {
              case 'text_delta':
                b['text'] = '${b['text'] ?? ''}${d['text']}';
              case 'thinking_delta':
                b['thinking'] = '${b['thinking'] ?? ''}${d['thinking']}';
              case 'signature_delta':
                b['signature'] = d['signature'];
              case 'input_json_delta':
                (partialJson[i] ??= StringBuffer()).write(d['partial_json'] ?? '');
              case 'citations_delta':
                (b['citations'] ??= <dynamic>[]) as List;
                (b['citations'] as List).add(d['citation']);
            }
            handlers.onBlockUpdate?.call(i, b);
          case 'content_block_stop':
            final i = ev['index'] as int;
            final b = blocks[i];
            if (b == null) break;
            final pj = partialJson.remove(i);
            if (pj != null) {
              final raw = pj.toString();
              try {
                b['input'] = raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw);
              } catch (_) {
                // Invalid tool JSON: keep the raw text so the caller can report it.
                b['input'] = <String, dynamic>{};
                b['_invalid_input'] = raw;
              }
            }
            handlers.onBlockStop?.call(i, b);
          case 'message_delta':
            final d = (ev['delta'] as Map?)?.cast<String, dynamic>() ?? const {};
            stopReason = d['stop_reason']?.toString() ?? stopReason;
            if (d['stop_details'] is Map) stopDetails = (d['stop_details'] as Map).cast<String, dynamic>();
          case 'error':
            final err = (ev['error'] as Map?)?.cast<String, dynamic>() ?? const {};
            throw ClaudeApiException('${err['message'] ?? 'Stream error'}');
        }
      }
    } on TimeoutException {
      throw ClaudeApiException('Connection timed out');
    } on http.ClientException catch (e) {
      if (_active == null) throw const _Cancelled();
      throw ClaudeApiException('Network error: ${e.message}');
    } finally {
      if (identical(_active, client)) _active = null;
      client.close();
    }
    final keys = blocks.keys.toList()..sort();
    return StreamResult([for (final k in keys) blocks[k]!], stopReason, stopDetails, model);
  }

  /// Aborts the in-flight request.
  void cancel() {
    final c = _active;
    _active = null;
    c?.close();
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

bool isCancellation(Object e) => e is _Cancelled;
