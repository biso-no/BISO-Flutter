import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/biso_navigation.dart';
import '../../../data/models/board_member_model.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/leadership/leadership_provider.dart';
import '../biso/biso.dart';

/// The board of a campus, or of one department when [departmentId] is set.
class CampusLeadershipSection extends ConsumerWidget {
  final String campusId;
  final String? departmentId;

  /// Overrides the default "Campus Leadership" heading.
  final String? title;

  /// Not every department has members in Azure AD; a department page leaves
  /// the section out rather than announcing an empty board.
  final bool hideWhenEmpty;

  const CampusLeadershipSection({
    super.key,
    required this.campusId,
    this.departmentId,
    this.title,
    this.hideWhenEmpty = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final provider = departmentId == null
        ? boardMembersProvider(campusId)
        : boardMembersWithDepartmentProvider(
            BoardMembersParams(campusId: campusId, departmentId: departmentId),
          );
    final boardMembersAsync = ref.watch(provider);

    final loaded = boardMembersAsync.valueOrNull;
    if (hideWhenEmpty &&
        loaded != null &&
        loaded.success &&
        loaded.members.isEmpty) {
      return const SizedBox.shrink();
    }

    return BisoSection(
      title: title ?? l10n.campusLeadershipMessage,
      child: boardMembersAsync.when(
        loading: () => const BisoSkeleton.rows(count: 3),
        error: (error, stackTrace) => BisoErrorState(
          message: 'Error loading board members: $error',
          onRetry: () => ref.invalidate(provider),
        ),
        data: (response) {
          if (!response.success) {
            return BisoErrorState(
              message:
                  'Error loading board members: '
                  '${response.error ?? 'Failed to load board members'}',
              onRetry: () => ref.invalidate(provider),
            );
          }

          if (response.members.isEmpty) {
            return BisoEmptyState(
              icon: CupertinoIcons.person_2,
              accent: BisoAccent.teal,
              title: response.departmentName != null
                  ? 'No members found for ${response.departmentName}'
                  : 'No board members found',
            );
          }

          return _BoardMembersList(
            members: response.members,
            departmentName: departmentId == null
                ? response.departmentName
                : null,
          );
        },
      ),
    );
  }
}

class _BoardMembersList extends StatelessWidget {
  final List<BoardMemberModel> members;
  final String? departmentName;

  const _BoardMembersList({required this.members, this.departmentName});

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (departmentName != null) ...[
          Text(
            departmentName!,
            style: theme.textTheme.bodyMedium?.copyWith(color: palette.muted),
          ),
          const SizedBox(height: 12),
        ],
        BisoListGroup(
          children: [
            for (final member in members) BoardMemberCard(member: member),
          ],
        ),
      ],
    );
  }
}

class BoardMemberCard extends StatelessWidget {
  final BoardMemberModel member;

  const BoardMemberCard({super.key, required this.member});

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final subtitle = [
      member.role,
      member.officeLocation,
    ].where((part) => part.isNotEmpty).join(' · ');

    return BisoListRow(
      leading: _buildAvatar(palette),
      title: member.name,
      subtitle: subtitle,
      onTap: () => _showMemberDetails(context),
    );
  }

  Widget _buildAvatar(BisoPalette palette) {
    final String? uri = member.profilePhotoUrl?.trim();
    if (uri != null && uri.isNotEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: palette.surfaceRaised,
        child: ClipOval(
          child: _SafeAvatarImage(
            uri: uri,
            width: 48,
            height: 48,
            borderRadius: 24,
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: 24,
      backgroundColor: palette.surfaceRaised,
      child: Icon(CupertinoIcons.person_fill, color: palette.muted, size: 20),
    );
  }

  void _showMemberDetails(BuildContext context) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _MemberDetailModal(member: member),
    );
  }
}

class _MemberDetailModal extends StatelessWidget {
  final BoardMemberModel member;

  const _MemberDetailModal({required this.member});

