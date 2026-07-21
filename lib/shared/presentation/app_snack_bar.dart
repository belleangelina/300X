import 'package:flutter/material.dart';

class AppSnackBar extends SnackBar
{
    const AppSnackBar({
        super.key,
        required super.content,
        super.duration = const Duration(milliseconds: 2500),
    });
}
