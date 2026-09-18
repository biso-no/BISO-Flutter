import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/models/user_model.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../widgets/biso/biso.dart';

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

  // Preserved across edits though this screen has no UI to change them.
  List<String> _selectedDepartments = [];

  // The profile's own campus. Deliberately separate from the campus the home
  // screen filters by (filterCampusStateProvider), which this screen never
  // touches.
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
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
              leading: const Icon(CupertinoIcons.camera),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.photo),
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
          const SnackBar(content: Text('Profile updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating profile: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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

    return Form(
      key: _formKey,
      child: BisoPage(
        title: 'Edit Profile',
        largeTitle: false,
        actions: [
          BisoHeaderAction(
            icon: CupertinoIcons.checkmark,
            tooltip: 'Save',
            onPressed: _isLoading ? null : _saveProfile,
          ),
        ],
        slivers: [
          SliverToBoxAdapter(child: _buildAvatar(authState.user)),
          SliverToBoxAdapter(
            child: Builder(
              builder: (context) => _buildPersonalInfoGroup(context),
            ),
          ),
          SliverToBoxAdapter(child: _buildCampusGroup()),
          SliverToBoxAdapter(
            child: Builder(builder: (context) => _buildAddressGroup(context)),
          ),
        ],
      ),
    );
  }

  /// [context] must be a descendant of the enclosing [BisoPage] (obtained via
  /// a [Builder] at each call site) so a focused field's keyboard clearance
  /// accounts for the translucent header, mirroring `sell_product_screen.dart`.
  EdgeInsets _scrollPaddingFor(BuildContext context) {
    final insets = BisoPageInsets.maybeOf(context);
    return insets != null
        ? EdgeInsets.fromLTRB(20, insets.top + 20, 20, insets.bottom + 20)
        : const EdgeInsets.all(20);
  }

  Widget _buildAvatar(UserModel? user) {
    return Builder(
      builder: (context) {
        final palette = BisoPalette.of(context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: Center(
            child: SizedBox(
              width: 96,
              height: 96,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: palette.surfaceRaised,
                    backgroundImage: _selectedImage != null
                        ? FileImage(File(_selectedImage!.path)) as ImageProvider
                        : (user?.avatarUrl != null
                              ? NetworkImage(user!.avatarUrl!)
                              : null),
                    child: (_selectedImage == null && user?.avatarUrl == null)
                        ? Icon(
                            CupertinoIcons.person_fill,
                            size: 44,
                            color: palette.muted,
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: -6,
                    right: -6,
                    // A plain raised circle: glass is for floating chrome
                    // only (spec §1.4), and this button sits on content.
                    child: Material(
                      color: palette.surfaceRaised,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: IconButton(
                        icon: Icon(
                          CupertinoIcons.camera_fill,
                          size: 22,
                          color: palette.ink,
                        ),
                        tooltip:
                            AppLocalizations.of(context)?.changePhotoMessage ??
                            'Change photo',
                        onPressed: _pickImage,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPersonalInfoGroup(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scrollPadding = _scrollPaddingFor(context);
    return BisoFormGroup(
      title: 'Personal Information',
      children: [
        BisoFormRow(
          label: l10n.nameMessage,
          child: TextFormField(
            controller: _nameController,
            scrollPadding: scrollPadding,
            decoration: bisoInputDecoration(
              context,
              prefixIcon: const Icon(CupertinoIcons.person),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Name is required';
              }
              return null;
            },
            textInputAction: TextInputAction.next,
          ),
        ),
        BisoFormRow(
          label: l10n.phoneMessage,
          child: TextFormField(
            controller: _phoneController,
            scrollPadding: scrollPadding,
            decoration: bisoInputDecoration(
              context,
              prefixIcon: const Icon(CupertinoIcons.phone),
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
        ),
      ],
    );
  }

  Widget _buildCampusGroup() {
    return Builder(
      builder: (context) {
        final palette = BisoPalette.of(context);
        return BisoSection(
          title: 'Campus',
          footer:
              'Your home campus. This does not change which campus the '
              'home screen shows.',
          child: BisoListGroup(
            children: [
              for (final campus in AppConstants.campusNames.entries)
                BisoListRow(
                  leading: BisoIconTile(
                    icon: CupertinoIcons.building_2_fill,
                    accent: _selectedCampusId == campus.key
                        ? BisoAccent.blue
                        : BisoAccent.neutral,
                  ),
                  title: campus.value,
                  showChevron: false,
                  trailing: _selectedCampusId == campus.key
                      ? Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          color: palette.link,
                        )
                      : null,
                  onTap: () => setState(() => _selectedCampusId = campus.key),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAddressGroup(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = BisoPalette.of(context);
    final scrollPadding = _scrollPaddingFor(context);
    return BisoFormGroup(
      title: 'Address Information',
      children: [
        BisoFormRow(
          label: l10n.addressMessage,
          child: TextFormField(
            controller: _addressController,
            scrollPadding: scrollPadding,
            decoration: bisoInputDecoration(
              context,
              prefixIcon: const Icon(CupertinoIcons.house),
            ),
            textInputAction: TextInputAction.next,
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: BisoFormRow(
                label: l10n.cityMessage,
                child: TextFormField(
                  controller: _cityController,
                  scrollPadding: scrollPadding,
                  decoration: bisoInputDecoration(
                    context,
                    prefixIcon: const Icon(CupertinoIcons.building_2_fill),
                  ),
                  textInputAction: TextInputAction.next,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                children: [
                  BisoFormRow(
                    label: l10n.zipCodeMessage,
                    child: TextFormField(
                      controller: _zipController,
                      focusNode: _zipFocusNode,
                      scrollPadding: scrollPadding,
                      decoration: bisoInputDecoration(
                        context,
                        prefixIcon: const Icon(CupertinoIcons.mail),
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
                  ),
                  if (Platform.isIOS && _zipFieldFocused)
                    Container(
                      width: double.infinity,
                      height: 40,
                      color: palette.surfaceRaised,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => FocusScope.of(context).unfocus(),
                            child: Text(
                              'Done',
                              style: TextStyle(color: palette.link),
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
      ],
    );
  }
}
