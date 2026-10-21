import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/large_event_model.dart';

/// Service for handling navigation based on showcase type
class ShowcaseNavigationService {
  static const ShowcaseNavigationService _instance =
      ShowcaseNavigationService._internal();
  factory ShowcaseNavigationService() => _instance;
  const ShowcaseNavigationService._internal();

  /// Handle CTA press for different showcase types
  Future<void> handleShowcaseCTA(
    BuildContext context,
    LargeEventModel item,
  ) async {
    switch (item.showcaseType) {
      case ShowcaseType.webshopProduct:
        await _handleWebshopProduct(context, item);
        break;
      case ShowcaseType.externalEvent:
        await _handleExternalEvent(context, item);
        break;
      case ShowcaseType.jobOpportunity:
        await _handleJobOpportunity(context, item);
        break;
      case ShowcaseType.announcement:
        await _handleAnnouncement(context, item);
        break;
      case ShowcaseType.largeEvent:
        await _handleLargeEvent(context, item);
        break;
    }
  }

  Future<void> _handleWebshopProduct(
    BuildContext context,
    LargeEventModel item,
  ) async {
    if (item.productId != null) {
      // Navigate to specific product detail
      context.pushNamed(
        'webshop-product-detail',
        pathParameters: {'productId': item.productId!},
      );
    } else if (item.externalUrl != null) {
      // Open external product URL
      await _launchExternalUrl(item.externalUrl!);
    } else {
      // Fallback to webshop main page
      context.go('/explore/products');
    }
  }

  Future<void> _handleExternalEvent(
    BuildContext context,
    LargeEventModel item,
  ) async {
    if (item.externalUrl != null) {
      // Open external event URL (e.g., TicketCo)
      await _launchExternalUrl(item.externalUrl!);
    } else if (item.ticketcoEventId != null) {
      // Construct TicketCo URL if we have event ID
      final ticketcoUrl = _buildTicketCoUrl(
        item.ticketcoEventId!,
        item.ticketcoOrgId,
      );
      await _launchExternalUrl(ticketcoUrl);
    } else {
      // Fallback to events page
      context.go('/explore/events');
    }
  }

  Future<void> _handleJobOpportunity(
    BuildContext context,
    LargeEventModel item,
  ) async {
    final jobId = item.jobId;
    if (jobId != null) {
      context.go('/explore/volunteer/${Uri.encodeComponent(jobId)}');
    } else if (item.externalUrl != null) {
      // Open external job URL
      await _launchExternalUrl(item.externalUrl!);
    } else {
      // Fallback to jobs page
      context.go('/explore/volunteer');
    }
  }

  Future<void> _handleAnnouncement(
    BuildContext context,
    LargeEventModel item,
  ) async {
    if (item.externalUrl != null) {
      // Open external announcement URL
      await _launchExternalUrl(item.externalUrl!);
    } else {
      // Show announcement modal dialog
      await _showAnnouncementDialog(context, item);
    }
  }

  Future<void> _handleLargeEvent(
    BuildContext context,
    LargeEventModel item,
  ) async {
    if (item.externalUrl != null) {
      // Open external event URL
      await _launchExternalUrl(item.externalUrl!);
    } else {
      // Navigate to large event detail screen
      context.pushNamed(
        'large-event-detail',
        pathParameters: {'eventSlug': item.slug},
        extra: item,
      );
    }
  }

  Future<void> _launchExternalUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _buildTicketCoUrl(String eventId, String? orgId) {
    if (orgId != null) {
      return 'https://ticketco.events/$orgId/$eventId';
    } else {
      return 'https://ticketco.events/event/$eventId';
    }
  }

  Future<void> _showAnnouncementDialog(
    BuildContext context,
    LargeEventModel item,
  ) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            item.name,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.description,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                if (item.announcementContent != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    item.announcementContent!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                'Close',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}
