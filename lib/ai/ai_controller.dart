import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/bursa_stocks.dart';
import '../services/app_state.dart';
import 'ai_config.dart';
import 'app_tools.dart';
import 'claude_client.dart';

enum AiPage { chat, settings, login }

enum PartKind { text, thinking, tool, notice }

/// One visual piece of an assistant reply.
class ChatPart {
  final PartKind kind;
  String text;
  String? toolName;
  String? toolId;
  bool running;
  bool failed;
  ChatPart.text([this.text = '']) : kind = PartKind.text, running = false, failed = false;
  ChatPart.thinking([this.text = '']) : kind = PartKind.thinking, running = true, failed = false;
  ChatPart.tool(this.toolName, this.toolId, this.text) : kind = PartKind.tool, running = true, failed = false;
  ChatPart.notice(this.text, {this.failed = false}) : kind = PartKind.notice, running = false;
}

class ChatMessage {
  final bool fromUser;
  final List<ChatPart> parts;
  ChatMessage.user(String text) : fromUser = true, parts = [ChatPart.text(text)];
  ChatMessage.assistant() : fromUser = false, parts = [];
  String get plainText => parts.where((p) => p.kind == PartKind.text).map((p) => p.text).join('\n\n');
}

const _systemPrompt = '''
You are CKS AI, the assistant built into "CKS Stock Analyser", an Android app for the Bursa Malaysia stock market.

You help the user understand Malaysian stocks: prices, trends, technical analysis, comparisons and market conditions. Prefer the app's tools for any market data; never invent prices or indicator values. When the user names a company, resolve it with search_stocks if you are unsure of its 4-digit code. Use web search (when available) for news, announcements, results and fundamentals that the app's tools don't cover, and cite sources briefly.

Conventions:
- Prices are in Ringgit (RM) and may be delayed about 15 minutes. Times are Malaysia time (MYT, UTC+8).
- Bursa counters are identified by 4-digit codes, e.g. 1155 = Maybank. The FBM KLCI index is ^KLSE.
- The screen is a phone or tablet chat panel: be concise, lead with the answer, use short paragraphs, bullet points and small markdown tables. Avoid long preambles.
- Do not change the user's watchlist unless they ask.
- This is information, not financial advice. When you give a view on a stock, mention the main risks, and say so briefly if the data is limited.
''';

/// Drives the chat overlay and the Claude agent loop.
class AiController extends ChangeNotifier {
  AiController._() {
    AppTools.onNavigate = () => open = false;
  }
  static final AiController instance = AiController._();

  final ClaudeClient _client = ClaudeClient();
  final List<Map<String, dynamic>> _history = [];
  final List<ChatMessage> messages = [];

  bool _open = false;
  AiPage _page = AiPage.chat;
  bool busy = false;
  String? status;

  bool get open => _open;
  set open(bool v) {
    if (_open == v) return;
    _open = v;
    notifyListeners();
  }

  AiPage get page => !AiConfig.instance.signedIn ? AiPage.login : _page;
  set page(AiPage p) {
    _page = p;
    notifyListeners();
  }

  void toggle() => open = !_open;

  void show({AiPage page = AiPage.chat}) {
    _page = page;
    _open = true;
    notifyListeners();
  }

  void newChat() {
    if (busy) stop();
    _history.clear();
    messages.clear();
    status = null;
    notifyListeners();
  }

  void stop() {
    _client.cancel();
  }

