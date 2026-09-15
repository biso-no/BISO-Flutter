import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/models/campus_model.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../widgets/biso/biso.dart';

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
            backgroundColor: BisoPalette.of(context).error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    return BisoPage(
      title: '${_currentStep + 1} / 2',
      largeTitle: false,
      automaticallyImplyLeading: false,
      leading: _currentStep > 0
          ? BisoBackButton(onPressed: _previousStep)
          : null,
      notificationDepth: 1,
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _PersonalInfoStep(
            nameController: _nameController,
            phoneController: _phoneController,
            addressController: _addressController,
            cityController: _cityController,
            zipController: _zipController,
            currentStep: _currentStep,
            onNext: _nextStep,
          ),
          _CampusSelectionStep(
            campuses: _campuses,
            selectedCampusId: _selectedCampusId,
            currentStep: _currentStep,
            onCampusSelected: (campusId) {
              setState(() => _selectedCampusId = campusId);
            },
            onNext: _completeOnboarding,
            isLoading: authState.isLoading,
          ),
        ],
      ),
    );
  }
}

/// The step's own scroll view sits below [BisoPage]'s `body:` (a PageView is
/// not a descendant of the header's internal CustomScrollView, so BisoPage
/// cannot add clearance for it automatically) — [BisoPageInsets.maybeOf]
/// resolves from this widget's own build context, which is already inside
/// [BisoPageInsets] because the PageView that hosts it is BisoPage's `body`.
class _PersonalInfoStep extends StatefulWidget {
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController addressController;
  final TextEditingController cityController;
  final TextEditingController zipController;
  final int currentStep;
  final VoidCallback onNext;

  const _PersonalInfoStep({
    required this.nameController,
    required this.phoneController,
    required this.addressController,
    required this.cityController,
    required this.zipController,
    required this.currentStep,
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
    final palette = BisoPalette.of(context);
    final insets = BisoPageInsets.maybeOf(context);
    final topInset = insets?.top ?? 0.0;
    final bottomInset = insets?.bottom ?? 0.0;

    return Form(
      key: _formKey,
      child: CustomScrollView(
        keyboardDismissBehavior: Platform.isIOS
            ? ScrollViewKeyboardDismissBehavior.manual
            : ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(key: const ValueKey('step-top-inset'), height: topInset),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: LinearProgressIndicator(
                value: (widget.currentStep + 1) / 2,
                backgroundColor: palette.hairline,
                valueColor: AlwaysStoppedAnimation<Color>(palette.link),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.personalInfoMessage,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tell us a bit about yourself',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: palette.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: BisoFormGroup(
                children: [
                  BisoFormRow(
                    label: l10n.nameMessage,
                    child: TextFormField(
                      controller: widget.nameController,
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: widget.phoneController,
                          focusNode: _phoneFocusNode,
                          decoration: bisoInputDecoration(
                            context,
                            prefixIcon: const Icon(CupertinoIcons.phone),
                            hintText: '123 45 678',
                          ),
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                        ),
                        if (Platform.isIOS && _phoneFieldFocused)
                          _DoneBar(
                            color: palette.surfaceRaised,
                            textColor: palette.link,
                            onDone: () => FocusScope.of(context).unfocus(),
                          ),
                      ],
                    ),
                  ),
                  BisoFormRow(
                    label: l10n.addressMessage,
                    child: TextFormField(
                      controller: widget.addressController,
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
                            controller: widget.cityController,
                            decoration: bisoInputDecoration(
                              context,
                              prefixIcon: const Icon(
                                CupertinoIcons.building_2_fill,
                              ),
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                      ),
                      Expanded(
                        child: BisoFormRow(
                          label: l10n.zipCodeMessage,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: widget.zipController,
                                focusNode: _zipFocusNode,
                                decoration: bisoInputDecoration(
                                  context,
                                  prefixIcon: const Icon(
                                    CupertinoIcons.number_square,
                                  ),
                                ),
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(4),
                                ],
                              ),
                              if (Platform.isIOS && _zipFieldFocused)
                                _DoneBar(
                                  color: palette.surfaceRaised,
                                  textColor: palette.link,
                                  onDone: () =>
                                      FocusScope.of(context).unfocus(),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: FilledButton(
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      widget.onNext();
                    }
                  },
                  child: Text(l10n.continueButtonMessage),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: bottomInset + 16)),
        ],
      ),
    );
  }
}

/// A small inline "Done" affordance under a focused field, replacing the
/// keyboard's own accessory bar. [color]/[textColor] come from the caller so
/// this stays palette-agnostic.
class _DoneBar extends StatelessWidget {
  const _DoneBar({
    required this.color,
    required this.textColor,
    required this.onDone,
  });

  final Color color;
  final Color textColor;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    height: 40,
    color: color,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: onDone,
          child: Text(
            'Done',
            style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _CampusSelectionStep extends StatelessWidget {
  final List<CampusModel> campuses;
  final String? selectedCampusId;
  final int currentStep;
  final Function(String) onCampusSelected;
  final VoidCallback onNext;
  final bool isLoading;

  const _CampusSelectionStep({
    required this.campuses,
    required this.selectedCampusId,
    required this.currentStep,
    required this.onCampusSelected,
    required this.onNext,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);
    final insets = BisoPageInsets.maybeOf(context);
    final topInset = insets?.top ?? 0.0;
    final bottomInset = insets?.bottom ?? 0.0;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(key: const ValueKey('step-top-inset'), height: topInset),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: LinearProgressIndicator(
              value: (currentStep + 1) / 2,
              backgroundColor: palette.hairline,
              valueColor: AlwaysStoppedAnimation<Color>(palette.link),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.selectCampusMessage,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose your BI campus location',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: palette.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverBisoListGroup(
            itemCount: campuses.length,
            itemBuilder: (context, index) {
              final campus = campuses[index];
              final isSelected = selectedCampusId == campus.id;

              return ColoredBox(
                color: isSelected
                    ? palette.link.withValues(alpha: 0.08)
                    : Colors.transparent,
                child: BisoListRow(
                  leading: BisoIconTile(
                    icon: CupertinoIcons.building_2_fill,
                    accent: isSelected ? BisoAccent.blue : BisoAccent.neutral,
                  ),
                  title: campus.name,
                  subtitle: campus.description,
                  trailing: isSelected
                      ? Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          color: palette.link,
                        )
                      : null,
                  onTap: () => onCampusSelected(campus.id),
                ),
              );
            },
          ),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: FilledButton(
                onPressed: (selectedCampusId != null && !isLoading)
                    ? onNext
                    : null,
                child: isLoading
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            palette.onPrimary,
                          ),
                        ),
                      )
                    : Text(l10n.completeSetupMessage),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: bottomInset + 16)),
      ],
    );
  }
}
