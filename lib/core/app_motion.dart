import 'package:flutter/animation.dart';

class AppMotion {
  AppMotion._();

  static const microInteraction = Duration(milliseconds: 160);
  static const quick = Duration(milliseconds: 180);
  static const standard = Duration(milliseconds: 220);
  static const settle = Duration(milliseconds: 250);
  static const progress = Duration(milliseconds: 260);
  static const emphasis = Duration(milliseconds: 280);
  static const scroll = Duration(milliseconds: 360);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
}
