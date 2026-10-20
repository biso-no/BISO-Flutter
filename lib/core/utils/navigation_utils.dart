import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Navigation utilities for consistent navigation behavior across the app
class NavigationUtils {
  NavigationUtils._();

  /// Safely navigates back, falling back to home if there's nothing to pop
  static void safeGoBack(
    BuildContext context, {
    String fallbackRoute = '/home',
  }) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(fallbackRoute);
    }
  }

  /// Alias for safeGoBack - for consistency with different naming conventions
  static void goBackSafely(
    BuildContext context, {
    String fallbackRoute = '/home',
  }) {
    safeGoBack(context, fallbackRoute: fallbackRoute);
  }

  /// Creates a standardized back button that safely handles navigation
  static Widget buildBackButton(
    BuildContext context, {
    String fallbackRoute = '/home',
    VoidCallback? onPressed,
  }) {
    return IconButton(
      onPressed:
          onPressed ?? () => safeGoBack(context, fallbackRoute: fallbackRoute),
      icon: const Icon(Icons.arrow_back),
    );
  }

  /// Navigates to a tab in the main home screen
  /// This is useful when you want to navigate to a specific tab from anywhere
  static void navigateToHomeTab(BuildContext context, int tabIndex) {
    // For now, we'll just navigate to home
    // In the future, this could be enhanced to support deep linking to specific tabs
    context.go('/home');
  }

  /// Common navigation patterns
  static void navigateToExploreTab(BuildContext context) {
    navigateToHomeTab(context, 1); // Explore tab is index 1
  }

  static void navigateToChatTab(BuildContext context) {
    navigateToHomeTab(context, 2); // Chat tab is index 2
  }

  static void navigateToProfileTab(BuildContext context) {
    navigateToHomeTab(context, 3); // Profile tab is index 3
  }

  /// Shows a dialog asking user if they want to navigate back when there are unsaved changes
  static Future<bool> showUnsavedChangesDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Unsaved Changes'),
            content: const Text(
              'You have unsaved changes. Are you sure you want to go back?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Stay'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Leave'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Enhanced back button for forms with unsaved changes
  static Widget buildFormBackButton(
    BuildContext context, {
    required bool hasUnsavedChanges,
    String fallbackRoute = '/home',
  }) {
    return IconButton(
      onPressed: () async {
        if (hasUnsavedChanges) {
          final shouldLeave = await showUnsavedChangesDialog(context);
          if (shouldLeave && context.mounted) {
            safeGoBack(context, fallbackRoute: fallbackRoute);
          }
        } else {
          safeGoBack(context, fallbackRoute: fallbackRoute);
        }
      },
      icon: const Icon(Icons.arrow_back),
    );
  }
}
