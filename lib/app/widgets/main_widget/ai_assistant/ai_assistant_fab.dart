import 'package:flutter/material.dart';
import 'package:webinar/app/pages/main_page/home_page/ai_assistant_page/ai_assistant_page.dart';
import 'package:webinar/app/services/user_service/ai_assistant_service.dart';
import 'package:webinar/common/common.dart';
import 'package:webinar/common/data/app_data.dart';
import 'package:webinar/common/utils/ai_assistant_config.dart';
import 'package:webinar/config/colors.dart';

/// Floating AI entry — hidden unless config + entitlement allow.
class AiAssistantFab extends StatefulWidget {
  const AiAssistantFab({super.key});

  @override
  State<AiAssistantFab> createState() => _AiAssistantFabState();
}

class _AiAssistantFabState extends State<AiAssistantFab> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _refreshVisibility();
  }

  Future<void> _refreshVisibility() async {
    if (!AiAssistantConfig.isGloballyEnabled || !AiAssistantConfig.hasAnySearchScope) {
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

    return Material(
      elevation: 6,
      shadowColor: Colors.black26,
      shape: const CircleBorder(),
      color: green77(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          nextRoute(AiAssistantPage.pageName);
        },
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.auto_awesome, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}
