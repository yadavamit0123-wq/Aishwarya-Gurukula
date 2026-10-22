import 'package:flutter/material.dart';

/// Tracks top route name so global overlays (WhatsApp FAB) can reposition.
class WhatsAppRouteTracker extends NavigatorObserver {
  static final ValueNotifier<String?> routeName = ValueNotifier<String?>(null);

  void _set(Route<dynamic>? route) {
    routeName.value = route?.settings.name;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _set(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _set(previousRoute);
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _set(newRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _set(previousRoute);
    super.didRemove(route, previousRoute);
  }
}
