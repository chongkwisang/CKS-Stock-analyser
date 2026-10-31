import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_state.dart';
import 'ai_config.dart';
import 'ai_controller.dart';
import 'app_tools.dart';
import 'claude_web.dart';

/// Wraps the whole app (above the Navigator) with the floating Claude
/// button and the chat panel that expands from it.
class AiOverlay extends StatefulWidget {
  final Widget child;
  const AiOverlay({super.key, required this.child});
  @override
  State<AiOverlay> createState() => _AiOverlayState();
}

class _AiOverlayState extends State<AiOverlay> {
  late final OverlayEntry _entry = OverlayEntry(builder: (_) => _AiStack(child: widget.child));

  @override
  void didUpdateWidget(AiOverlay old) {
    super.didUpdateWidget(old);
    if (old.child != widget.child) _entry.markNeedsBuild();
  }

  // The panel sits above the Navigator, so it gets its own Overlay for text
  // selection handles and the like.
  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}

class _AiStack extends StatefulWidget {
  final Widget child;
  const _AiStack({required this.child});
  @override
  State<_AiStack> createState() => _AiStackState();
}

class _AiStackState extends State<_AiStack> with SingleTickerProviderStateMixin {
  /// The panel is built on first open and then kept (minimised = offstage),
  /// so the claude.ai chat is not reloaded every time.
  bool _mounted = false;
  final ai = AiController.instance;
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 300),
  );

  @override
  void initState() {
    super.initState();
    ai.addListener(_sync);
  }

  void _sync() {
    if (ai.open && _anim.status != AnimationStatus.forward && _anim.value < 1) _anim.forward();
    if (!ai.open && _anim.status != AnimationStatus.reverse && _anim.value > 0) {
      FocusManager.instance.primaryFocus?.unfocus();
      _anim.reverse();
    }
  }

  @override
  void dispose() {
    ai.removeListener(_sync);
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final phone = size.width < 600;
    final fabSize = 58.0;
    final fabRight = 16.0 + mq.padding.right;
    final fabBottom = (phone ? 68 + 14 : 20) + mq.padding.bottom;
    final kb = mq.viewInsets.bottom;

    final panelW = phone ? size.width - 16 : math.min(460.0, size.width - 32);
    final panelBottom = math.max(fabBottom + fabSize + 12, kb + 8);
    final maxH = size.height - mq.padding.top - panelBottom - 8;
    final panelH = math.min(phone ? size.height * 0.82 : 720.0, maxH);

    return Stack(
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _anim,
          builder: (context, child) {
            final t = _anim.value;
            if (t > 0) _mounted = true;
            if (!_mounted) return const SizedBox.shrink();
            final curved = Curves.easeOutCubic.transform(t);
            final fade = Curves.easeOut.transform(math.min(1, t * 1.6));
            return Positioned(
              right: phone ? 8 : fabRight,
              bottom: panelBottom,
              width: panelW,
              height: panelH,
              child: Offstage(
                offstage: t == 0,
                child: IgnorePointer(
                  ignoring: !ai.open,
                  child: Opacity(
                    opacity: fade,
                    child: Transform.translate(
                      offset: Offset(0, (1 - curved) * 40),
                      child: Transform.scale(
                        scale: 0.55 + 0.45 * curved,
                        alignment: Alignment.bottomRight,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
          child: const _Panel(),
        ),
        Positioned(
          right: fabRight,
          bottom: fabBottom,
          child: _Fab(size: fabSize, anim: _anim),
        ),
      ],
    );
  }
}

class _Fab extends StatelessWidget {
  final double size;
  final Animation<double> anim;
  const _Fab({required this.size, required this.anim});

  @override
  Widget build(BuildContext context) {
    final ai = AiController.instance;
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: ai,
      builder: (context, _) => Semantics(
        button: true,
        label: ai.open ? 'Minimise Claude chat' : 'Open Claude chat',
        child: GestureDetector(
          onTap: ai.toggle,
          child: AnimatedBuilder(
            animation: anim,
            builder: (context, _) {
              final t = Curves.easeInOutCubic.transform(anim.value);
              return SizedBox(
                width: size,
                height: size,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (ai.busy)
                      SizedBox(
                        width: size + 8,
                        height: size + 8,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.tertiary),
                      ),
                    Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFD97757), Color(0xFF8E5BD9)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.28),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Transform.rotate(
                        angle: t * math.pi,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Opacity(
                              opacity: 1 - t,
                              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 26),
                            ),
                            Opacity(
                              opacity: t,
                              child: Transform.rotate(
                                angle: math.pi,
                                child: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 32),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ai = AiController.instance;
    return Material(
      color: cs.surfaceContainerLow,
      elevation: 16,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: ListenableBuilder(
        listenable: Listenable.merge([ai, AiConfig.instance]),
        builder: (context, _) => Column(
          children: [
            _Header(page: ai.page),
            const Divider(height: 1),
            Expanded(
              child: Stack(
                children: [
                  if (AiConfig.instance.useClaudeAccount)
                    Offstage(offstage: ai.page != AiPage.chat, child: const ClaudeWebChat()),
                  if (!(AiConfig.instance.useClaudeAccount && ai.page == AiPage.chat))
                    Positioned.fill(
                      child: ColoredBox(
                        color: Theme.of(context).colorScheme.surfaceContainerLow,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          transitionBuilder: (child, a) => FadeTransition(
                            opacity: a,
                            child: SlideTransition(
                              position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(a),
                              child: child,
                            ),
                          ),
                          child: switch (ai.page) {
                            AiPage.login => const _LoginPage(key: ValueKey('login')),
                            AiPage.settings => const _SettingsPage(key: ValueKey('settings')),
                            AiPage.chat => const _ChatPage(key: ValueKey('chat')),
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final AiPage page;
  const _Header({required this.page});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ai = AiController.instance;
    final cfg = AiConfig.instance;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Row(
        children: [
          if (page == AiPage.settings && cfg.signedIn)
            IconButton(
              tooltip: 'Back to chat',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => ai.page = AiPage.chat,
            )
          else
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [Color(0xFFD97757), Color(0xFF8E5BD9)]),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  page == AiPage.settings ? 'AI settings' : 'CKS AI',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (cfg.useClaudeAccount)
                  Text('Your Claude account', style: theme.textTheme.bodySmall)
                else if (cfg.signedIn)
                  GestureDetector(
                    onTap: () => ai.page = AiPage.settings,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            cfg.modelLabel,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                          ),
                        ),
                        Icon(Icons.expand_more, size: 16, color: theme.colorScheme.primary),
                      ],
                    ),
                  )
                else
                  Text('Powered by Claude', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (page == AiPage.chat) ...[
            if (cfg.useClaudeAccount)
              IconButton(tooltip: 'Reload chat', icon: const Icon(Icons.refresh), onPressed: () => ai.webChat?.reload())
            else
              IconButton(tooltip: 'New chat', icon: const Icon(Icons.add_comment_outlined), onPressed: ai.newChat),
            IconButton(
              tooltip: 'AI settings',
              icon: const Icon(Icons.tune),
              onPressed: () => ai.page = AiPage.settings,
            ),
          ],
          IconButton(
            tooltip: 'Minimise',
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            onPressed: () => ai.open = false,
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Chat ─────────────────────────────

class _ChatPage extends StatefulWidget {
  const _ChatPage({super.key});
  @override
  State<_ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<_ChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final ai = AiController.instance;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    ai.addListener(_autoScroll);
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    ai.removeListener(_autoScroll);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _autoScroll() {
    if (!_scroll.hasClients) return;
    final nearBottom = _scroll.position.maxScrollExtent - _scroll.position.pixels < 160;
    final grew = ai.messages.length != _lastCount;
    _lastCount = ai.messages.length;
    if (nearBottom || grew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _send([String? text]) {
    final t = text ?? _input.text;
    if (t.trim().isEmpty) return;
    _input.clear();
    ai.send(t);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: ai, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: ai.messages.isEmpty
              ? _Welcome(onPick: _send)
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  itemCount: ai.messages.length,
                  itemBuilder: (context, i) =>
                      _Bubble(message: ai.messages[i], live: ai.busy && i == ai.messages.length - 1, status: ai.status),
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4))),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    hintText: 'Ask about any Bursa stock…',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: ai.busy
                    ? IconButton.filledTonal(
                        key: const ValueKey('stop'),
                        tooltip: 'Stop',
                        icon: const Icon(Icons.stop_rounded),
                        onPressed: ai.stop,
                      )
                    : IconButton.filled(
                        key: const ValueKey('send'),
                        tooltip: 'Send',
                        icon: const Icon(Icons.arrow_upward_rounded),
                        onPressed: _input.text.trim().isEmpty ? null : _send,
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Welcome extends StatelessWidget {
  final ValueChanged<String> onPick;
  const _Welcome({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewing = AppState.instance.viewingSymbol;
    final code = viewing?.replaceAll('.KL', '');
    final suggestions = [
      if (viewing != null) 'Analyse $code for me',
      'How is the KLCI doing today?',
      'Compare Maybank, Public Bank and CIMB',
      'Which KLCI stocks look oversold?',
      'Summarise my watchlist',
      'Latest news on Tenaga Nasional',
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 8),
        Text(
          'Hi! Ask me anything about Bursa Malaysia.',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'I can read live quotes, run technical analysis, compare stocks, manage your watchlist, open charts and search the web for news.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in suggestions)
              ActionChip(avatar: const Icon(Icons.bolt, size: 16), label: Text(s), onPressed: () => onPick(s)),
          ],
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final bool live;
  final String? status;
  const _Bubble({required this.message, required this.live, this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (message.fromUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(left: 48, bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: SelectableText(message.plainText, style: TextStyle(color: cs.onPrimaryContainer)),
        ),
      );
    }
    final children = <Widget>[];
    for (final p in message.parts) {
      switch (p.kind) {
        case PartKind.text:
          if (p.text.trim().isEmpty) continue;
          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: MarkdownBody(
                data: p.text,
                selectable: true,
                onTapLink: (_, href, _) {
                  if (href != null) launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
                },
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                  tableBody: theme.textTheme.bodySmall,
                  tableHead: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                  tableCellsPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  tableBorder: TableBorder.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                  code: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
              ),
            ),
          );
        case PartKind.thinking:
          children.add(_Thinking(part: p));
        case PartKind.tool:
          children.add(_ToolChip(part: p));
        case PartKind.notice:
          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                p.text,
                style: theme.textTheme.bodySmall?.copyWith(color: p.failed ? cs.error : cs.onSurfaceVariant),
              ),
            ),
          );
      }
    }
    if (live && status != null) children.add(_Typing(label: status!));
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

class _ToolChip extends StatelessWidget {
  final ChatPart part;
  const _ToolChip({required this.part});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final web = part.toolName == 'web_search' || part.toolName == 'web_fetch';
    final app = AppTools.isAppTool(part.toolName ?? '');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(10)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(web ? Icons.public : (app ? Icons.query_stats : Icons.extension), size: 15, color: cs.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(part.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
            ),
            const SizedBox(width: 8),
            if (part.running)
              const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6))
            else
              Icon(
                part.failed ? Icons.error_outline : Icons.check_circle,
                size: 15,
                color: part.failed ? cs.error : Colors.green,
              ),
          ],
        ),
      ),
    );
  }
}

class _Thinking extends StatefulWidget {
  final ChatPart part;
  const _Thinking({required this.part});
  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = widget.part.text.trim();
    if (text.isEmpty && !widget.part.running) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: text.isEmpty ? null : () => setState(() => _expanded = !_expanded),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.psychology_alt_outlined, size: 15, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    widget.part.running ? 'Thinking…' : 'Thought process',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  if (text.isNotEmpty)
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
              if (_expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(21, 4, 0, 4),
                  child: Text(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Typing extends StatefulWidget {
  final String label;
  const _Typing({required this.label});
  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Row(
              children: List.generate(3, (i) {
                final v = math.sin((_c.value * 2 * math.pi) - i * 0.9) * 0.5 + 0.5;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primary.withValues(alpha: 0.3 + 0.7 * v),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(width: 8),
          Text(widget.label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ──────────────────────────── Sign in ────────────────────────────

class _LoginPage extends StatefulWidget {
  const _LoginPage({super.key});
  @override
  State<_LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<_LoginPage> {
  final _key = TextEditingController();
  bool _busy = false, _obscure = true;
  String? _error;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final k = _key.text.trim();
    if (k.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AiController.instance.signIn(k);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Connect your Claude account', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          'Sign in with an API key from your Claude Console account. Usage is billed to that account. '
          '(A Claude.ai Pro/Max chat subscription can\'t be used by other apps.)',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        _Step(n: 1, text: 'Open the Claude Console and create an API key.'),
        Padding(
          padding: const EdgeInsets.only(left: 34, bottom: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Get an API key'),
              onPressed: () => launchUrl(
                Uri.parse('https://console.anthropic.com/settings/keys'),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ),
        ),
        _Step(n: 2, text: 'Paste it here and connect.'),
        const SizedBox(height: 8),
        TextField(
          controller: _key,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: (_) => _connect(),
          decoration: InputDecoration(
            hintText: 'sk-ant-…',
            prefixIcon: const Icon(Icons.key),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _busy ? null : _connect,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Connect'),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(Icons.lock_outline, size: 16, color: theme.colorScheme.outline),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Your key is stored encrypted on this device and is only sent to api.anthropic.com.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String text;
  const _Step({required this.n, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        CircleAvatar(radius: 12, child: Text('$n', style: const TextStyle(fontSize: 12))),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

// ──────────────────────────── Settings ───────────────────────────

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({super.key});
  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  bool _refreshing = false;
  String? _error;
  bool _adding = false;
  final _name = TextEditingController(), _url = TextEditingController(), _token = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (!AiConfig.instance.useClaudeAccount && AiConfig.instance.signedIn && AiConfig.instance.models.isEmpty) {
      _refresh();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      await AiController.instance.refreshModels();
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _refreshing = false);
  }

  void _addServer() {
    final name = _name.text.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-');
    final url = _url.text.trim();
    if (name.isEmpty || !url.startsWith('https://')) {
      setState(() => _error = 'MCP server needs a name and an https:// URL');
      return;
    }
    AiConfig.instance.addMcp(
      McpServer(name: name, url: url, token: _token.text.trim().isEmpty ? null : _token.text.trim()),
    );
    _name.clear();
    _url.clear();
    _token.clear();
    setState(() {
      _adding = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: AiConfig.instance, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cfg = AiConfig.instance;
    final key = cfg.apiKey ?? '';
    final newest = cfg.models.isEmpty ? null : cfg.models.first.id;
    Widget section(String t, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              t.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(color: cs.primary, letterSpacing: 1.1),
            ),
          ),
          ?trailing,
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
      children: [
        section('Connection'),
        Card(
          child: RadioGroup<String>(
            groupValue: cfg.mode,
            onChanged: (v) {
              if (v != null) cfg.mode = v;
            },
            child: const Column(
              children: [
                RadioListTile<String>(
                  value: 'claude',
                  title: Text('Claude account', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Sign in on claude.ai. Uses your Claude plan, no API key needed.'),
                ),
                RadioListTile<String>(
                  value: 'api',
                  title: Text('API key (advanced)', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Pay-as-you-go Claude Console key. Adds web search and MCP servers.'),
                ),
              ],
            ),
          ),
        ),
        if (cfg.useClaudeAccount) ...[
          section('Claude account'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.chat_outlined),
                  title: const Text('Back to chat'),
                  subtitle: const Text(
                    'Choose the engine (Fast, Balanced, Most capable or a named model) '
                    'from the sliders icon inside the chat.',
                  ),
                  onTap: () => AiController.instance.page = AiPage.chat,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text('Reload chat'),
                  onTap: () {
                    AiController.instance.webChat?.reload();
                    AiController.instance.page = AiPage.chat;
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Sign out of claude.ai'),
                  subtitle: const Text('Clears the Claude sign-in stored in this app'),
                  onTap: () async {
                    await AiController.instance.webChat?.signOut();
                    AiController.instance.page = AiPage.chat;
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
            child: Text(
              'Sign in with the Claude account that owns the CKS AI chat page, or one it is shared with. '
              'Inside apps, Google sign-in may be blocked: use "Continue with email" instead.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
        if (!cfg.useClaudeAccount) ...[
          section('Account'),
          Card(
            child: cfg.signedIn
                ? ListTile(
                    leading: const Icon(Icons.verified_user_outlined),
                    title: const Text('Connected with API key'),
                    subtitle: Text(key.length > 8 ? '••••${key.substring(key.length - 4)}' : '••••'),
                    trailing: TextButton(onPressed: AiController.instance.signOut, child: const Text('Sign out')),
                  )
                : ListTile(
                    leading: const Icon(Icons.key),
                    title: const Text('Enter your API key'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => AiController.instance.page = AiPage.login,
                  ),
          ),
          section(
            'AI model',
            trailing: _refreshing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Refresh models',
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: _refresh,
                  ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(4),
              child: Text(_error!, style: TextStyle(color: cs.error)),
            ),
          Card(
            child: RadioGroup<String>(
              groupValue: cfg.model,
              onChanged: (v) {
                if (v != null) cfg.model = v;
              },
              child: Column(
                children: [
                  if (cfg.models.isEmpty && !_refreshing) const ListTile(title: Text('No models loaded. Tap refresh.')),
                  for (final m in cfg.models)
                    RadioListTile<String>(
                      value: m.id,
                      dense: true,
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(m.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          if (m.id == defaultModelId) _Badge('Recommended', cs.primary),
                          if (m.id == newest && m.id != defaultModelId) _Badge('Newest', cs.tertiary),
                        ],
                      ),
                      subtitle: Text(m.id),
                    ),
                ],
              ),
            ),
          ),
          if ((cfg.modelInfo?.effortLevels ?? const []).isNotEmpty) ...[
            section('Reasoning effort'),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [for (final l in cfg.modelInfo!.effortLevels) ButtonSegment(value: l, label: Text(l))],
                selected: {cfg.effort},
                onSelectionChanged: (v) => cfg.effort = v.first,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text('Higher effort = deeper analysis, slower and more tokens.', style: theme.textTheme.bodySmall),
            ),
          ],
          section('Tools'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.query_stats),
                  title: const Text('Bursa market tools'),
                  subtitle: Text(
                    '${AppTools.definitions.length} built-in tools: quotes, history, technicals, compare, '
                    'market overview, watchlist, open charts',
                  ),
                  trailing: const Icon(Icons.check_circle, color: Colors.green),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.public),
                  title: const Text('Web search & fetch'),
                  subtitle: const Text('News, announcements and fundamentals'),
                  value: cfg.webTools,
                  onChanged: (v) => cfg.webTools = v,
                ),
              ],
            ),
          ),
          section(
            'MCP servers',
            trailing: IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Add MCP server',
              icon: Icon(_adding ? Icons.close : Icons.add, size: 20),
              onPressed: () => setState(() => _adding = !_adding),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              'Connect remote MCP servers (https) to give Claude more tools. Claude connects to them directly.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            child: !_adding
                ? const SizedBox(width: double.infinity)
                : Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          TextField(
                            controller: _name,
                            decoration: const InputDecoration(labelText: 'Name', isDense: true),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _url,
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(labelText: 'Server URL (https://…)', isDense: true),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _token,
                            obscureText: true,
                            decoration: const InputDecoration(labelText: 'Auth token (optional)', isDense: true),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.tonal(onPressed: _addServer, child: const Text('Add server')),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          for (final s in cfg.mcpServers)
            Card(
              child: SwitchListTile(
                title: Text(s.name),
                subtitle: Text(s.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                value: s.enabled,
                onChanged: (v) => cfg.toggleMcp(s.name, v),
                secondary: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => cfg.removeMcp(s.name)),
              ),
            ),
        ],
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
    child: Text(
      text,
      style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700),
    ),
  );
}
