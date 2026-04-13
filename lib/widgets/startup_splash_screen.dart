import 'package:flutter/material.dart';

class StartupSplashScreen extends StatelessWidget {
  const StartupSplashScreen({this.errorMessage, super.key});

  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;
    final backgroundColor = isDark
        ? const Color(0xFF111418)
        : const Color(0xFFF5F7F2);
    final foregroundColor = isDark ? Colors.white : const Color(0xFF12303A);

    return ColoredBox(
      color: backgroundColor,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Image.asset(
                      'assets/branding/splash_android.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 28),
                  Text(
                    '啟動失敗',
                    style: TextStyle(
                      color: foregroundColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    errorMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: foregroundColor.withValues(alpha: 0.82),
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
