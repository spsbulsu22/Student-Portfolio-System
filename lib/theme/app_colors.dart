import 'package:flutter/material.dart';

/// Colors taken from the Figma High Fidelity frames.
/// Values marked (approx) were read visually; verify against Figma variables later.
class AppColors {
  AppColors._();

  static const primary = Color(0xFF0088FF); // Primary_Action_Button fill
  static const brandText = Color(0xFF007EDE); // title + field labels
  static const inputFill = Color(0xFFD3E7FF); // text field background
  static const link = Color(0xFF006CE8); // "Forgot Password?"
  static const linkAccent = Color(0xFF0095FF); // "Click here"
  static const checkboxBlue = Color(0xFF3F7FF0); // Remember Me toggle (approx)
  static const textDark = Colors.black;

  // Instructor screens: gradient background (Figma 1.2 - Login, 221deg, 4% -> 96%)
  static const instructorGradientStart = Color(0xFF007EDE);
  static const instructorGradientEnd = Color(0xFF004478);

  // Home screens (Figma 2 - Home / 2.2 - Home)
  static const menuButton = Color(0xFF0068B8); // Menu Button background
  static const homeIcon = Color(0xFF0A7FEB); // icon color inside white tiles (approx)

  // Side menu (Figma: Instructor Menu / Student Menu)
  static const menuText = Color(0xFF173650); // title, names, inactive items
  static const menuMuted = Color(0xFF657C8F); // "Instructor account" caption
  static const menuDivider = Color(0xFFE6EDF4);

  // Profile screens (Figma: Instructor Profile / Student Profile)
  // Header gradient: 270deg, 0% #007EDE -> 52% #0064B1 -> 100% #004478
  static const profileGradientMid = Color(0xFF0064B1);
  static const profileLabel = Color(0xB30068B8); // #0068B8 @ 70%

  // Profile dropdown (Figma: Instructor/Student Profile Dropdown)
  static const dropdownText = Color(0xFF15334B);
  static const dropdownBorder = Color(0xFFE2EEFA); // border + divider
}
