import '../../../core/theme/biso_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/biso_glass.dart';
import '../../../data/models/user_model.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../../data/services/feature_flag_service.dart';
import 'edit_profile_screen.dart';
import 'settings_screen.dart';
import 'payment_information_screen.dart';

// Feature flag provider for expenses
final _featureFlagServiceProvider = Provider<FeatureFlagService>(
  (ref) => FeatureFlagService(),
);

final expenseFeatureFlagProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  final service = ref.watch(_featureFlagServiceProvider);
  return service.isEnabled('expenses');
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final authState = ref.watch(authStateProvider);
    final user = authState.user;
    final selectedCampus = ref.watch(selectedCampusProvider);

    // Show loading while initializing user data
    if (authState.isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.profile)),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading your profile...'),
            ],
          ),
        ),
      );
    }

    final profile = user;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: Text(l10n.profile),
            actions: [
              IconButton(
                tooltip: l10n.settingsMessage,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
                icon: const Icon(CupertinoIcons.slider_horizontal_3),
              ),
              const SizedBox(width: 8),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.biNavy,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'BISO',
                          textScaler: TextScaler.noScaling,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'BI ${selectedCampus.name}',
                            textAlign: TextAlign.end,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.biLightBlue,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: const Color(0xFF20405D),
                          backgroundImage: user?.avatarUrl != null
                              ? NetworkImage(user!.avatarUrl!)
                              : null,
                          child: user?.avatarUrl == null
                              ? Text(
                                  (user?.name.isNotEmpty == true
                                          ? user!.name
                                          : 'B')
                                      .characters
                                      .first
                                      .toUpperCase(),
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(color: Colors.white),
                                )
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            user?.name ?? l10n.profile,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Profile Content
          SliverToBoxAdapter(
            child: Padding(
              padding: BisoNavigationInset.padding(
                context,
                const EdgeInsets.fromLTRB(24, 12, 24, 24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile Completion Banner (if profile is incomplete)
                  if (authState.needsOnboarding) ...[
                    Card(
                      color: isDark
                          ? AppColors.warmGold.withValues(alpha: 0.15)
                          : AppColors.accentGold.withValues(alpha: 0.1),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: isDark
                                      ? AppColors.warmGold
                                      : AppColors.strongGold,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Complete Your Profile',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? AppColors.warmGold
                                        : AppColors.strongGold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Get the most out of BISO by completing your profile with campus and contact information.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isDark
                                    ? AppColors.warmGold
                                    : AppColors.strongGold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: () => context.push('/onboarding'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.defaultGold,
                                  foregroundColor: AppColors.strongBlue,
                                ),
                                child: const Text('Complete Profile'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Quick Actions
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ActionCard(
                              icon: Icons.edit,
                              label: 'Edit Profile',
                              color: AppColors.defaultBlue,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const EditProfileScreen(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ActionCard(
                              icon: Icons.school,
                              label: 'Student ID',
                              color: AppColors.green9,
                              disabled: true,
                              onTap: () {},
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'We’re improving Student ID. Thanks for your patience.',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  const SizedBox(height: 24),

                  // Profile Information Section
                  _ProfileSection(
                    title: 'Profile Information',
                    children: [
                      _ProfileInfoTile(
                        icon: Icons.email_outlined,
                        label: 'Email',
                        value: authState.user?.email ?? '',
                      ),
                      if (profile?.phone != null)
                        _ProfileInfoTile(
                          icon: Icons.phone_outlined,
                          label: 'Phone',
                          value: profile!.phone!,
                        ),
                      if (profile?.address != null)
                        _ProfileInfoTile(
                          icon: Icons.home_outlined,
                          label: 'Address',
                          value: _formatAddress(profile!),
                        ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Campus & Departments Section
                  _ProfileSection(
                    title: 'Campus & Interests',
                    children: [
                      _ProfileInfoTile(
                        icon: Icons.location_city_outlined,
                        label: 'Campus',
                        value: 'BI ${selectedCampus.name}',
                        trailing: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppColors.biLightBlue,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      if (profile?.departments.isNotEmpty == true)
                        _ProfileInfoTile(
                          icon: Icons.interests_outlined,
                          label: 'Interests',
                          value: profile!.departments.join(', '),
                        ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Account Actions Section
                  _ProfileSection(
                    title: 'Account',
                    children: [
                      // Expense feature - only show when enabled
                      Consumer(
                        builder: (context, ref, child) {
                          final expenseFlagAsync = ref.watch(
                            expenseFeatureFlagProvider,
                          );
                          return expenseFlagAsync.when(
                            data: (enabled) => enabled
                                ? _ProfileActionTile(
                                    icon: Icons.receipt_long_outlined,
                                    label: 'Expense History',
                                    onTap: () =>
                                        context.push('/explore/expenses'),
                                  )
                                : const SizedBox.shrink(),
                            loading: () => const SizedBox.shrink(),
                            error: (_, _) => const SizedBox.shrink(),
                          );
                        },
                      ),
                      _ProfileActionTile(
                        icon: Icons.shopping_bag_outlined,
                        label: 'Your Orders',
                        onTap: () => context.push('/explore/products/orders'),
                      ),
                      _ProfileActionTile(
                        icon: Icons.payment_outlined,
                        label: 'Payment Information',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const PaymentInformationScreen(),
                          ),
                        ),
                      ),
                      _ProfileActionTile(
                        icon: Icons.notifications_outlined,
                        label: 'Notification Preferences',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const SettingsScreen(initialTab: 1),
                          ),
                        ),
                      ),
                      _ProfileActionTile(
                        icon: Icons.language_outlined,
                        label: 'Language Settings',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const SettingsScreen(initialTab: 4),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Sign Out
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.logout, color: AppColors.error),
                      title: const Text(
                        'Sign Out',
                        style: TextStyle(color: AppColors.error),
                      ),
                      onTap: () => _showSignOutDialog(context, ref),
                    ),
                  ),

                  const SizedBox(height: 132),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatAddress(UserModel user) {
    final parts = [
      if (user.address != null) user.address!,
      if (user.city != null) user.city!,
      if (user.zipCode != null) user.zipCode!,
    ];
    return parts.join(', ');
  }

  void _showSignOutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(authStateProvider.notifier).signOut();
              // Clear all user data when signing out
              // User data is now cleared by AuthProvider internally
              if (context.mounted) {
                context.go('/home');
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool disabled;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color iconColor = disabled ? color.withValues(alpha: 0.5) : color;
    final Color iconBackground = disabled
        ? color.withValues(alpha: 0.06)
        : color.withValues(alpha: 0.1);

    return BisoGlassCard(
      padding: EdgeInsets.zero,
      borderRadius: 16,

      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: disabled
                      ? theme.colorScheme.onSurface.withValues(alpha: 0.6)
                      : theme.colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _ProfileSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        BisoGlassCard(
          padding: EdgeInsets.zero,
          borderRadius: 16,

          child: Column(
            children: children
                .expand((widget) => [widget, const Divider(height: 1)])
                .take(children.length * 2 - 1)
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _ProfileInfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  const _ProfileInfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: Icon(icon, color: AppColors.onSurfaceVariant),
      title: Text(label),
      subtitle: Text(
        value,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: trailing,
    );
  }
}

class _ProfileActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ProfileActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.onSurfaceVariant),
      title: Text(label),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }
}
