import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/campus_model.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/auth/auth_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  // Form data
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _zipController = TextEditingController();

  String? _selectedCampusId;
  // Department selection removed

  final List<CampusModel> _campuses = const [
    CampusModel(
      id: AppConstants.osloId,
      name: 'Oslo',
      description: 'Main campus in Norway\'s capital',
      location: 'Oslo, Norway',
      imageUrl: '',
      heroImageUrl: '',
      stats: CampusStats(),
    ),
    CampusModel(
      id: AppConstants.bergenId,
      name: 'Bergen',
      description: 'Beautiful coastal campus',
      location: 'Bergen, Norway',
      imageUrl: '',
      heroImageUrl: '',
      stats: CampusStats(),
    ),
    CampusModel(
      id: AppConstants.trondheimId,
      name: 'Trondheim',
      description: 'Historic university city campus',
      location: 'Trondheim, Norway',
      imageUrl: '',
      heroImageUrl: '',
      stats: CampusStats(),
    ),
    CampusModel(
      id: AppConstants.stavangerId,
      name: 'Stavanger',
      description: 'Energy sector hub campus',
      location: 'Stavanger, Norway',
      imageUrl: '',
      heroImageUrl: '',
      stats: CampusStats(),
    ),
  ];

  // Department selection removed

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _zipController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < 1) {
      setState(() => _currentStep++);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _completeOnboarding() async {
    try {
      await ref
          .read(authStateProvider.notifier)
          .createProfile(
            name: _nameController.text,
            phone: _phoneController.text.isNotEmpty
                ? _phoneController.text
                : null,
            address: _addressController.text.isNotEmpty
                ? _addressController.text
                : null,
            city: _cityController.text.isNotEmpty ? _cityController.text : null,
            zipCode: _zipController.text.isNotEmpty
                ? _zipController.text
                : null,
            campusId: _selectedCampusId,
          );

      if (mounted) {
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    return Scaffold(
      appBar: AppBar(
        leading: _currentStep > 0
            ? IconButton(
                onPressed: _previousStep,
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        title: Text('${_currentStep + 1} / 2'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            LinearProgressIndicator(
              value: (_currentStep + 1) / 2,
              backgroundColor: AppColors.gray200,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.defaultBlue,
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: Platform.isIOS
                    ? ScrollViewKeyboardDismissBehavior.manual
                    : ScrollViewKeyboardDismissBehavior.onDrag,
                child: SizedBox(
                  height: MediaQuery.of(context).size.height - 200, // Account for app bar and progress bar
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (index) => setState(() => _currentStep = index),
                    children: [
                      _PersonalInfoStep(
                        nameController: _nameController,
                        phoneController: _phoneController,
                        addressController: _addressController,
                        cityController: _cityController,
                        zipController: _zipController,
                        onNext: _nextStep,
                      ),
                      _CampusSelectionStep(
                        campuses: _campuses,
                        selectedCampusId: _selectedCampusId,
                        onCampusSelected: (campusId) {
                          setState(() => _selectedCampusId = campusId);
                        },
                        onNext: _completeOnboarding,
                        isLoading: authState.isLoading,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonalInfoStep extends StatefulWidget {
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController addressController;
  final TextEditingController cityController;
  final TextEditingController zipController;
  final VoidCallback onNext;

  const _PersonalInfoStep({
    required this.nameController,
    required this.phoneController,
    required this.addressController,
    required this.cityController,
    required this.zipController,
    required this.onNext,
  });

  @override
  State<_PersonalInfoStep> createState() => _PersonalInfoStepState();
}

class _PersonalInfoStepState extends State<_PersonalInfoStep> {
  final _formKey = GlobalKey<FormState>();
  final FocusNode _zipFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();
  bool _zipFieldFocused = false;
  bool _phoneFieldFocused = false;

  @override
  void initState() {
    super.initState();
    _zipFocusNode.addListener(() {
      setState(() => _zipFieldFocused = _zipFocusNode.hasFocus);
    });
    _phoneFocusNode.addListener(() {
      setState(() => _phoneFieldFocused = _phoneFocusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _zipFocusNode.dispose();
    _phoneFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20), // Extra space at top for better UX
            Text(
              l10n.personalInfoMessage,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: AppColors.strongBlue,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tell us a bit about yourself',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 32),

            TextFormField(
              controller: widget.nameController,
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

            Column(
              children: [
                TextFormField(
                  controller: widget.phoneController,
                  focusNode: _phoneFocusNode,
                  decoration: InputDecoration(
                    labelText: l10n.phoneMessage,
                    prefixIcon: const Icon(Icons.phone_outlined),
                    hintText: '123 45 678',
                  ),
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                ),
                if (Platform.isIOS && _phoneFieldFocused)
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

            const SizedBox(height: 16),

            TextFormField(
              controller: widget.addressController,
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
                    controller: widget.cityController,
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
                        controller: widget.zipController,
                        focusNode: _zipFocusNode,
                        decoration: InputDecoration(
                          labelText: l10n.zipCodeMessage,
                          prefixIcon: const Icon(Icons.local_post_office_outlined),
                        ),
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
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

            const Spacer(),

            Padding(
              padding: const EdgeInsets.only(bottom: 20), // Extra padding for keyboard
              child: ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    widget.onNext();
                  }
                },
                child: Text(l10n.continueButtonMessage),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CampusSelectionStep extends StatelessWidget {
  final List<CampusModel> campuses;
  final String? selectedCampusId;
  final Function(String) onCampusSelected;
  final VoidCallback onNext;
  final bool isLoading;

  const _CampusSelectionStep({
    required this.campuses,
    required this.selectedCampusId,
    required this.onCampusSelected,
    required this.onNext,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.selectCampusMessage,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: AppColors.strongBlue,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose your BI campus location',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 32),

          Expanded(
            child: ListView.separated(
              itemCount: campuses.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final campus = campuses[index];
                final isSelected = selectedCampusId == campus.id;

                return Card(
                  color: isSelected ? AppColors.subtleBlue : null,
                  child: InkWell(
                    onTap: () => onCampusSelected(campus.id),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.defaultBlue
                                  : AppColors.defaultBlue.withValues(
                                      alpha: 0.1,
                                    ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.location_city,
                              color: isSelected
                                  ? Colors.white
                                  : AppColors.defaultBlue,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  campus.name,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  campus.description,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Icon(
                              Icons.check_circle,
                              color: AppColors.defaultBlue,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.only(bottom: 20), // Extra padding for keyboard
            child: ElevatedButton(
              onPressed: (selectedCampusId != null && !isLoading)
                  ? onNext
                  : null,
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    )
                  : Text(l10n.completeSetupMessage),
            ),
          ),
        ],
      ),
    );
  }
}
