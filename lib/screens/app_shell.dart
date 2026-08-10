import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../theme/app_theme.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'sessions_screen.dart';

/// The signed-in navigation shell: Beranda, Sesi, Riwayat, Profil.
///
/// Four destinations and nothing else. There is no discovery tab, no search,
/// no people directory — the absence is the product decision (B.4): being able
/// to browse and approach someone directly is exactly what CoStudy removes.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.user, required this.authService});

  final User user;
  final AuthService authService;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      HomeScreen(user: widget.user, onSeeSessions: () => _select(1)),
      const SessionsScreen(),
      const HistoryScreen(),
      ProfileScreen(user: widget.user, authService: widget.authService),
    ];

    return Scaffold(
      // IndexedStack rather than swapping children: switching tabs must not
      // discard a tab's scroll position or, more importantly, restart the
      // Waiting screen's animation on Sesi.
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: _BottomNav(
        index: _index,
        onSelect: _select,
      ),
    );
  }

  void _select(int index) => setState(() => _index = index);
}

/// Custom bar rather than NavigationBar: the prototype's active state is a
/// blue-tinted rounded pill behind the icon with the label beneath, which
/// Material 3's own indicator geometry will not produce.
class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const _items = [
    (icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Beranda'),
    (icon: Icons.search_rounded, activeIcon: Icons.search_rounded, label: 'Sesi'),
    (
      icon: Icons.calendar_today_outlined,
      activeIcon: Icons.calendar_month_rounded,
      label: 'Riwayat'
    ),
    (
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Profil'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.gray)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < _items.length; i++)
                _NavItem(
                  item: _items[i],
                  selected: index == i,
                  onTap: () => onSelect(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ({IconData icon, IconData activeIcon, String label}) item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 38,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.blueLight : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
                child: Icon(
                  selected ? item.activeIcon : item.icon,
                  size: 20,
                  color: selected ? AppColors.blue : AppColors.grayMid,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.label,
                style: display(
                  size: 10,
                  weight: FontWeight.w700,
                  color: selected ? AppColors.blue : AppColors.grayMid,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
