import 'package:flutter/material.dart';

abstract final class AppColors
{
    static final ColorScheme lightScheme = ColorScheme.fromSwatch(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
    );

    static final ColorScheme darkScheme = ColorScheme.fromSwatch(
        primarySwatch: Colors.blue,
        accentColor: Colors.blue,
        brightness: Brightness.dark,
    );

    static const Color background = Color(0xfffafafa);
    static const Color backgroundDark = Color(0xff212121);
    static const Color black333 = Color(0xff333333);
    static const Color cardDark = Color(0xff424242);
}
