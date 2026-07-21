import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x300/shared/presentation/app_snack_bar.dart';

void main()
{
    test('全局底部提示缩短为两点五秒', ()
    {
        const AppSnackBar snackBar = AppSnackBar(content: Text('提示'));

        expect(snackBar.duration, const Duration(milliseconds: 2500));
    });
}
