import 'package:flutter/material.dart';

class AppLoadingView extends StatelessWidget
{
    const AppLoadingView({
        this.message = '正在加载',
        super.key,
    });

    final String message;

    @override
    Widget build(BuildContext context)
    {
        return Center(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                        const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(height: 16),
                        Text(
                            message,
                            style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                            ),
                        ),
                    ],
                ),
            ),
        );
    }
}
