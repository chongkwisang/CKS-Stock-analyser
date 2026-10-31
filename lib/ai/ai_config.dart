import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A remote MCP server the user has added. Claude connects to it server-side
/// through the Messages API MCP connector.
class McpServer {
  final String name;
  final String url;
  final String? token;
  final bool enabled;
  const McpServer({required this.name, required this.url, this.token, this.enabled = true});

  McpServer copyWith({bool? enabled}) =>
      McpServer(name: name, url: url, token: token, enabled: enabled ?? this.enabled);

  Map<String, dynamic> toJson() => {'name': name, 'url': url, 'token': token, 'enabled': enabled};
  factory McpServer.fromJson(Map<String, dynamic> j) => McpServer(
    name: j['name'] as String,
    url: j['url'] as String,
    token: j['token'] as String?,
    enabled: j['enabled'] as bool? ?? true,
  );
}

/// What the Models API told us about a model.
class ModelInfo {
  final String id;
  final String displayName;
  final DateTime? createdAt;
  final bool adaptiveThinking;
  final List<String> effortLevels;
  const ModelInfo({
    required this.id,
    required this.displayName,
    this.createdAt,
    this.adaptiveThinking = false,
    this.effortLevels = const [],
  });

  factory ModelInfo.fromApi(Map<String, dynamic> j) {
    final caps = (j['capabilities'] as Map?)?.cast<String, dynamic>() ?? const {};
    bool sup(Object? node) => node is Map && node['supported'] == true;
    final thinking = caps['thinking'];
    final adaptive = thinking is Map && sup((thinking['types'] as Map?)?['adaptive']);
    final effort = caps['effort'];
    final levels = <String>[];
    if (sup(effort)) {
      for (final l in const ['low', 'medium', 'high', 'xhigh', 'max']) {
        if (sup((effort as Map)[l])) levels.add(l);
      }
    }
    return ModelInfo(
      id: j['id'] as String,
      displayName: (j['display_name'] ?? j['id']).toString(),
      createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
      adaptiveThinking: adaptive,
      effortLevels: levels,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'display_name': displayName,
    'created_at': createdAt?.toIso8601String(),
    'adaptive': adaptiveThinking,
    'effort': effortLevels,
  };

  factory ModelInfo.fromCache(Map<String, dynamic> j) => ModelInfo(
    id: j['id'] as String,
    displayName: j['display_name'] as String,
    createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
    adaptiveThinking: j['adaptive'] as bool? ?? false,
    effortLevels: ((j['effort'] as List?) ?? const []).cast<String>(),
  );
}

const defaultModelId = 'claude-opus-5-5';

/// Persisted AI settings. The API key lives in Android's encrypted storage;
/// everything else in shared preferences.
class AiConfig extends ChangeNotifier {
  AiConfig._();
  static final AiConfig instance = AiConfig._();

  static const _secure = FlutterSecureStorage();
  late SharedPreferences _prefs;

  String? _apiKey;
  String _model = defaultModelId;
  String _effort = 'medium';
  bool _webTools = true;
  List<McpServer> _mcp = [];
  List<ModelInfo> _models = [];

  String? get apiKey => _apiKey;
  bool get signedIn => (_apiKey ?? '').isNotEmpty;
  String get model => _model;
  String get effort => _effort;
  bool get webTools => _webTools;
  List<McpServer> get mcpServers => List.unmodifiable(_mcp);
  List<ModelInfo> get models => List.unmodifiable(_models);

  ModelInfo? get modelInfo {
    for (final m in _models) {
      if (m.id == _model) return m;
    }
    return null;
  }

  String get modelLabel => modelInfo?.displayName ?? _model;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    try {
      _apiKey = await _secure.read(key: 'anthropic_api_key');
    } catch (_) {
      _apiKey = null;
    }
    _model = _prefs.getString('ai_model') ?? defaultModelId;
    _effort = _prefs.getString('ai_effort') ?? 'medium';
    _webTools = _prefs.getBool('ai_web') ?? true;
    try {
      _mcp = ((jsonDecode(_prefs.getString('ai_mcp') ?? '[]') as List).cast<Map<String, dynamic>>())
          .map(McpServer.fromJson)
          .toList();
      _models = ((jsonDecode(_prefs.getString('ai_models') ?? '[]') as List).cast<Map<String, dynamic>>())
          .map(ModelInfo.fromCache)
          .toList();
    } catch (_) {}
  }

  @visibleForTesting
  void debugSetKey(String key) => _apiKey = key;

  Future<void> setApiKey(String? key) async {
    _apiKey = key;
    if (key == null) {
      await _secure.delete(key: 'anthropic_api_key');
      _models = [];
      await _prefs.remove('ai_models');
    } else {
      await _secure.write(key: 'anthropic_api_key', value: key);
    }
    notifyListeners();
  }

  void setModels(List<ModelInfo> list) {
    _models = [...list]..sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));
    _prefs.setString('ai_models', jsonEncode(_models.map((e) => e.toJson()).toList()));
    if (_models.isNotEmpty && !_models.any((m) => m.id == _model)) {
      _model = _models.any((m) => m.id == defaultModelId) ? defaultModelId : _models.first.id;
      _prefs.setString('ai_model', _model);
    }
    notifyListeners();
  }

  set model(String v) {
    _model = v;
    _prefs.setString('ai_model', v);
    final levels = modelInfo?.effortLevels ?? const [];
    if (levels.isNotEmpty && !levels.contains(_effort)) effort = levels.contains('medium') ? 'medium' : levels.first;
    notifyListeners();
  }

  set effort(String v) {
    _effort = v;
    _prefs.setString('ai_effort', v);
    notifyListeners();
  }

  set webTools(bool v) {
    _webTools = v;
    _prefs.setBool('ai_web', v);
    notifyListeners();
  }

  void addMcp(McpServer s) {
    _mcp = [..._mcp.where((e) => e.name != s.name), s];
    _saveMcp();
  }

  void removeMcp(String name) {
    _mcp = _mcp.where((e) => e.name != name).toList();
    _saveMcp();
  }

  void toggleMcp(String name, bool on) {
    _mcp = _mcp.map((e) => e.name == name ? e.copyWith(enabled: on) : e).toList();
    _saveMcp();
  }

  void _saveMcp() {
    _prefs.setString('ai_mcp', jsonEncode(_mcp.map((e) => e.toJson()).toList()));
    notifyListeners();
  }
}
