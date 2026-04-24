import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/favorites_storage.dart';
import '../../../data/models/user_model.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/auth/auth_provider.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _zipController = TextEditingController();
  final _zipFocusNode = FocusNode();

  List<String> _selectedDepartments = [];
  String? _selectedCampusId;
  XFile? _selectedImage;
  bool _isLoading = false;
  bool _didPrefillFromUser = false;
  bool _zipFieldFocused = false;

  @override
  void initState() {
    super.initState();
    _zipFocusNode.addListener(() {
      setState(() => _zipFieldFocused = _zipFocusNode.hasFocus);
    });
    _initializeData();
  }

  void _initializeData() {
    final user = ref.read(authStateProvider).user;
    if (user != null) {
      _applyUser(user);
      _didPrefillFromUser = true;
    }
  }

  void _applyUser(UserModel user) {
    // Only prefill empty fields to avoid overriding user edits
    if (_nameController.text.isEmpty) _nameController.text = user.name;
    if (_phoneController.text.isEmpty) {
      _phoneController.text = user.phone ?? '';
    }
    if (_addressController.text.isEmpty) {
      _addressController.text = user.address ?? '';
    }
    if (_cityController.text.isEmpty) {
      _cityController.text = user.city ?? '';
    }
    if (_zipController.text.isEmpty) {
      _zipController.text = user.zipCode ?? '';
    }

    setState(() {
      _selectedDepartments = List.from(user.departments);
      _selectedCampusId = user.campusId;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _zipController.dispose();
    _zipFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final source = await _showImageSourceDialog();
    if (source == null) return;

    final picker = ImagePicker();
    try {
      final image = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() => _selectedImage = image);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    return showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Image Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await ref
          .read(authStateProvider.notifier)
          .updateProfile(
            name: _nameController.text.trim(),
            phone: _phoneController.text.trim().isNotEmpty
                ? _phoneController.text.trim()
                : null,
            address: _addressController.text.trim().isNotEmpty
                ? _addressController.text.trim()
                : null,
            city: _cityController.text.trim().isNotEmpty
                ? _cityController.text.trim()
                : null,
            zipCode: _zipController.text.trim().isNotEmpty
                ? _zipController.text.trim()
                : null,
            campusId: _selectedCampusId,
            departments: _selectedDepartments,
            avatarFile: _selectedImage,
          );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully'),
            backgroundColor: AppColors.green9,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating profile: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final authState = ref.watch(authStateProvider);

    // Listen for auth state changes and prefill once when user becomes available
    ref.listen(authStateProvider, (previous, next) {
      final user = next.user;
      if (!_didPrefillFromUser && user != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _applyUser(user);
            _didPrefillFromUser = true;
          }
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveProfile,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          keyboardDismissBehavior: Platform.isIOS
              ? ScrollViewKeyboardDismissBehavior.manual
              : ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Avatar Section
              Center(
                child: Stack(
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.defaultBlue,
                          width: 3,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 48,
                        backgroundImage: _selectedImage != null
                            ? FileImage(File(_selectedImage!.path))
                                  as ImageProvider
                            : (authState.user?.avatarUrl != null
                                  ? NetworkImage(authState.user!.avatarUrl!)
                                  : null),
                        backgroundColor: AppColors.gray200,
                        child:
                            (_selectedImage == null &&
                                authState.user?.avatarUrl == null)
                            ? const Icon(
                                Icons.person,
                                size: 50,
                                color: AppColors.defaultBlue,
                              )
                            : null,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: InkWell(
                        onTap: _pickImage,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.defaultBlue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Personal Information
              Text(
                'Personal Information',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: l10n.nameMessage,
                  prefixIcon: const Icon(Icons.person_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Name is required';
                  }
                  return null;
                },
                textInputAction: TextInputAction.next,
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _phoneController,
                decoration: InputDecoration(
                  labelText: l10n.phoneMessage,
                  prefixIcon: const Icon(Icons.phone_outlined),
                  hintText: '+47 123 45 678',
                ),
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value != null && value.isNotEmpty) {
                    // Basic Norwegian phone number validation
                    final phoneRegex = RegExp(r'^\+47\s?\d{8}$|^\d{8}$');
                    if (!phoneRegex.hasMatch(value.replaceAll(' ', ''))) {
                      return 'Please enter a valid Norwegian phone number';
                    }
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // Address Information
              Text(
                'Address Information',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _addressController,
                decoration: InputDecoration(
                  labelText: l10n.addressMessage,
                  prefixIcon: const Icon(Icons.home_outlined),
                ),
                textInputAction: TextInputAction.next,
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cityController,
                      decoration: InputDecoration(
                        labelText: l10n.cityMessage,
                        prefixIcon: const Icon(Icons.location_city_outlined),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _zipController,
                          focusNode: _zipFocusNode,
                          decoration: InputDecoration(
                            labelText: l10n.zipCodeMessage,
                            prefixIcon: const Icon(
                              Icons.local_post_office_outlined,
                            ),
                          ),
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ],
                          validator: (value) {
                            if (value != null && value.isNotEmpty) {
                              // Norwegian postal code validation (4 digits)
                              if (value.length != 4 ||
                                  !RegExp(r'^\d{4}$').hasMatch(value)) {
                                return 'Invalid zip code';
                              }
                            }
                            return null;
                          },
                        ),
                        if (Platform.isIOS && _zipFieldFocused)
                          Container(
                            width: double.infinity,
                            height: 40,
                            color: AppColors.gray100,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => FocusScope.of(context).unfocus(),
                                  child: const Text(
                                    'Done',
                                    style: TextStyle(
                                      color: AppColors.defaultBlue,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),
/*
              // Interests/Departments (from DB)
              Text(
                'Interests & Departments',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),

              const SizedBox(height: 16),

              _DepartmentPicker(
                departments: _departments,
                initiallySelectedIds: _selectedDepartments,
                onSelectionChanged: (ids) =>
                    setState(() => _selectedDepartments = ids),
                onToggleFavorite: _toggleFavorite,
              ),
*/
              const SizedBox(height: 32),
/*
              // Campus Information (from DB)
              Text(
                'Campus Information',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.strongBlue,
                ),
              ),

              const SizedBox(height: 16),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select your home campus',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ..._campuses.map((campus) {
                        final isSelected = _selectedCampusId == campus['id'];

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedCampusId = campus['id'];
                                _selectedDepartments.clear();
                                _departments.clear();
                              });
                              _loadDepartments(_selectedCampusId!);
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.defaultBlue
                                      : AppColors.outline,
                                  width: isSelected ? 2 : 1,
                                ),
                                color: isSelected
                                    ? AppColors.defaultBlue.withValues(
                                        alpha: 0.1,
                                      )
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: AppColors.defaultBlue,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.location_city,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          campus['name']!,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(
                                      Icons.check_circle,
                                      color: AppColors.defaultBlue,
                                      size: 24,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
*/
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _DepartmentPicker extends StatefulWidget {
  final List<Map<String, String>> departments;
  final List<String> initiallySelectedIds;
  final ValueChanged<List<String>> onSelectionChanged;
  final Future<void> Function(String) onToggleFavorite;

  const _DepartmentPicker({
    required this.departments,
    required this.initiallySelectedIds,
    required this.onSelectionChanged,
    required this.onToggleFavorite,
  });

  @override
  State<_DepartmentPicker> createState() => _DepartmentPickerState();
}

class _DepartmentPickerState extends State<_DepartmentPicker> {
  late List<String> _selected;
  List<String> _favorites = [];
  String _search = '';

  @override
  void initState() {
    super.initState();
    _selected = List.of(widget.initiallySelectedIds);
    _loadFavs();
  }

  Future<void> _loadFavs() async {
    final ids = await FavoritesStorage.getFavoriteDepartmentIds();
    if (mounted) setState(() => _favorites = ids);
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
    widget.onSelectionChanged(_selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lower = _search.trim().toLowerCase();
    final filtered = lower.isEmpty
        ? widget.departments
        : widget.departments
              .where(
                (d) =>
                    d['name']!.toLowerCase().contains(lower) ||
                    d['id']!.toLowerCase().contains(lower),
              )
              .toList();

    final favoriteItems = filtered
        .where((d) => _favorites.contains(d['id']))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search field (custom minimal)
        Container(
          decoration: BoxDecoration(
            color: AppColors.gray50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.outline),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(
                Icons.search_rounded,
                color: AppColors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration.collapsed(
                    hintText: 'Search departments by name or ID',
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              if (_search.isNotEmpty)
                InkWell(
                  onTap: () => setState(() => _search = ''),
                  child: const Icon(Icons.close_rounded, size: 18),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (favoriteItems.isNotEmpty) ...[
          Text(
            'Favorites',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _buildWrap(theme, favoriteItems),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _buildWrap(ThemeData theme, List<Map<String, String>> items) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((dept) {
        final id = dept['id']!;
        final name = dept['name']!;
        final selected = _selected.contains(id);
        final favored = _favorites.contains(id);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.defaultBlue.withValues(alpha: 0.12)
                : AppColors.gray50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.defaultBlue : AppColors.outline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () async {
                  await widget.onToggleFavorite(id);
                  _loadFavs();
                },
                child: Icon(
                  favored ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 18,
                  color: favored
                      ? AppColors.orange9
                      : AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _toggleSelect(id),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selected)
                      const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: AppColors.defaultBlue,
                      ),
                    if (selected) const SizedBox(width: 6),
                    Text(
                      name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
