import 'package:flutter/material.dart';

class CatalogControlBar extends StatelessWidget {
  const CatalogControlBar({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 49,
      child: Column(
        children: <Widget>[
          Expanded(
            child: Row(
              children: children
                  .map((Widget child) => Expanded(child: child))
                  .toList(growable: false),
            ),
          ),
          Divider(
            height: 1,
            indent: 12,
            endIndent: 12,
            color: Colors.grey.withValues(alpha: 0.2),
          ),
        ],
      ),
    );
  }
}

class CatalogControlAction extends StatelessWidget {
  const CatalogControlAction({
    required this.tooltip,
    required this.onTap,
    required this.child,
    super.key,
  });

  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: child,
          ),
        ),
      ),
    );
  }
}

class CatalogControlSelector<T> extends StatelessWidget {
  const CatalogControlSelector({
    required this.label,
    required this.selected,
    required this.choices,
    required this.onSelected,
    super.key,
  });

  final String label;
  final T selected;
  final List<(T, String)> choices;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      initialValue: selected,
      position: PopupMenuPosition.under,
      onSelected: onSelected,
      itemBuilder: (BuildContext context) => choices
          .map(
            ((T, String) choice) => CheckedPopupMenuItem<T>(
              value: choice.$1,
              checked: choice.$1 == selected,
              child: Text(choice.$2),
            ),
          )
          .toList(growable: false),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
