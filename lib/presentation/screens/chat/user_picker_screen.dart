import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/public_profile_model.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../widgets/biso/biso.dart';
import 'chat_list_screen.dart';

class UserPickerScreen extends ConsumerStatefulWidget {
  final List<String> excludeUserIds;
  final String title;
  final bool multiSelect;

  const UserPickerScreen({
    super.key,
    this.excludeUserIds = const [],
    this.title = 'Select Users',
    this.multiSelect = true,
  });

  @override
  ConsumerState<UserPickerScreen> createState() => _UserPickerScreenState();
}

class _UserPickerScreenState extends ConsumerState<UserPickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<PublicProfileModel> _searchResults = [];
  List<String> _selectedUserIds = [];

  /// Profiles of the selected users, keyed by user id, so a chip keeps its
  /// name after the query that found the user changes or is cleared.
  final Map<String, PublicProfileModel> _selectedProfiles = {};
  bool _isLoading = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query != _searchQuery) {
      _searchQuery = query;
      _searchUsers(query);
    }
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final chatService = ref.read(chatServiceProvider);
      final selectedCampus = ref.read(selectedCampusProvider);
      final results = await chatService.searchUsers(
        query,
        campusId: selectedCampus.id,
      );

      // Filter out excluded users
      final filteredResults = results.where((profile) {
        return !widget.excludeUserIds.contains(profile.userId);
      }).toList();

      setState(() {
        _searchResults = filteredResults;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _searchResults = [];
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Search failed: $e')));
      }
    }
  }

  void _toggleUser(String userId, [PublicProfileModel? profile]) {
    setState(() {
      if (_selectedUserIds.contains(userId)) {
        _selectedUserIds.remove(userId);
        _selectedProfiles.remove(userId);
      } else {
        if (widget.multiSelect) {
          _selectedUserIds.add(userId);
        } else {
          _selectedUserIds = [userId];
          _selectedProfiles.clear();
        }
        if (profile != null) _selectedProfiles[userId] = profile;
      }
    });
  }

  void _onDone() {
    if (_selectedUserIds.isNotEmpty) {
      context.pop(_selectedUserIds);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BisoPage(
      title: widget.title,
      largeTitle: false,
      actions: [
        if (_selectedUserIds.isNotEmpty)
          BisoHeaderAction(
            icon: CupertinoIcons.checkmark,
            tooltip: widget.multiSelect
                ? 'Done (${_selectedUserIds.length})'
                : 'Select',
            badge: widget.multiSelect ? _selectedUserIds.length : null,
            onPressed: _onDone,
          ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Search by name or email...',
                prefixIcon: Icon(CupertinoIcons.search),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(child: _buildSelectedChips(context)),
        ..._buildResultsSlivers(context),
      ],
    );
  }

  Widget _buildSelectedChips(BuildContext context) {
    if (!widget.multiSelect || _selectedUserIds.isEmpty) {
      return const SizedBox.shrink();
    }
    final palette = BisoPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        spacing: 8,
        children: _selectedUserIds.map((userId) {
          final profile =
              _selectedProfiles[userId] ??
              _searchResults.firstWhere(
                (p) => p.userId == userId,
                orElse: () => PublicProfileModel(
                  id: '',
                  userId: userId,
                  name: 'Selected User',
                ),
              );

          return Chip(
            label: Text(profile.name),
            onDeleted: () => _toggleUser(userId),
            backgroundColor: palette.surfaceRaised,
          );
        }).toList(),
      ),
    );
  }

  List<Widget> _buildResultsSlivers(BuildContext context) {
    if (_searchQuery.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: BisoEmptyState(
            icon: CupertinoIcons.search,
            title: 'Start typing to search users',
            accent: BisoAccent.teal,
          ),
        ),
      ];
    }

    if (_isLoading) {
      return [SliverToBoxAdapter(child: BisoSkeleton.rows())];
    }

    if (_searchResults.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: BisoEmptyState(
            icon: CupertinoIcons.person_crop_circle_badge_xmark,
            title: 'No users found',
            accent: BisoAccent.teal,
          ),
        ),
      ];
    }

    return [
      SliverBisoListGroup(
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          final profile = _searchResults[index];
          final isSelected = _selectedUserIds.contains(profile.userId);
          final palette = BisoPalette.of(context);

          return BisoListRow(
            leading: CircleAvatar(
              backgroundColor: BisoAccent.teal.fill(context),
              backgroundImage: profile.avatar != null
                  ? NetworkImage(profile.avatar!)
                  : null,
              child: profile.avatar == null
                  ? Text(
                      profile.name.isNotEmpty
                          ? profile.name[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        color: BisoAccent.teal.glyph(context),
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : null,
            ),
            title: profile.name,
            subtitle: profile.displayEmail,
            showChevron: false,
            trailing: isSelected
                ? Icon(
                    CupertinoIcons.checkmark_circle_fill,
                    color: palette.link,
                  )
                : null,
            onTap: () {
              _toggleUser(profile.userId, profile);

              // If single select, immediately return
              if (!widget.multiSelect && _selectedUserIds.isNotEmpty) {
                _onDone();
              }
            },
          );
        },
      ),
    ];
  }
}
