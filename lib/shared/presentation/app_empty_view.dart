import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

class AppEmptyView extends StatelessWidget
{
    const AppEmptyView({
        this.message = '这里什么都没有',
        this.onRefresh,
        this.actionLabel,
        super.key,
    });

    final String message;
    final VoidCallback? onRefresh;
    final String? actionLabel;

    @override
    Widget build(BuildContext context)
    {
        return Center(
            child: InkWell(
                onTap: onRefresh,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                            Icon(
                                Remix.inbox_2_line,
                                size: 64,
                                color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                                message,
                                style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                ),
                            ),
                            if (actionLabel != null) ...<Widget>[
                                const SizedBox(height: 16),
                                FilledButton(
                                    onPressed: onRefresh,
                                    child: Text(actionLabel!),
                                ),
                            ],
                        ],
                    ),
                ),
            ),
        );
    }
}
