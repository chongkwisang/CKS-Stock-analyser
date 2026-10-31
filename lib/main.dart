import 'package:flutter/material.dart';

import 'ai/ai_config.dart';
import 'ai/ai_overlay.dart';
import 'app_nav.dart';
import 'screens/home_shell.dart';
import 'services/app_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppState.instance.load();
  await AiConfig.instance.load();
  runApp(const CksApp());
}

class CksApp extends StatelessWidget {
  const CksApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) => MaterialApp(
        title: 'CKS Stock Analyser',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: AppState.instance.themeMode,
        navigatorKey: appNavigatorKey,
        builder: (context, child) => AiOverlay(child: child ?? const SizedBox()),
        home: const HomeShell(),
      ),
    );
  }
}
