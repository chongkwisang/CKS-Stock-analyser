import 'dart:convert';
import 'dart:io';

import 'package:cks_stock_analyser/ai/ai_config.dart';
import 'package:cks_stock_analyser/ai/ai_controller.dart';
import 'package:cks_stock_analyser/ai/claude_client.dart';
import 'package:cks_stock_analyser/services/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String sse(List<Map<String, dynamic>> events) =>
    events.map((e) => 'event: ${e['type']}\ndata: ${jsonEncode(e)}\n\n').join();

void main() {
  test('agent loop: thinking + tool_use -> tool_result -> final text', () async {
    SharedPreferences.setMockInitialValues({});
    await AppState.instance.load();
    await AiConfig.instance.load();
    AiConfig.instance.debugSetKey('sk-test');

    final bodies = <Map<String, dynamic>>[];
    final headers = <HttpHeaders>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    ClaudeClient.base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      bodies.add(jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>);
      headers.add(req.headers);
      req.response.headers.contentType = ContentType('text', 'event-stream');
      if (bodies.length == 1) {
        req.response.write(sse([
          {'type': 'message_start', 'message': {'id': 'm1', 'model': 'claude-opus-5-5'}},
          {'type': 'content_block_start', 'index': 0, 'content_block': {'type': 'thinking', 'thinking': ''}},
          {'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'thinking_delta', 'thinking': 'Need watchlist.'}},
          {'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'signature_delta', 'signature': 'sig123'}},
          {'type': 'content_block_stop', 'index': 0},
          {'type': 'content_block_start', 'index': 1, 'content_block': {'type': 'tool_use', 'id': 'toolu_1', 'name': 'update_watchlist', 'input': {}}},
          {'type': 'content_block_delta', 'index': 1, 'delta': {'type': 'input_json_delta', 'partial_json': '{"action": "add", '}},
          {'type': 'content_block_delta', 'index': 1, 'delta': {'type': 'input_json_delta', 'partial_json': '"symbol": "7084"}'}},
          {'type': 'content_block_stop', 'index': 1},
          {'type': 'message_delta', 'delta': {'stop_reason': 'tool_use'}},
          {'type': 'message_stop'},
        ]));
      } else {
        req.response.write(sse([
          {'type': 'message_start', 'message': {'id': 'm2', 'model': 'claude-opus-5-5'}},
          {'type': 'content_block_start', 'index': 0, 'content_block': {'type': 'text', 'text': ''}},
          {'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'text_delta', 'text': 'Added **QL** '}},
          {'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'text_delta', 'text': 'to your watchlist.'}},
          {'type': 'content_block_stop', 'index': 0},
          {'type': 'message_delta', 'delta': {'stop_reason': 'end_turn'}},
          {'type': 'message_stop'},
        ]));
      }
      await req.response.close();
    });

    final ai = AiController.instance;
    await ai.send('Add QL to my watchlist');
    await server.close(force: true);

    expect(bodies.length, 2);
    expect(bodies.first['model'], 'claude-opus-5-5');
    expect(bodies.first['fallbacks'], 'default');
    expect(headers.first.value('anthropic-beta'), contains('server-side-fallback-2026-07-01'));
    expect(headers.first.value('anthropic-version'), '2026-10-21');
    expect(headers.first.value('x-api-key'), 'sk-test');
    final tools = (bodies.first['tools'] as List).cast<Map>();
    expect(tools.any((t) => t['type'] == 'web_search_20260209'), isTrue);

    final msgs = (bodies[1]['messages'] as List).cast<Map>();
    expect(msgs.map((m) => m['role']).toList(), ['user', 'assistant', 'user']);
    final assistant = (msgs[1]['content'] as List).cast<Map>();
    expect(assistant[0]['type'], 'thinking');
    expect(assistant[0]['signature'], 'sig123', reason: 'thinking blocks must be echoed unchanged');
    expect(assistant[1]['input'], {'action': 'add', 'symbol': '7084'});
    final result = (msgs[2]['content'] as List).cast<Map>().single;
    expect(result['tool_use_id'], 'toolu_1');
    expect(result['is_error'], isNull, reason: '${result['content']}');

    expect(AppState.instance.isWatched('7084.KL'), isTrue);
    expect(ai.messages.last.plainText, 'Added **QL** to your watchlist.');
    expect(ai.busy, isFalse);
  });
}
