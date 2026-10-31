import 'package:flutter/widgets.dart';

/// Root navigator, so features outside the page tree (the AI overlay) can
/// open screens.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
