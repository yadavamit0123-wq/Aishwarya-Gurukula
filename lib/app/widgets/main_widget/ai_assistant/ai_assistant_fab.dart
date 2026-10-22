import 'package:flutter/material.dart';
import 'package:webinar/app/pages/main_page/home_page/ai_assistant_page/ai_assistant_page.dart';
import 'package:webinar/app/services/user_service/ai_assistant_service.dart';
import 'package:webinar/common/common.dart';
import 'package:webinar/common/data/app_data.dart';
import 'package:webinar/common/utils/ai_assistant_config.dart';
import 'package:webinar/config/colors.dart';
import 'package:webinar/config/styles.dart';

/// Floating AI entry — hidden unless config + entitlement allow.
class AiAssistantFab extends StatefulWidget {
  const AiAssistantFab({super.key});

  @override
  State<AiAssistantFab> createState() => _AiAssistantFabState();
}

class _AiAssistantFabState extends State<AiAssistantFab>
    with SingleTickerProviderStateMixin {
  bool _visible = false;
  late AnimationController _floatController;
  late Animation<double> _floatOffset;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _floatOffset = Tween<double>(begin: 0, end: -5).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );
    _refreshVisibility();
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  Future<void> _refreshVisibility() async {
    if (!AiAssistantConfig.isGloballyEnabled ||
        !AiAssistantConfig.hasAnySearchScope) {
      if (mounted) setState(() => _visible = false);
      return;
    }

    final token = await AppData.getAccessToken();
    if (token.isEmpty) {
      if (mounted) setState(() => _visible = false);
      return;
    }

    final usage = await AiAssistantService.getUsage();
    if (!mounted) return;
    setState(() {
      _visible = usage?.aiEnabledForUser == true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => nextRoute(AiAssistantPage.pageName),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _floatOffset,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _floatOffset.value),
                child: child,
              );
            },
            child: Material(
              elevation: 6,
              shadowColor: Colors.black26,
              shape: const CircleBorder(),
              color: green77(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => nextRoute(AiAssistantPage.pageName),
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(Icons.auto_awesome, color: Colors.white, size: 24),
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Ask Guru',
            textAlign: TextAlign.center,
            style: style12Bold().copyWith(
              color: Colors.white,
              fontSize: 11,
              height: 1.1,
              letterSpacing: 0.2,
              shadows: const [
                Shadow(
                  color: Color(0x99000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