  String _contextNote() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final viewing = AppState.instance.viewingSymbol;
    final known = viewing == null ? null : findKnown(viewing);
    final parts = [
      'Current time: ${now.toIso8601String().substring(0, 16)} MYT',
      if (viewing != null) 'User is viewing: $viewing${known != null ? ' (${known.name})' : ''}',
      'Watchlist: ${AppState.instance.watchlist.join(', ')}',
    ];
    return '<app_context>\n${parts.join('\n')}\n</app_context>';
  }

  List<Map<String, dynamic>> _tools(AiConfig cfg) {
    final tools = <Map<String, dynamic>>[
      for (final d in AppTools.definitions) {...d, 'eager_input_streaming': true},
    ];
    if (cfg.webTools) {
      final m = cfg.model;
      final dynamicFiltering = RegExp(r'claude-(opus-(5|4-[678])|sonnet-(5|4-6)|fable)').hasMatch(m);
      tools.add({
        'type': dynamicFiltering ? 'web_search_20260209' : 'web_search_20250305',
        'name': 'web_search',
        'max_uses': 5,
      });
      if (!m.contains('haiku-4')) {
        tools.add({
          'type': dynamicFiltering ? 'web_fetch_20260209' : 'web_fetch_20250910',
          'name': 'web_fetch',
          'max_uses': 5,
        });
      }
    }
    for (final s in cfg.mcpServers.where((s) => s.enabled)) {
      tools.add({'type': 'mcp_toolset', 'mcp_server_name': s.name});
    }
    return tools;
  }

  static const _fallbackModels = {'claude-fable-5-1', 'claude-opus-5-5', 'claude-opus-5', 'claude-sonnet-5-5'};

  Future<void> send(String text) async {
    final cfg = AiConfig.instance;
    final key = cfg.apiKey;
    if (busy || text.trim().isEmpty || key == null) return;
    busy = true;
    messages.add(ChatMessage.user(text.trim()));
    final reply = ChatMessage.assistant();
    messages.add(reply);
    status = 'Thinking…';
    notifyListeners();

    final userBlocks = [
      {'type': 'text', 'text': _contextNote()},
      {'type': 'text', 'text': text.trim()},
    ];
    // Keep roles alternating: if an interrupted turn left a trailing user message, extend it.
    if (_history.isNotEmpty && _history.last['role'] == 'user') {
      (_history.last['content'] as List).addAll(userBlocks);
    } else {
      _history.add({'role': 'user', 'content': userBlocks});
    }

    try {
      for (var step = 0; step < 20; step++) {
        final info = cfg.modelInfo;
        final mcp = cfg.mcpServers.where((s) => s.enabled).toList();
        final useFallbacks = _fallbackModels.contains(cfg.model);
        final body = <String, dynamic>{
          'model': cfg.model,
          'max_tokens': 32000,
          'system': _systemPrompt,
          'tools': _tools(cfg),
          'messages': _history,
          'cache_control': {'type': 'ephemeral'},
          if (info == null || info.adaptiveThinking) 'thinking': {'type': 'adaptive', 'display': 'summarized'},
          if (info != null && info.effortLevels.contains(cfg.effort)) 'output_config': {'effort': cfg.effort},
          if (useFallbacks) 'fallbacks': 'default',
          if (mcp.isNotEmpty)
            'mcp_servers': [
              for (final s in mcp)
                {
                  'type': 'url',
                  'url': s.url,
                  'name': s.name,
                  if ((s.token ?? '').isNotEmpty) 'authorization_token': s.token,
                },
            ],
        };
        final betas = [
          if (useFallbacks) 'server-side-fallback-2026-07-01',
          if (mcp.isNotEmpty) 'mcp-client-2025-11-20',
        ];

        final partsByIndex = <int, ChatPart>{};
        final result = await _client.stream(
          key: key,
          body: body,
          betas: betas,
          handlers: StreamHandlers(
            onBlockStart: (i, b) {
              final part = _partFor(b);
              if (part != null) {
                partsByIndex[i] = part;
                reply.parts.add(part);
              }
              _completeServerTool(reply, b);
              status = switch (b['type']) {
                'thinking' || 'redacted_thinking' => 'Thinking…',
                'text' => null,
                _ => status,
              };
              notifyListeners();
            },
            onBlockUpdate: (i, b) {
              final part = partsByIndex[i];
              if (part == null) return;
              if (part.kind == PartKind.text) part.text = (b['text'] ?? '') as String;
              if (part.kind == PartKind.thinking) part.text = (b['thinking'] ?? '') as String;
              notifyListeners();
            },
            onBlockStop: (i, b) {
              final part = partsByIndex[i];
              if (part == null) return;
              if (part.kind == PartKind.thinking) part.running = false;
              if (part.kind == PartKind.tool && b['input'] is Map) {
                part.text = AppTools.label(part.toolName!, (b['input'] as Map).cast<String, dynamic>());
              }
              notifyListeners();
            },
          ),
        );

        _history.add({'role': 'assistant', 'content': _echoable(result.content)});

        switch (result.stopReason) {
          case 'tool_use':
            status = 'Working…';
            notifyListeners();
            final results = await _runTools(result.content, reply);
            _history.add({'role': 'user', 'content': results});
            continue;
          case 'pause_turn':
            continue;
          case 'refusal':
            reply.parts.add(ChatPart.notice('Claude declined to answer this request.', failed: true));
            _closeDanglingTools();
          case 'max_tokens':
            reply.parts.add(ChatPart.notice('The reply hit the length limit. Ask me to continue.'));
            _closeDanglingTools();
        }
        break;
      }
    } catch (e) {
      if (isCancellation(e)) {
        reply.parts.add(ChatPart.notice('Stopped.'));
      } else {
        reply.parts.add(ChatPart.notice('$e', failed: true));
        if (e is ClaudeApiException && e.status == 401) {
          reply.parts.add(ChatPart.notice('Your API key was rejected. Sign in again in AI settings.', failed: true));
        }
      }
      _closeDanglingTools();
    } finally {
      for (final p in reply.parts) {
        if (p.running) {
          p.running = false;
        }
      }
      busy = false;
      status = null;
      notifyListeners();
    }
  }

  ChatPart? _partFor(Map<String, dynamic> b) {
    switch (b['type']) {
      case 'text':
        return ChatPart.text((b['text'] ?? '') as String);
      case 'thinking':
        return ChatPart.thinking((b['thinking'] ?? '') as String);
      case 'tool_use':
      case 'server_tool_use':
        final name = b['name'].toString();
        return ChatPart.tool(name, b['id']?.toString(), AppTools.label(name, const {}));
      case 'mcp_tool_use':
        return ChatPart.tool(b['name'].toString(), b['id']?.toString(), '${b['server_name'] ?? 'MCP'}: ${b['name']}');
    }
    return null;
  }

  /// Server-side tool results arrive whole in content_block_start.
  void _completeServerTool(ChatMessage reply, Map<String, dynamic> b) {
    final type = b['type']?.toString() ?? '';
    if (!type.endsWith('_tool_result')) return;
    final id = b['tool_use_id']?.toString();
    for (final p in reply.parts) {
      if (p.kind == PartKind.tool && p.toolId == id) {
        p.running = false;
        final c = b['content'];
        p.failed = b['is_error'] == true || (c is Map && c['type']?.toString().endsWith('_error') == true);
      }
    }
  }

  /// Drops model-internal blocks that preceded a mid-output fallback (they
  /// can't be echoed), and our private parsing markers.
  List<Map<String, dynamic>> _echoable(List<Map<String, dynamic>> content) {
    final lastFallback = content.lastIndexWhere((b) => b['type'] == 'fallback');
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < content.length; i++) {
      final b = Map<String, dynamic>.from(content[i])..remove('_invalid_input');
      if (i < lastFallback) {
        const internal = {'thinking', 'redacted_thinking', 'tool_use', 'server_tool_use', 'mcp_tool_use'};
        if (internal.contains(b['type'])) continue;
      }
      out.add(b);
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _runTools(List<Map<String, dynamic>> content, ChatMessage reply) async {
    final calls = content.where((b) => b['type'] == 'tool_use').toList();
    return Future.wait(
      calls.map((b) async {
        final id = b['id'].toString();
        final name = b['name'].toString();
        final part = reply.parts.where((p) => p.toolId == id).firstOrNull;
        String output;
        var isError = false;
        if (b['_invalid_input'] != null) {
          output = 'INVALID_JSON: could not parse tool input: ${b['_invalid_input']}';
          isError = true;
        } else if (!AppTools.isAppTool(name)) {
          output = 'Unknown tool $name';
          isError = true;
        } else {
          try {
            output = await AppTools.run(name, (b['input'] as Map).cast<String, dynamic>());
          } catch (e) {
            output = jsonEncode({'error': '$e'});
            isError = true;
          }
        }
        if (part != null) {
          part.running = false;
          part.failed = isError;
        }
        notifyListeners();
        return {'type': 'tool_result', 'tool_use_id': id, 'content': output, if (isError) 'is_error': true};
      }),
    );
  }

  /// If the last assistant turn asked for tools that never ran (stopped,
  /// refused or truncated), answer them so the history stays valid.
  void _closeDanglingTools() {
    if (_history.isEmpty || _history.last['role'] != 'assistant') return;
    final pending = (_history.last['content'] as List).where((b) => b is Map && b['type'] == 'tool_use').toList();
    if (pending.isEmpty) return;
    _history.add({
      'role': 'user',
      'content': [
        for (final b in pending)
          {
            'type': 'tool_result',
            'tool_use_id': (b as Map)['id'],
            'content': 'Not run: the turn was interrupted.',
            'is_error': true,
          },
      ],
    });
  }

  /// Verifies a key by listing models; saves it on success.
  Future<void> signIn(String key) async {
    final models = await _client.listModels(key.trim());
    await AiConfig.instance.setApiKey(key.trim());
    AiConfig.instance.setModels(models);
    _page = AiPage.chat;
    notifyListeners();
  }

  Future<void> refreshModels() async {
    final key = AiConfig.instance.apiKey;
    if (key == null) return;
    AiConfig.instance.setModels(await _client.listModels(key));
  }

  Future<void> signOut() async {
    newChat();
    await AiConfig.instance.setApiKey(null);
    notifyListeners();
  }
}
