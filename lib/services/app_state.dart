import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide persisted state: watchlist, theme and preferences.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  late SharedPreferences _prefs;
  List<String> _watchlist = [];
  ThemeMode _themeMode = ThemeMode.dark;
  bool _autoCheckUpdates = true;
  bool _candles = true;

  /// Symbol on the stock screen currently open (context for the AI).
  String? viewingSymbol;

  List<String> get watchlist => List.unmodifiable(_watchlist);
  ThemeMode get themeMode => _themeMode;
  bool get autoCheckUpdates => _autoCheckUpdates;
  bool get candles => _candles;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _watchlist = _prefs.getStringList('watchlist') ?? ['1155.KL', '1295.KL', '5347.KL', '5225.KL', '1023.KL'];
    _themeMode = ThemeMode.values[_prefs.getInt('themeMode') ?? ThemeMode.dark.index];
    _autoCheckUpdates = _prefs.getBool('autoCheckUpdates') ?? true;
    _candles = _prefs.getBool('candles') ?? true;
  }

  bool isWatched(String symbol) => _watchlist.contains(symbol);

  void toggleWatch(String symbol) {
    if (_watchlist.contains(symbol)) {
      _watchlist.remove(symbol);
    } else {
      _watchlist.add(symbol);
    }
    _prefs.setStringList('watchlist', _watchlist);
    notifyListeners();
  }

  /// [newIndex] is already adjusted for the removed item.
  void moveItem(int oldIndex, int newIndex) {
    final s = _watchlist.removeAt(oldIndex);
    _watchlist.insert(newIndex, s);
    _prefs.setStringList('watchlist', _watchlist);
    notifyListeners();
  }

  set themeMode(ThemeMode m) {
    _themeMode = m;
    _prefs.setInt('themeMode', m.index);
    notifyListeners();
  }

  set autoCheckUpdates(bool v) {
    _autoCheckUpdates = v;
    _prefs.setBool('autoCheckUpdates', v);
    notifyListeners();
  }

  set candles(bool v) {
    _candles = v;
    _prefs.setBool('candles', v);
    notifyListeners();
  }
}
