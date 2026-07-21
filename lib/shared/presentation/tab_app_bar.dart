import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TabAppBar extends StatelessWidget implements PreferredSizeWidget
{
    const TabAppBar({
        required this.tabs,
        this.controller,
        this.action,
        super.key,
    });

    final List<Tab> tabs;
    final TabController? controller;
    final Widget? action;

    @override
    Widget build(BuildContext context)
    {
        final bool dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
            value: dark
                ? SystemUiOverlayStyle.light.copyWith(
                    systemNavigationBarColor: Colors.transparent,
                )
                : SystemUiOverlayStyle.dark.copyWith(
                    systemNavigationBarColor: Colors.transparent,
                ),
            child: Container(
                height: double.infinity,
                padding: EdgeInsets.only(
                    top: MediaQuery.paddingOf(context).top,
                    right: 4,
                ),
                child: Row(
                    children: <Widget>[
                        Expanded(
                            child: TabBar(
                                isScrollable: true,
                                controller: controller,
                                tabAlignment: TabAlignment.start,
                                labelColor:
                                    Theme.of(context).colorScheme.primary,
                                unselectedLabelColor: dark
                                    ? Colors.white70
                                    : Colors.black87,
                                labelStyle: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                ),
                                unselectedLabelStyle: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                ),
                                labelPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                ),
                                indicatorColor: Colors.transparent,
                                dividerColor: Colors.transparent,
                                tabs: tabs,
                            ),
                        ),
                        action ?? const SizedBox.shrink(),
                    ],
                ),
            ),
        );
    }

    @override
    Size get preferredSize => const Size.fromHeight(56);
}
