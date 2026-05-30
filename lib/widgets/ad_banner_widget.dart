import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../app/bus_app.dart';
import '../core/ad_service.dart';

/// A self-contained banner ad widget.
///
/// Renders a standard adaptive banner ad when ads are enabled and the platform
/// supports them. Returns [SizedBox.shrink] otherwise.
class AdBannerWidget extends StatefulWidget {
  const AdBannerWidget({super.key});

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAd();
  }

  Future<void> _loadAd() async {
    await AdService.instance.initialize();
    if (!AdService.instance.isAvailable) {
      return;
    }

    // Check if ads are enabled in settings.
    final controller = AppControllerScope.of(context);
    if (!controller.settings.enableAds) {
      _bannerAd?.dispose();
      _bannerAd = null;
      if (_isLoaded) {
        setState(() => _isLoaded = false);
      }
      return;
    }

    // Avoid reloading if already loaded.
    if (_bannerAd != null) {
      return;
    }

    final adSize = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
      MediaQuery.sizeOf(context).width.truncate(),
    );
    if (adSize == null || !mounted) {
      return;
    }

    final bannerAd = BannerAd(
      adUnitId: AdService.bannerAdUnitId,
      size: adSize,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) {
            setState(() => _isLoaded = true);
          }
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('AdBanner failed to load: ${error.message}');
          ad.dispose();
          if (mounted) {
            setState(() {
              _bannerAd = null;
              _isLoaded = false;
            });
          }
        },
      ),
    );

    _bannerAd = bannerAd;
    await bannerAd.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AdService.instance.isAvailable) {
      return const SizedBox.shrink();
    }

    final controller = AppControllerScope.of(context);
    if (!controller.settings.enableAds) {
      return const SizedBox.shrink();
    }

    final ad = _bannerAd;
    if (ad == null || !_isLoaded) {
      return const SizedBox.shrink();
    }

    return Container(
      alignment: Alignment.center,
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
