import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'ai_controller.dart';
import 'app_tools.dart';
import '../l10n.dart';

/// The CKS AI chat page, hosted on claude.ai. It runs on the signed-in
/// viewer's own Claude plan (no API key) and reaches the app's market tools
/// through the `CksBridge` JavaScript channel.
const claudeChatUrl = 'https://claude.ai/artifact/Fw3oDijVjE9ZUPiE3dDQTZ';

/// Google and Apple block their sign-in pop-ups inside apps' browsers.
bool _socialLogin(Uri u) =>
    u.host == 'accounts.google.com' || u.host.endsWith('.google.com') || u.host == 'appleid.apple.com';

String get _useEmailNotice => t(
  t(
    t(
      'Google and Apple sign-in don\'t work inside apps. Tap "Continue with email", then enter the code from Claude\'s email, or copy the sign-in link from the email and tap "Paste sign-in link" below.',
    ),
  ),
);

/// Hosts the in-app browser may navigate to; anything else opens outside.
bool _allowedHost(String host) {
  const exact = {'claude.ai', 'claude.com'};
  const suffixes = ['.claude.ai', '.claude.com', '.claudeusercontent.com', '.anthropic.com'];
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
  String? _notice;

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
            final cu = Uri.tryParse(c.url!);
            if (cu != null && _socialLogin(cu)) {
              _blockSocialLogin();
              return;
            }
            _returnToChat(c.url!);
          },
          onWebResourceError: (e) {
            _log('error ${e.errorCode} ${e.description} ${e.url ?? ''}');
            if (e.isForMainFrame == true && mounted) {
              setState(() => _error = tf('Could not load Claude ({e}). Check your connection.', {'e': e.description}));
            }
          },
          onNavigationRequest: (req) {
            final uri = Uri.tryParse(req.url);
            if (uri == null) return NavigationDecision.prevent;
            if (_socialLogin(uri)) {
              _blockSocialLogin();
              return NavigationDecision.prevent;
            }
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
  /// user back to the CKS chat page. Only from claude.ai's home/chat-list
  /// pages, and at most once a minute, so it can never loop.
  DateTime? _lastReturn;
  void _returnToChat(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.host != 'claude.ai' && uri.host != 'www.claude.ai')) return;
    final path = uri.path.replaceAll(RegExp(r'/+$'), '');
    final home = path.isEmpty || path == '/new' || path == '/recents' || path == '/chats' || path == '/projects';
    if (!home) return;
    final now = DateTime.now();
    if (_lastReturn != null && now.difference(_lastReturn!) < const Duration(minutes: 1)) return;
    _lastReturn = now;
    _log('back to chat from ${path.isEmpty ? '/' : path}');
    _web.loadRequest(Uri.parse(claudeChatUrl));
  }

  void _blockSocialLogin() {
    _log('blocked Google/Apple sign-in');
    if (mounted) setState(() => _notice = _useEmailNotice);
    _web.loadRequest(
      Uri.parse('https://claude.ai/login?returnTo=${Uri.encodeComponent('/artifact/Fw3oDijVjE9ZUPiE3dDQTZ')}'),
    );
  }

  /// Opens a claude.ai sign-in link the user copied from Claude's email.
  Future<void> pasteSignInLink() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
    final match = RegExp(r'https://(www\.)?claude\.ai/\S+').firstMatch(text);
    if (match == null) {
      setState(
        () => _notice = t(
          t(
            t(
              'No claude.ai link on the clipboard. In Claude\'s sign-in email, long-press the sign-in button or link, choose "Copy link address", then tap "Paste sign-in link" again.',
            ),
          ),
        ),
      );
      return;
    }
    setState(() => _notice = null);
    _log('opening pasted sign-in link');
    _web.loadRequest(Uri.parse(match.group(0)!));
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
      '(function(m){function s(w){try{w.postMessage(m,"*")}catch(e){}try{for(var i=0;i<w.frames.length;i++)s(w.frames[i])}catch(e){}}s(window)})($msg);',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        Positioned.fill(
          bottom: 30,
          child: _web.platform is AndroidWebViewController
              // Hybrid composition draws reliably on more Android GPUs than the
              // default texture mode (which can show a blank white view).
              ? WebViewWidget.fromPlatformCreationParams(
                  params: AndroidWebViewWidgetCreationParams(
                    controller: _web.platform,
                    displayWithHybridComposition: true,
                  ),
                )
              : WebViewWidget(controller: _web),
        ),
        Positioned(left: 0, right: 0, bottom: 0, height: 30, child: _StatusStrip(state: this)),
        if (_notice != null)
          Positioned(
            left: 8,
            right: 8,
            top: 8,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(14),
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Theme.of(context).colorScheme.onTertiaryContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_notice!, style: TextStyle(color: Theme.of(context).colorScheme.onTertiaryContainer)),
                    ),
                    IconButton(
                      tooltip: t('Dismiss'),
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _notice = null),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
                      FilledButton.tonal(onPressed: reload, child: Text(t('Retry'))),
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

/// One line under the chat: where the page is and whether it reached the app.
class _StatusStrip extends StatelessWidget {
  final ClaudeWebChatState state;
  const _StatusStrip({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: AiController.instance,
      builder: (context, _) {
        final u = Uri.tryParse(state.url ?? '');
        final where = u == null || u.host.isEmpty ? t('loading…') : '${u.host}${u.path}';
        final problem = state.console.reversed.firstWhere(
          (l) => l.contains('error') || l.contains('console.error'),
          orElse: () => '',
        );
        final text = [
          where,
          state.bridgeSeen ? t('app linked') : t('app not linked'),
          if (problem.isNotEmpty) problem.substring(9),
        ].join(' · ');
        return Container(
          color: theme.colorScheme.surfaceContainer,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Icon(Icons.circle, size: 8, color: state.bridgeSeen ? Colors.green : theme.colorScheme.outline),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              if (!state.bridgeSeen)
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 22),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  onPressed: state.pasteSignInLink,
                  child: Text(t('Paste sign-in link')),
                ),
            ],
          ),
        );
      },
    );
  }
}
