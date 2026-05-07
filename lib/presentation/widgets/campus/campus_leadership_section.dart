import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/board_member_model.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/leadership/leadership_provider.dart';

class CampusLeadershipSection extends ConsumerWidget {
  final String campusId;
  final int animationDelay;

  const CampusLeadershipSection({
    super.key,
    required this.campusId,
    this.animationDelay = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final boardMembersAsync = ref.watch(boardMembersProvider(campusId));

    return TweenAnimationBuilder(
      duration: Duration(milliseconds: 600 + animationDelay),
      tween: Tween<double>(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadowLight,
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.defaultBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.groups_outlined,
                          color: AppColors.defaultBlue,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          l10n.campusLeadershipMessage,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.defaultBlue,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Content
                  boardMembersAsync.when(
                    loading: () => const _LoadingState(),
                    error: (error, stackTrace) => _ErrorState(
                      error: error.toString(),
                      onRetry: () => ref.refresh(boardMembersProvider(campusId)),
                    ),
                    data: (response) {
                      if (!response.success) {
                        return _ErrorState(
                          error: response.error ?? 'Failed to load board members',
                          onRetry: () => ref.refresh(boardMembersProvider(campusId)),
                        );
                      }

                      if (response.members.isEmpty) {
                        return _EmptyState(
                          departmentName: response.departmentName,
                        );
                      }

                      return _BoardMembersList(
                        members: response.members,
                        departmentName: response.departmentName,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: AppColors.outlineVariant.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Loading board members...',
              style: TextStyle(
                color: AppColors.mist,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.error.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.error_outline,
            color: AppColors.error,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            'Error loading board members',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.error,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.error,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String? departmentName;

  const _EmptyState({this.departmentName});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: AppColors.outlineVariant.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.people_outline,
              size: 48,
              color: AppColors.mist,
            ),
            const SizedBox(height: 8),
            Text(
              departmentName != null
                  ? 'No members found for $departmentName'
                  : 'No board members found',
              style: const TextStyle(
                color: AppColors.mist,
                fontStyle: FontStyle.italic,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardMembersList extends StatelessWidget {
  final List<BoardMemberModel> members;
  final String? departmentName;

  const _BoardMembersList({
    required this.members,
    this.departmentName,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Department name if available
        if (departmentName != null) ...[
          Text(
            departmentName!,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.defaultBlue.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Members list
        ...members.asMap().entries.map((entry) {
          final index = entry.key;
          final member = entry.value;
          
          return TweenAnimationBuilder(
            duration: Duration(milliseconds: 200 + (index * 100)),
            tween: Tween<double>(begin: 0.0, end: 1.0),
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(20 * (1 - value), 0),
                child: Opacity(
                  opacity: value,
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: index == members.length - 1 ? 0 : 12,
                    ),
                    child: BoardMemberCard(member: member),
                  ),
                ),
              );
            },
          );
        }),
      ],
    );
  }
}

class BoardMemberCard extends StatefulWidget {
  final BoardMemberModel member;

  const BoardMemberCard({
    super.key,
    required this.member,
  });

  @override
  State<BoardMemberCard> createState() => _BoardMemberCardState();
}

class _BoardMemberCardState extends State<BoardMemberCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: () => _showMemberDetails(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _isPressed
              ? AppColors.subtleBlue.withValues(alpha: 0.5)
              : AppColors.subtleBlue.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isPressed
                ? AppColors.defaultBlue.withValues(alpha: 0.3)
                : AppColors.defaultBlue.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            // Avatar
            _buildAvatar(),
            
            const SizedBox(width: 12),
            
            // Member Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.member.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.strongBlue,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.member.role,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.defaultBlue.withValues(alpha: 0.7),
                    ),
                  ),
                  if (widget.member.officeLocation.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 12,
                          color: AppColors.stoneGray,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.member.officeLocation,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.stoneGray,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            
            // Contact Icon
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.defaultBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.contact_mail_outlined,
                size: 16,
                color: AppColors.defaultBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final String? uri = widget.member.profilePhotoUrl?.trim();
    if (uri != null && uri.isNotEmpty) {
      final Widget avatarImage = _SafeAvatarImage(
        uri: uri,
        width: 48,
        height: 48,
        borderRadius: 24,
      );

      return CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.defaultBlue.withValues(alpha: 0.1),
        child: ClipOval(child: avatarImage),
      );
    }

    return CircleAvatar(
      radius: 24,
      backgroundColor: AppColors.defaultBlue.withValues(alpha: 0.1),
      child: const Icon(
        Icons.person,
        color: AppColors.defaultBlue,
        size: 20,
      ),
    );
  }

  void _showMemberDetails(BuildContext context) {
    HapticFeedback.selectionClick();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _MemberDetailModal(member: widget.member),
    );
  }
}

class _MemberDetailModal extends StatelessWidget {
  final BoardMemberModel member;

  const _MemberDetailModal({required this.member});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.cloud,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Avatar
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.defaultBlue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              clipBehavior: Clip.antiAlias,
              child: (member.profilePhotoUrl != null && member.profilePhotoUrl!.isNotEmpty)
                  ? _SafeAvatarImage(
                      uri: member.profilePhotoUrl!,
                      width: 80,
                      height: 80,
                      borderRadius: 40,
                    )
                  : const Center(
                      child: Icon(
                        Icons.person,
                        color: AppColors.defaultBlue,
                        size: 32,
                      ),
                    ),
            ),
            
            const SizedBox(height: 16),
            
            // Name
            Text(
              member.name,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.strongBlue,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 8),
            
            // Role
            Text(
              member.role,
              style: TextStyle(
                fontSize: 16,
                color: AppColors.defaultBlue.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            
            if (member.officeLocation.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 16,
                    color: AppColors.stoneGray,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    member.officeLocation,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.stoneGray,
                    ),
                  ),
                ],
              ),
            ],
            
            const SizedBox(height: 32),
            
            // Contact Actions
            Row(
              children: [
                if (member.email.isNotEmpty) ...[
                  Expanded(
                    child: _ContactButton(
                      icon: Icons.email_outlined,
                      label: 'Email',
                      onTap: () => _launchEmail(member.email),
                    ),
                  ),
                  if (member.phone.isNotEmpty) const SizedBox(width: 12),
                ],
                if (member.phone.isNotEmpty) ...[
                  Expanded(
                    child: _ContactButton(
                      icon: Icons.phone_outlined,
                      label: 'Call',
                      onTap: () => _launchPhone(member.phone),
                    ),
                  ),
                ],
              ],
            ),
            
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _launchEmail(String email) async {
    final uri = Uri.parse('mailto:$email');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _launchPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}

class _ContactButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ContactButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_ContactButton> createState() => _ContactButtonState();
}

class _ContactButtonState extends State<_ContactButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        decoration: BoxDecoration(
          color: _isPressed
              ? AppColors.defaultBlue
              : AppColors.defaultBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.defaultBlue.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.icon,
              color: _isPressed ? AppColors.white : AppColors.defaultBlue,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: TextStyle(
                color: _isPressed ? AppColors.white : AppColors.defaultBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
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
    if (_isHttpUrl(uri)) {
      return Image.network(
        uri,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _placeholder();
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _loading();
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
            return _placeholder();
          },
        );
      }
    }

    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      width: width,
      height: height,
      color: AppColors.cloud,
      child: const Center(
        child: Icon(
          Icons.person,
          color: AppColors.defaultBlue,
          size: 20,
        ),
      ),
    );
  }

  Widget _loading() {
    return Container(
      width: width,
      height: height,
      color: AppColors.cloud,
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}