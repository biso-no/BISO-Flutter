import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/public_profile_model.dart';
import '../../../providers/campus/campus_provider.dart';
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

  void _toggleUser(String userId) {
    setState(() {
      if (_selectedUserIds.contains(userId)) {
        _selectedUserIds.remove(userId);
      } else {
        if (widget.multiSelect) {
          _selectedUserIds.add(userId);
        } else {
          _selectedUserIds = [userId];
        }
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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(widget.title),
        actions: [
          if (_selectedUserIds.isNotEmpty)
            TextButton(
              onPressed: _onDone,
              child: Text(
                widget.multiSelect
                    ? 'Done (${_selectedUserIds.length})'
                    : 'Select',
                style: const TextStyle(color: AppColors.defaultBlue),
              ),
            ),
        ],
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 1,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name or email...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: AppColors.surface,
              ),
            ),
          ),

          // Selected users chips (if multi-select)
          if (widget.multiSelect && _selectedUserIds.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: _selectedUserIds.map((userId) {
                  final profile = _searchResults.firstWhere(
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
                    backgroundColor: AppColors.subtleBlue,
                  );
                }).toList(),
              ),
            ),

          const SizedBox(height: 16),

          // Search results
          Expanded(child: _buildSearchResults()),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchQuery.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 64, color: AppColors.onSurfaceVariant),
            SizedBox(height: 16),
            Text(
              'Start typing to search users',
              style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchResults.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off, size: 64, color: AppColors.onSurfaceVariant),
            SizedBox(height: 16),
            Text(
              'No users found',
              style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final profile = _searchResults[index];
        final isSelected = _selectedUserIds.contains(profile.userId);

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.subtleBlue,
            backgroundImage: profile.avatar != null
                ? NetworkImage(profile.avatar!)
                : null,
            child: profile.avatar == null
                ? Text(
                    profile.name.isNotEmpty
                        ? profile.name[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: AppColors.defaultBlue,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          title: Text(
            profile.name,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: profile.displayEmail != null
              ? Text(profile.displayEmail!)
              : null,
          trailing: isSelected
              ? const Icon(Icons.check_circle, color: AppColors.defaultBlue)
              : const Icon(
                  Icons.radio_button_unchecked,
                  color: AppColors.onSurfaceVariant,
                ),
          onTap: () {
            _toggleUser(profile.userId);

            // If single select, immediately return
            if (!widget.multiSelect && _selectedUserIds.isNotEmpty) {
              _onDone();
            }
          },
        );
      },
    );
  }
}
