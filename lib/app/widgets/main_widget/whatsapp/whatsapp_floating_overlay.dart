import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:webinar/config/assets.dart';
import 'package:webinar/app/pages/main_page/main_page.dart';
import 'package:webinar/app/services/user_service/ai_assistant_service.dart';
import 'package:webinar/app/widgets/main_widget/whatsapp/whatsapp_route_tracker.dart';
import 'package:webinar/common/data/app_data.dart';
import 'package:webinar/common/utils/ai_assistant_config.dart';
import 'package:webinar/common/utils/whatsapp_floating_config.dart';

/// Global WhatsApp FAB — config from GET /config → whatsapp_floating.
class WhatsAppFloatingOverlay extends StatefulWidget {
  final Widget? child;

  const WhatsAppFloatingOverlay({super.key, required this.child});

  @override
  State<WhatsAppFloatingOverlay> createState() => _WhatsAppFloatingOverlayState();
}

class _WhatsAppFloatingOverlayState extends State<WhatsAppFloatingOverlay> {
  bool _aiFabVisible = false;

  static const double _mainBottomNavHeight = 110;

  @override
  void initState() {
    super.initState();
    WhatsAppRouteTracker.routeName.addListener(_onRouteChanged);
    _refreshAiVisibility();
  }

  @override
  void dispose() {
    WhatsAppRouteTracker.routeName.removeListener(_onRouteChanged);
    super.dispose();
  }

  void _onRouteChanged() {
    _refreshAiVisibility();
    if (mounted) setState(() {});
  }

  Future<void> _refreshAiVisibility() async {
    if (WhatsAppRouteTracker.routeName.value != MainPage.pageName) {
      if (_aiFabVisible && mounted) setState(() => _aiFabVisible = false);
      return;
    }

    if (!AiAssistantConfig.isGloballyEnabled || !AiAssistantConfig.hasAnySearchScope) {
      if (mounted) setState(() => _aiFabVisible = false);
      return;
    }

    final token = await AppData.getAccessToken();
    if (token.isEmpty) {
      if (mounted) setState(() => _aiFabVisible = false);
      return;
    }

    final usage = await AiAssistantService.getUsage();
    if (!mounted) return;
    setState(() {
      _aiFabVisible = usage?.aiEnabledForUser == true;
    });
  }

  Future<void> _openWhatsApp() async {
    var url = WhatsAppFloatingConfig.waMeUrl.trim();
    if (url.isEmpty && WhatsAppFloatingConfig.phoneE164.isNotEmpty) {
      final phone = WhatsAppFloatingConfig.phoneE164.replaceAll('+', '').replaceAll(' ', '');
      final msg = Uri.encodeComponent(WhatsAppFloatingConfig.defaultMessage);
      url = msg.isEmpty ? 'https://wa.me/$phone' : 'https://wa.me/$phone?text=$msg';
    }
    if (url.isEmpty) return;

    final ok = await launchUrlString(url, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!WhatsAppFloatingConfig.isEnabled) {
      return widget.child ?? const SizedBox.shrink();
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (widget.child != null) widget.child!,
        ValueListenableBuilder<String?>(
          valueListenable: WhatsAppRouteTracker.routeName,
          builder: (context, route, _) {
            final onMain = route == MainPage.pageName;
            final bottomInset = MediaQuery.paddingOf(context).bottom;
            final aiVisible = onMain && _aiFabVisible;
            final bottomOffset = bottomInset +
                (onMain ? _mainBottomNavHeight : 0) +
                WhatsAppFloatingConfig.bottomDp(aiFabVisible: aiVisible);

            return Positioned(
              right: 16,
              bottom: bottomOffset,
              child: Material(
                elevation: 6,
                shadowColor: Colors.black26,
                shape: const CircleBorder(),
                color: const Color(0xFF25D366),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _openWhatsApp,
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: Padding(
                      padding: const EdgeInsets.all(11),
                      child: SvgPicture.asset(
                        AppAssets.whatsappSvg,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
