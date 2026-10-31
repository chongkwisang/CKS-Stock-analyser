import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'ai_controller.dart';
import 'app_tools.dart';

/// The CKS AI chat page, hosted on claude.ai. It runs on the signed-in
/// viewer's own Claude plan (no API key) and reaches the app's market tools
/// through the `CksBridge` JavaScript channel.
const claudeChatUrl = 'https://claude.ai/artifact/Fw3oDijVjE9ZUPiE3dDQTZ';

/// Hosts the in-app browser may navigate to; anything else opens outside.
bool _allowedHost(String host) {
  const exact = {'claude.ai', 'claude.com', 'accounts.google.com', 'appleid.apple.com'};
  const suffixes = [
    '.claude.ai',
    '.claude.com',
    '.claudeusercontent.com',
    '.anthropic.com',
    '.google.com',
    '.gstatic.com',
    '.apple.com',
  ];
  return exact.contains(host) || host == 'anthropic.com' || suffixes.any(host.endsWith);
}

class ClaudeWebChat extends StatefulWidget {
  const ClaudeWebChat({super.key});
  @override
  State<ClaudeWebChat> createState() => ClaudeWebChatState();
}

class ClaudeWebChatState extends State<ClaudeWebChat> {
  late final WebViewController _web;
  int _progress = 0;
  String? _error;

  // Diagnostics, shown in AI settings.
  String? url;
  String? title;
  bool bridgeSeen = false;
  final List<String> console = [];

  void _log(String line) {
    final t = DateTime.now();
    console.add(
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')} $line',
    );
    if (console.length > 40) console.removeAt(0);
    AiController.instance.notifyDiagnostics();
  }

  @override
  void initState() {
    super.initState();
    AiController.instance.webChat = this;
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('CksBridge', onMessageReceived: _onBridge)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _error = null);
          },
          onPageFinished: (u) async {
            url = u;
            title = await _web.getTitle();
            _log('loaded $u');
            _returnToChat(u);
          },
          onUrlChange: (c) {
            if (c.url == null) return;
            url = c.url;
            _log('url ${c.url}');
            _returnToChat(c.url!);
          },
          onWebResourceError: (e) {
            _log('error ${e.errorCode} ${e.description} ${e.url ?? ''}');
            if (e.isForMainFrame == true && mounted) {
              setState(() => _error = 'Could not load Claude (${e.description}). Check your connection.');
            }
          },
          onNavigationRequest: (req) {
            final uri = Uri.tryParse(req.url);
            if (uri == null) return NavigationDecision.prevent;
            if (!req.isMainFrame) return NavigationDecision.navigate;
            if ((uri.scheme == 'https' || uri.scheme == 'http') && _allowedHost(uri.host)) {
              return NavigationDecision.navigate;
            }
            launchUrl(uri, mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          },
        ),
      );
    _web.setOnConsoleMessage((m) => _log('console.${m.level.name}: ${m.message}'));
    final platform = _web.platform;
    if (platform is AndroidWebViewController) {
      // The chat page is served from a claude.ai sub-frame; it needs its cookies.
      AndroidWebViewCookieManager(const PlatformWebViewCookieManagerCreationParams())
          .setAcceptThirdPartyCookies(platform, true);
      platform.setMediaPlaybackRequiresUserGesture(true);
    }
    _web.loadRequest(Uri.parse(claudeChatUrl));
  }

  @override
  void dispose() {
    if (AiController.instance.webChat == this) AiController.instance.webChat = null;
    super.dispose();
  }

  /// After signing in, claude.ai lands on its own home page; bring the
  /// user back to the CKS chat page.
  void _returnToChat(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.host != 'claude.ai' && uri.host != 'www.claude.ai')) return;
    final path = uri.path;
    const stay = ['/artifact', '/login', '/logout', '/magic-link', '/oauth', '/verify', '/sso', '/onboarding', '/api'];
    if (stay.any(path.startsWith)) return;
    _log('back to chat from $path');
    _web.loadRequest(Uri.parse(claudeChatUrl));
  }

  void reload() {
    setState(() => _error = null);
    _web.loadRequest(Uri.parse(claudeChatUrl));
  }

  Future<void> signOut() async {
    await WebViewCookieManager().clearCookies();
    await _web.clearLocalStorage();
    await _web.clearCache();
    reload();
  }

  /// A tool call from the chat page: {id, tool, input}.
  Future<void> _onBridge(JavaScriptMessage message) async {
    String? id;
    var ok = true;
    String output;
    try {
      final req = jsonDecode(message.message) as Map<String, dynamic>;
      id = req['id']?.toString();
      final tool = req['tool']?.toString() ?? '';
      final input = (req['input'] is Map) ? (req['input'] as Map).cast<String, dynamic>() : <String, dynamic>{};
      if (tool == 'hello') {
        bridgeSeen = true;
        _log('bridge connected');
        return;
      } else if (tool == 'get_app_context') {
        output = AiController.instance.appContext();
      } else if (AppTools.isAppTool(tool)) {
        output = await AppTools.run(tool, input);
      } else {
        ok = false;
        output = 'Unknown tool $tool';
      }
    } catch (e) {
      ok = false;
      output = '$e';
    }
    if (id == null) return;
    final msg = jsonEncode({'cks': 'result', 'id': id, 'ok': ok, 'output': output});
    // The chat page lives in a nested claude.ai frame: deliver to every frame;
    // the page only accepts results for ids it is waiting on.
    await _web.runJavaScript(
      '(function(m){function s(w){try{w.postMessage(m,"*")}catch(e){}'
      'try{for(var i=0;i<w.frames.length;i++)s(w.frames[i])}catch(e){}}s(window)})($msg);',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        Positioned.fill(child: WebViewWidget(controller: _web)),
        if (_progress < 100)
          Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(value: _progress / 100, minHeight: 2)),
        if (_error != null)
          Positioned.fill(
            child: ColoredBox(
              color: theme.colorScheme.surfaceContainerLow,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off, size: 40),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton.tonal(onPressed: reload, child: const Text('Retry')),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
