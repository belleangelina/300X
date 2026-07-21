import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

class AppErrorView extends StatelessWidget
{
    const AppErrorView({
        required this.message,
        this.onRetry,
        super.key,
    });

    final String message;
    final VoidCallback? onRetry;

    @override
    Widget build(BuildContext context)
    {
        return Center(
            child: InkWell(
                onTap: onRetry,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                            Icon(
                                Remix.error_warning_line,
                                size: 64,
                                color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                                message,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                ),
                            ),
                            if (onRetry != null) ...<Widget>[
                                const SizedBox(height: 12),
                                const Text(
                                    '点击重试',
                                    style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12,
                                    ),
                                ),
                            ],
                        ],
                    ),
                ),
            ),
        );
    }
}
