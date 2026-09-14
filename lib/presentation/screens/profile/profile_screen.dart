import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/feature_flag_service.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../widgets/biso/biso.dart';
import 'edit_profile_screen.dart';
import 'payment_information_screen.dart';
import 'settings_screen.dart';

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
    final authState = ref.watch(authStateProvider);
    final user = authState.user;
    final selectedCampus = ref.watch(selectedCampusProvider);

    // Show loading while initializing user data
    if (authState.isLoading) {
      return BisoPage(
        title: l10n.profile,
        largeTitle: false,
        slivers: [SliverToBoxAdapter(child: BisoSkeleton.rows(count: 4))],
      );
    }

    final profile = user;
    final expenseFlagAsync = ref.watch(expenseFeatureFlagProvider);
    final showExpenseHistory = expenseFlagAsync.valueOrNull ?? false;

    return BisoPage(
      title: l10n.profile,
      actions: [
        BisoHeaderAction(
          icon: CupertinoIcons.gear,
          tooltip: l10n.settingsMessage,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
        ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: DecoratedBox(
              // biso:allow brand card
              decoration: BoxDecoration(
                color: AppColors.biNavy,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
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
                          backgroundColor: Colors.white.withValues(
                            alpha: 0.12,
                          ),
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
        ),

        // Profile Completion Banner (if profile is incomplete)
        if (authState.needsOnboarding)
          SliverToBoxAdapter(
            child: BisoSection(
              child: BisoListGroup(
                children: [
                  const BisoListRow(
                    leading: BisoIconTile(
                      icon: CupertinoIcons.info_circle,
                      accent: BisoAccent.violet,
                    ),
                    title: 'Complete Your Profile',
                    subtitle:
                        'Get the most out of BISO by completing your profile '
                        'with campus and contact information.',
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => context.push('/onboarding'),
                        child: const Text('Complete Profile'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Quick Actions
        SliverToBoxAdapter(
          child: BisoSection(
            child: BisoListGroup(
              children: [
                BisoListRow(
                  leading: const BisoIconTile(icon: CupertinoIcons.pencil),
                  title: 'Edit Profile',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const EditProfileScreen(),
                    ),
                  ),
                ),
                const BisoListRow(
                  leading: BisoIconTile(
                    icon: CupertinoIcons.book,
                    accent: BisoAccent.gold,
                  ),
                  title: 'Student ID',
                  subtitle:
                      'We’re improving Student ID. Thanks for your patience.',
                  showChevron: false,
                ),
              ],
            ),
          ),
        ),

        // Profile Information Section
        SliverToBoxAdapter(
          child: BisoSection(
            title: 'Profile Information',
            child: BisoListGroup(
              children: [
                BisoListRow(
                  leading: const BisoIconTile(icon: CupertinoIcons.mail),
                  title: 'Email',
                  value: authState.user?.email ?? '',
                ),
                if (profile?.phone != null)
                  BisoListRow(
                    leading: const BisoIconTile(icon: CupertinoIcons.phone),
                    title: 'Phone',
                    value: profile!.phone!,
                  ),
                if (profile?.address != null)
                  BisoListRow(
                    leading: const BisoIconTile(icon: CupertinoIcons.house),
                    title: 'Address',
                    value: _formatAddress(profile!),
                  ),
              ],
            ),
          ),
        ),

        // Campus & Departments Section
        SliverToBoxAdapter(
          child: BisoSection(
            title: 'Campus & Interests',
            child: BisoListGroup(
              children: [
                BisoListRow(
                  leading: const BisoIconTile(
                    icon: CupertinoIcons.location_solid,
                  ),
                  title: 'Campus',
                  value: 'BI ${selectedCampus.name}',
                ),
                if (profile?.departments.isNotEmpty == true)
                  BisoListRow(
                    leading: const BisoIconTile(icon: CupertinoIcons.tags),
                    title: 'Interests',
                    value: profile!.departments.join(', '),
                  ),
              ],
            ),
          ),
        ),

        // Account Actions Section
        SliverToBoxAdapter(
          child: BisoSection(
            title: 'Account',
            child: BisoListGroup(
              children: [
                if (showExpenseHistory)
                  BisoListRow(
                    leading: const BisoIconTile(
                      icon: CupertinoIcons.doc_text,
                      accent: BisoAccent.coral,
                    ),
                    title: 'Expense History',
                    onTap: () => context.push('/explore/expenses'),
                  ),
                BisoListRow(
                  leading: const BisoIconTile(
                    icon: CupertinoIcons.bag,
                    accent: BisoAccent.gold,
                  ),
                  title: 'Your Orders',
                  onTap: () => context.push('/explore/products/orders'),
                ),
                BisoListRow(
                  leading: const BisoIconTile(
                    icon: CupertinoIcons.creditcard,
                    accent: BisoAccent.coral,
                  ),
                  title: 'Payment Information',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PaymentInformationScreen(),
                    ),
                  ),
                ),
                BisoListRow(
                  leading: const BisoIconTile(icon: CupertinoIcons.bell),
                  title: 'Notification Preferences',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(
                        initialTab: 1,
                      ),
                    ),
                  ),
                ),
                BisoListRow(
                  leading: const BisoIconTile(icon: CupertinoIcons.globe),
                  title: 'Language Settings',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(
                        initialTab: 4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Sign Out
        SliverToBoxAdapter(
          child: BisoSection(
            child: BisoListGroup(
              children: [
                BisoListRow(
                  leading: const BisoIconTile(
                    icon: CupertinoIcons.square_arrow_right,
                  ),
                  title: 'Sign Out',
                  destructive: true,
                  showChevron: false,
                  onTap: () => _showSignOutDialog(context, ref),
                ),
              ],
            ),
          ),
        ),
      ],
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
            style: TextButton.styleFrom(
              foregroundColor: BisoPalette.of(context).error,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}