  static const _spacing = EdgeInsets.fromLTRB(20, 8, 20, 20);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);

    // The floating tab bar overlays sheets and strips the bottom safe area,
    // so a SafeArea adds nothing here; clear the bar itself. Sheets sit
    // outside BisoPage, hence the design-rule exception.
    return SingleChildScrollView(
      child: Padding(
        padding: BisoNavigationInset.padding(context, _spacing), // biso:allow
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: palette.surfaceRaised,
              child:
                  (member.profilePhotoUrl != null &&
                      member.profilePhotoUrl!.isNotEmpty)
                  ? ClipOval(
                      child: _SafeAvatarImage(
                        uri: member.profilePhotoUrl!,
                        width: 80,
                        height: 80,
                        borderRadius: 40,
                      ),
                    )
                  : Icon(
                      CupertinoIcons.person_fill,
                      color: palette.muted,
                      size: 32,
                    ),
            ),
            const SizedBox(height: 16),
            Text(
              member.name,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: palette.ink,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              member.role,
              style: theme.textTheme.bodyLarge?.copyWith(color: palette.muted),
              textAlign: TextAlign.center,
            ),
            if (member.officeLocation.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.location_solid,
                    size: 14,
                    color: palette.muted,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      member.officeLocation,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (member.email.isNotEmpty || member.phone.isNotEmpty) ...[
              const SizedBox(height: 24),
              BisoListGroup(
                children: [
                  if (member.email.isNotEmpty)
                    BisoListRow(
                      leading: const BisoIconTile(icon: CupertinoIcons.mail),
                      title: 'Email',
                      subtitle: member.email,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _launchOrCopy(
                          context,
                          Uri(scheme: 'mailto', path: member.email),
                          member.email,
                          'Email copied',
                        );
                      },
                    ),
                  if (member.phone.isNotEmpty)
                    BisoListRow(
                      leading: const BisoIconTile(icon: CupertinoIcons.phone),
                      title: 'Call',
                      subtitle: member.phone,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _launchOrCopy(
                          context,
                          Uri(scheme: 'tel', path: member.phone),
                          member.phone,
                          'Phone number copied',
                        );
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Launches without asking `canLaunchUrl` first: that check needs each
  /// scheme declared per platform and silently turns the tap into a no-op
  /// when one is missing. Copies [value] when nothing can handle [uri] (no
  /// mail app, the iOS Simulator) so the tap is never a dead end.
  Future<void> _launchOrCopy(
    BuildContext context,
    Uri uri,
    String value,
    String copiedMessage,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (launched) return;
    await Clipboard.setData(ClipboardData(text: value));
    messenger?.showSnackBar(SnackBar(content: Text(copiedMessage)));
  }
}

class _SafeAvatarImage extends StatelessWidget {
  final String uri;
  final double width;
  final double height;
  final double borderRadius;

  const _SafeAvatarImage({
    required this.uri,
    required this.width,
    required this.height,
    this.borderRadius = 0,
  });

  bool _isHttpUrl(String value) {
    final v = value.toLowerCase();
    return v.startsWith('http://') || v.startsWith('https://');
  }

  bool _isDataUri(String value) {
    return value.toLowerCase().startsWith('data:image');
  }

  bool _looksLikeRawBase64(String value) {
    // Heuristic: long base64-looking string (often starts with "/9j/" for JPEG)
    final trimmed = value.trim();
    if (trimmed.length < 40) return false;
    final candidate = trimmed.contains(',') ? trimmed.split(',').last : trimmed;
    final normalized = candidate.replaceAll(RegExp(r"\s"), '');
    final base64Like = RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(normalized);
    return base64Like && normalized.length >= 40;
  }

  Uint8List? _decodeBase64(String value) {
    try {
      final dataPart = value.contains(',') ? value.split(',').last : value;
      final normalized = base64.normalize(dataPart.trim());
      return base64Decode(normalized);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);

    if (_isHttpUrl(uri)) {
      return Image.network(
        uri,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _placeholder(palette);
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _loading(palette);
        },
      );
    }

    if (_isDataUri(uri) || _looksLikeRawBase64(uri)) {
      final bytes = _decodeBase64(uri);
      if (bytes != null) {
        return Image.memory(
          bytes,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _placeholder(palette);
          },
        );
      }
    }

    return _placeholder(palette);
  }

  Widget _placeholder(BisoPalette palette) {
    return ColoredBox(
      color: palette.surfaceRaised,
      child: SizedBox(
        width: width,
        height: height,
        child: Center(
          child: Icon(
            CupertinoIcons.person_fill,
            color: palette.muted,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _loading(BisoPalette palette) {
    return ColoredBox(
      color: palette.surfaceRaised,
      child: SizedBox(
        width: width,
        height: height,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    );
  }
}
