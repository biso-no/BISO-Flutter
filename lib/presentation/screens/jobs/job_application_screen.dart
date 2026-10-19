import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/job_application.dart';
import '../../../data/models/job_model.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/jobs/jobs_provider.dart';
import '../../../providers/membership/membership_overview_provider.dart';
import '../../widgets/biso/biso.dart';
import '../../widgets/premium/premium_html_renderer.dart';

/// The country codes the web's apply form offers, Norway first.
const _countryCodes = <(String, String)>[
  ('+47', '🇳🇴 +47'),
  ('+46', '🇸🇪 +46'),
  ('+45', '🇩🇰 +45'),
  ('+358', '🇫🇮 +358'),
  ('+354', '🇮🇸 +354'),
  ('+44', '🇬🇧 +44'),
  ('+49', '🇩🇪 +49'),
  ('+33', '🇫🇷 +33'),
  ('+34', '🇪🇸 +34'),
  ('+39', '🇮🇹 +39'),
  ('+31', '🇳🇱 +31'),
  ('+32', '🇧🇪 +32'),
  ('+41', '🇨🇭 +41'),
  ('+43', '🇦🇹 +43'),
  ('+48', '🇵🇱 +48'),
  ('+420', '🇨🇿 +420'),
  ('+1', '🇺🇸 +1'),
  ('+61', '🇦🇺 +61'),
  ('+91', '🇮🇳 +91'),
  ('+86', '🇨🇳 +86'),
  ('+81', '🇯🇵 +81'),
  ('+82', '🇰🇷 +82'),
  ('+55', '🇧🇷 +55'),
  ('+52', '🇲🇽 +52'),
  ('+7', '🇷🇺 +7'),
  ('+90', '🇹🇷 +90'),
  ('+92', '🇵🇰 +92'),
  ('+234', '🇳🇬 +234'),
  ('+27', '🇿🇦 +27'),
  ('+20', '🇪🇬 +20'),
];

/// Field limits of the server's application schema, so a long entry is cut
/// short here rather than refused after the upload.
const _maxNameLength = 200;
const _maxLinkedInLength = 500;
const _maxRoleLength = 200;
const _maxAnswerLength = 4000;

/// Applying for a vacancy, in the web form's steps: Contact, Questions (only
/// when the vacancy has any), Documents and Review.
///
/// The checks here are for quick feedback; the server decides, and its
/// message is shown when it refuses.
class JobApplicationScreen extends ConsumerWidget {
  const JobApplicationScreen({super.key, required this.jobId, this.job});

  final String jobId;

  /// The vacancy as the detail page read it. Read again when absent, for a
  /// link straight to the form.
  final JobModel? job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final known = job;
    if (known != null) return _ApplyGate(job: known);

    final l10n = AppLocalizations.of(context)!;
    final detail = ref.watch(jobDetailProvider(jobId));
    return detail.when(
      data: (job) => job == null
          ? _StatePage(
              child: BisoEmptyState(
                icon: CupertinoIcons.briefcase,
                accent: BisoAccent.teal,
                title: l10n.jobNotOpenTitle,
                message: l10n.jobNotOpenBody,
              ),
            )
          : _ApplyGate(job: job),
      loading: () => const _StatePage(child: BisoSkeleton.card()),
      error: (_, _) => _StatePage(
        child: BisoErrorState(
          onRetry: () => ref.invalidate(jobDetailProvider(jobId)),
        ),
      ),
    );
  }
}

/// A page with one centred state, such as loading or a wall before the form.
class _StatePage extends StatelessWidget {
  const _StatePage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => BisoPage(
    title: AppLocalizations.of(context)!.jobApply,
    largeTitle: false,
    leading: BisoBackButton(
      onPressed: () => NavigationUtils.safeGoBack(
        context,
        fallbackRoute: '/explore/volunteer',
      ),
    ),
    slivers: [SliverFillRemaining(hasScrollBody: false, child: child)],
  );
}

/// Shows the form only to someone who may apply. Sign-in comes first: a
/// signed-out visitor has no membership to check yet.
class _ApplyGate extends ConsumerWidget {
  const _ApplyGate({required this.job});

  final JobModel job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final signedIn = ref.watch(
      authStateProvider.select((state) => state.isAuthenticated),
    );
    if (!signedIn) {
      return _StatePage(
        child: BisoEmptyState(
          icon: CupertinoIcons.lock,
          accent: BisoAccent.teal,
          title: l10n.jobApply,
          message: l10n.jobApplySignInMessage,
          action: FilledButton(
            onPressed: () => context.go('/auth/login'),
            child: Text(l10n.jobApplySignInCta),
          ),
        ),
      );
    }
    if (job.membersOnly && !ref.watch(hasValidMembershipProvider)) {
      return _StatePage(
        child: BisoEmptyState(
          icon: CupertinoIcons.star,
          accent: BisoAccent.gold,
          title: l10n.jobApply,
          message: l10n.jobApplyMembersOnlyMessage,
          action: FilledButton(
            onPressed: () => context.push('/profile/membership'),
            child: Text(l10n.jobApplyBecomeMember),
          ),
        ),
      );
    }
    return _ApplicationForm(job: job);
  }
}

enum _Step { contact, questions, documents, review }

enum _Document { coverLetter, resume }

class _ApplicationForm extends ConsumerStatefulWidget {
  const _ApplicationForm({required this.job});

  final JobModel job;

  @override
  ConsumerState<_ApplicationForm> createState() => _ApplicationFormState();
}

class _ApplicationFormState extends ConsumerState<_ApplicationForm> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _linkedIn = TextEditingController();
  final _currentRole = TextEditingController();
  final _employer = TextEditingController();
  final _availability = TextEditingController();
  final _scroll = ScrollController();
  String _countryCode = _countryCodes.first.$1;

  /// Answers typed into text, long text and number questions.
  late final Map<String, TextEditingController> _typedAnswers = {
    for (final question in _questions)
      if (_isTyped(question.type)) question.id: TextEditingController(),
  };

  /// Answers picked for select (`String`), multi-select (`List<String>`, in
  /// the order ticked) and yes/no (`bool`) questions.
  final Map<String, Object?> _pickedAnswers = {};

  late final List<_Step> _steps = [
    _Step.contact,
    if (_questions.isNotEmpty) _Step.questions,
    _Step.documents,
    _Step.review,
  ];
  int _stepIndex = 0;

  ApplicationDocument? _coverLetter;
  ApplicationDocumentProblem? _coverLetterProblem;
  ApplicationDocument? _resume;
  ApplicationDocumentProblem? _resumeProblem;

  bool _consent = false;
  bool _submitting = false;
  bool _submitted = false;
  String? _submitError;

  List<JobQuestion> get _questions => widget.job.customQuestions;
  _Step get _step => _steps[_stepIndex];

  static bool _isTyped(JobQuestionType type) => switch (type) {
    JobQuestionType.text ||
    JobQuestionType.longText ||
    JobQuestionType.number => true,
    _ => false,
  };

  @override
  void initState() {
    super.initState();
    // The account's name, which the student may correct; the email always
    // comes from the account.
    _name.text = ref.read(authStateProvider).user?.name ?? '';
    for (final controller in [_name, _phone, ..._typedAnswers.values]) {
      controller.addListener(_rebuild);
    }
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    for (final controller in [
      _name,
      _phone,
      _linkedIn,
      _currentRole,
      _employer,
      _availability,
      ..._typedAnswers.values,
    ]) {
      controller.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  /// Country code and number together, or empty without a number.
  String get _phoneValue {
    final local = _phone.text.trim();
    return local.isEmpty ? '' : '$_countryCode$local';
  }

  bool get _phoneTooLong => _phoneValue.length > maxApplicantPhoneLength;

  Object? _answer(JobQuestion question) =>
      _typedAnswers[question.id]?.text ?? _pickedAnswers[question.id];

  bool get _contactReady => _name.text.trim().isNotEmpty && !_phoneTooLong;

  bool get _questionsReady => _questions
      .where((question) => question.required)
      .every((question) => isAnswerGiven(_answer(question)));

  bool get _documentsFit =>
      applicationDocumentsFitTogether(_coverLetter, _resume);

  bool get _documentsReady =>
      _coverLetter != null &&
      _coverLetterProblem == null &&
      _resumeProblem == null &&
      (!widget.job.cvRequired || _resume != null) &&
      _documentsFit;

  void _next() {
    if (_stepIndex < _steps.length - 1) _goToStep(_stepIndex + 1);
  }

  void _previous() {
    if (_stepIndex > 0) _goToStep(_stepIndex - 1);
  }

  /// Each step starts at its top, not wherever the last one was scrolled to.
  void _goToStep(int index) {
    setState(() => _stepIndex = index);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _back() {
    if (_stepIndex > 0) {
      _previous();
      return;
    }
    NavigationUtils.safeGoBack(
      context,
      fallbackRoute: '/explore/volunteer/${Uri.encodeComponent(widget.job.id)}',
    );
  }

  Future<void> _pick(_Document document) async {
    final picked = await ref.read(applicationDocumentPickerProvider)();
    if (picked == null || !mounted) return;
    final problem = picked.problem;
    final accepted = problem == null ? picked : null;
    setState(() {
      switch (document) {
        case _Document.coverLetter:
          _coverLetter = accepted;
          _coverLetterProblem = problem;
        case _Document.resume:
          _resume = accepted;
          _resumeProblem = problem;
      }
    });
  }

  void _removeResume() => setState(() {
    _resume = null;
    _resumeProblem = null;
  });

  void _setPicked(String questionId, Object? value) =>
      setState(() => _pickedAnswers[questionId] = value);

  Future<void> _submit() async {
    final coverLetter = _coverLetter;
    if (!_consent || _submitting || coverLetter == null) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _submitting = true;
      _submitError = null;
    });

    final result = await ref
        .read(recruitmentApiClientProvider)
        .submit(
          JobApplicationDraft(
            jobId: widget.job.id,
            applicantName: _name.text.trim(),
            applicantPhone: _phoneValue,
            linkedinUrl: _linkedIn.text.trim(),
            currentRole: _currentRole.text.trim(),
            currentEmployer: _employer.text.trim(),
            availability: _availability.text,
            questions: _questions,
            answers: {
              for (final question in _questions) question.id: _answer(question),
            },
            coverLetter: coverLetter,
            resume: _resume,
          ),
        );
    if (!mounted) return;

    setState(() {
      _submitting = false;
      switch (result) {
        case ApplicationSubmitted():
          _submitted = true;
        case ApplicationRejected(:final code, :final message):
          _submitError = code == ApplicationError.network
              ? l10n.jobApplyNetworkError
              : message;
      }
    });
    if (_submitted) ref.invalidate(myApplicationsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final email = ref.watch(
      authStateProvider.select((state) => state.user?.email ?? ''),
    );

    if (_submitted) {
      return BisoPage(
        title: l10n.jobApply,
        largeTitle: false,
        leading: BisoBackButton(
          onPressed: () => NavigationUtils.safeGoBack(
            context,
            fallbackRoute: '/explore/volunteer',
          ),
        ),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: BisoEmptyState(
              icon: CupertinoIcons.checkmark_circle,
              accent: BisoAccent.teal,
              title: l10n.jobApplySuccessTitle,
              message: l10n.jobApplySuccessBody(email),
              action: FilledButton(
                onPressed: () => context.go('/profile/applications'),
                child: Text(l10n.jobApplyViewMyApplications),
              ),
            ),
          ),
        ],
      );
    }

    final List<Widget> stepSlivers = switch (_step) {
      _Step.contact => _contactSlivers(l10n, email),
      _Step.questions => _questionSlivers(l10n),
      _Step.documents => _documentSlivers(l10n),
      _Step.review => _reviewSlivers(l10n, email),
    };

    return PopScope(
      canPop: _stepIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _previous();
      },
      child: BisoPage(
        title: l10n.jobApply,
        largeTitle: false,
        leading: BisoBackButton(onPressed: _back),
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(
            child: _StepHeader(
              title: widget.job.title,
              steps: [for (final step in _steps) _stepLabel(l10n, step)],
              current: _stepIndex,
            ),
          ),
          ...stepSlivers,
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
        bottomBar: BisoBottomBar(child: _actions(l10n)),
      ),
    );
  }

  static String _stepLabel(AppLocalizations l10n, _Step step) => switch (step) {
    _Step.contact => l10n.jobApplyStepContact,
    _Step.questions => l10n.jobApplyStepQuestions,
    _Step.documents => l10n.jobApplyStepDocuments,
    _Step.review => l10n.jobApplyStepReview,
  };

  Widget _actions(AppLocalizations l10n) {
    final (String label, VoidCallback? onPressed) = switch (_step) {
      _Step.contact => (l10n.continueMessage, _contactReady ? _next : null),
      _Step.questions => (l10n.continueMessage, _questionsReady ? _next : null),
      _Step.documents => (
        l10n.jobApplyReviewApplication,
        _documentsReady ? _next : null,
      ),
      _Step.review => (
        _submitting ? l10n.jobApplySubmitting : l10n.jobApplySubmit,
        _consent && !_submitting ? _submit : null,
      ),
    };
    return Row(
      children: [
        if (_stepIndex > 0) ...[
          Expanded(
            child: OutlinedButton(
              onPressed: _submitting ? null : _previous,
              child: Text(l10n.backMessage),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: FilledButton(onPressed: onPressed, child: Text(label)),
        ),
      ],
    );
  }

  List<Widget> _contactSlivers(AppLocalizations l10n, String email) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    return [
      SliverToBoxAdapter(
        child: BisoFormGroup(
          footer: l10n.jobApplyEmailVerified,
          children: [
            BisoFormRow(
              label: l10n.jobApplyFullName,
              child: _Field(
                key: const ValueKey('applicant-name'),
                controller: _name,
                maxLength: _maxNameLength,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
              ),
            ),
            BisoFormRow(
              label: l10n.emailMessage,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  email,
                  style: text.bodyLarge?.copyWith(color: palette.muted),
                ),
              ),
            ),
          ],
        ),
      ),
      SliverToBoxAdapter(
        child: BisoFormGroup(
          children: [
            BisoFormRow(
              label: l10n.jobApplyPhone,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Semantics(
                        label: l10n.jobApplyCountryCode,
                        child: DropdownButton<String>(
                          value: _countryCode,
                          underline: const SizedBox.shrink(),
                          icon: Icon(
                            CupertinoIcons.chevron_down,
                            size: 14,
                            color: palette.muted,
                          ),
                          items: [
                            for (final (code, label) in _countryCodes)
                              DropdownMenuItem(value: code, child: Text(label)),
                          ],
                          onChanged: (code) => setState(
                            () => _countryCode = code ?? _countryCode,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Field(
                          key: const ValueKey('applicant-phone'),
                          controller: _phone,
                          hintText: '123 45 678',
                          keyboardType: TextInputType.phone,
                          autofillHints: const [
                            AutofillHints.telephoneNumberNational,
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_phoneTooLong)
                    Text(
                      l10n.jobApplyPhoneTooLong,
                      style: text.bodySmall?.copyWith(color: palette.error),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      SliverToBoxAdapter(
        child: BisoFormGroup(
          children: [
            BisoFormRow(
              label: l10n.jobApplyLinkedIn,
              child: _Field(
                controller: _linkedIn,
                hintText: 'https://linkedin.com/in/…',
                keyboardType: TextInputType.url,
                maxLength: _maxLinkedInLength,
              ),
            ),
            BisoFormRow(
              label: l10n.jobApplyCurrentRole,
              child: _Field(
                controller: _currentRole,
                hintText: l10n.jobApplyCurrentRoleHint,
                maxLength: _maxRoleLength,
              ),
            ),
            BisoFormRow(
              label: l10n.jobApplyEmployer,
              child: _Field(
                controller: _employer,
                hintText: 'BI, BISO…',
                maxLength: _maxRoleLength,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _questionSlivers(AppLocalizations l10n) {
    final palette = BisoPalette.of(context);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Text(
            l10n.jobApplyQuestionsIntro,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.muted),
          ),
        ),
      ),
      for (final question in _questions)
        SliverToBoxAdapter(
          child: BisoFormGroup(
            footer: question.helpText,
            children: _questionRows(l10n, question),
          ),
        ),
    ];
  }

  List<Widget> _questionRows(AppLocalizations l10n, JobQuestion question) {
    final label = question.required ? '${question.label} *' : question.label;
    final typed = _typedAnswers[question.id];
    if (typed != null) {
      final long = question.type == JobQuestionType.longText;
      return [
        BisoFormRow(
          label: label,
          child: _Field(
            key: ValueKey('question-${question.id}'),
            controller: typed,
            maxLength: _maxAnswerLength,
            minLines: long ? 3 : 1,
            maxLines: long ? 6 : 1,
            keyboardType: switch (question.type) {
              JobQuestionType.number => const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              JobQuestionType.longText => TextInputType.multiline,
              _ => TextInputType.text,
            },
          ),
        ),
      ];
    }

    final palette = BisoPalette.of(context);
    Widget mark({required bool on, required bool multi}) =>
        Icon(switch ((on, multi)) {
          (true, true) => CupertinoIcons.checkmark_square_fill,
          (false, true) => CupertinoIcons.square,
          (true, false) => CupertinoIcons.checkmark_circle_fill,
          (false, false) => CupertinoIcons.circle,
        }, color: on ? palette.link : palette.muted);

    final picked = _pickedAnswers[question.id];
    return [
      _QuestionLabel(label),
      ...switch (question.type) {
        JobQuestionType.select => [
          for (final option in question.options)
            BisoListRow(
              title: option,
              showChevron: false,
              trailing: mark(on: picked == option, multi: false),
              onTap: () => _setPicked(question.id, option),
            ),
        ],
        JobQuestionType.multiSelect => [
          for (final option in question.options)
            BisoListRow(
              title: option,
              showChevron: false,
              trailing: mark(
                on: picked is List && picked.contains(option),
                multi: true,
              ),
              onTap: () {
                final current = picked is List<String> ? picked : <String>[];
                _setPicked(
                  question.id,
                  current.contains(option)
                      ? [...current.where((o) => o != option)]
                      : [...current, option],
                );
              },
            ),
        ],
        _ => [
          BisoListRow(
            title: l10n.jobApplyYes,
            trailing: Switch.adaptive(
              value: picked == true,
              onChanged: (yes) => _setPicked(question.id, yes),
            ),
            onTap: () => _setPicked(question.id, picked != true),
          ),
        ],
      },
    ];
  }

  List<Widget> _documentSlivers(AppLocalizations l10n) {
    final palette = BisoPalette.of(context);
    return [
      SliverToBoxAdapter(
        child: BisoFormGroup(
          children: [
            _DocumentRow(
              pickKey: const ValueKey('pick-cover_letter'),
              label: l10n.jobApplyCoverLetter,
              help: l10n.jobApplyCoverLetterHelp,
              document: _coverLetter,
              problem: _coverLetterProblem,
              onPick: () => _pick(_Document.coverLetter),
            ),
          ],
        ),
      ),
      SliverToBoxAdapter(
        child: BisoFormGroup(
          children: [
            _DocumentRow(
              pickKey: const ValueKey('pick-resume'),
              label: widget.job.cvRequired
                  ? l10n.jobApplyCvRequired
                  : l10n.jobApplyCvOptional,
              help: l10n.jobApplyFileHelp,
              document: _resume,
              problem: _resumeProblem,
              onPick: () => _pick(_Document.resume),
              onRemove: _removeResume,
            ),
          ],
        ),
      ),
      if (!_documentsFit)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              l10n.jobApplyTooLargeTogether,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.error),
            ),
          ),
        ),
      SliverToBoxAdapter(
        child: BisoFormGroup(
          footer: l10n.jobApplyAvailabilityHelp,
          children: [
            BisoFormRow(
              label: l10n.jobApplyAvailability,
              child: _Field(
                controller: _availability,
                hintText: l10n.jobApplyAvailabilityHint,
                keyboardType: TextInputType.multiline,
                minLines: 3,
                maxLines: 6,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _reviewSlivers(AppLocalizations l10n, String email) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    final phone = _phoneValue;
    final resume = _resume;
    final coverLetter = _coverLetter;
    BisoListRow summary(String label, String value) =>
        BisoListRow(title: label, value: value, showChevron: false);

    return [
      SliverToBoxAdapter(
        child: BisoSection(
          child: BisoListGroup(
            dividerIndent: 16,
            children: [
              summary(l10n.jobApplyName, _name.text.trim()),
              summary(l10n.emailMessage, email),
              if (phone.isNotEmpty) summary(l10n.phoneMessage, phone),
              if (resume != null) summary(l10n.jobApplyCv, resume.name),
              if (coverLetter != null)
                summary(l10n.jobApplyCoverLetterLabel, coverLetter.name),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: BisoSection(
          child: BisoListGroup(
            children: [
              MergeSemantics(
                child: InkWell(
                  onTap: () => setState(() => _consent = !_consent),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox.adaptive(
                          value: _consent,
                          onChanged: (value) =>
                              setState(() => _consent = value ?? false),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              l10n.jobApplyConsent,
                              style: text.bodyMedium?.copyWith(
                                color: palette.ink,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      if (_submitError != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _submitError!,
                style: text.bodyMedium?.copyWith(color: palette.error),
              ),
            ),
          ),
        ),
    ];
  }
}

/// The vacancy's title above a bar showing how far along the form is.
class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.title,
    required this.steps,
    required this.current,
  });

  final String title;
  final List<String> steps;
  final int current;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title.toCompactHtml(
            style: text.titleLarge?.copyWith(color: palette.ink),
            maxLines: 2,
            fontSize: 20,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= current ? palette.primary : palette.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${current + 1}/${steps.length} · ${steps[current]}',
            style: text.labelLarge?.copyWith(color: palette.muted),
          ),
        ],
      ),
    );
  }
}

/// A question's label above its choices.
class _QuestionLabel extends StatelessWidget {
  const _QuestionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
    child: Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.labelMedium?.copyWith(color: BisoPalette.of(context).muted),
    ),
  );
}

/// One PDF slot: what is picked, what is wrong with it, and the buttons to
/// pick, replace or remove it.
class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.pickKey,
    required this.label,
    required this.help,
    required this.document,
    required this.problem,
    required this.onPick,
    this.onRemove,
  });

  final Key pickKey;
  final String label;
  final String help;
  final ApplicationDocument? document;
  final ApplicationDocumentProblem? problem;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    final picked = document;
    final problemText = switch (problem) {
      ApplicationDocumentProblem.notPdf => l10n.jobApplyNotPdf,
      ApplicationDocumentProblem.tooLarge => l10n.jobApplyTooLarge,
      null => null,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.labelMedium?.copyWith(color: palette.muted)),
          if (picked != null) ...[
            const SizedBox(height: 4),
            Text(
              l10n.jobApplySelectedFile(
                picked.name,
                (picked.size / 1024).toStringAsFixed(0),
              ),
              style: text.bodyLarge?.copyWith(color: palette.ink),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            problemText ?? help,
            style: text.bodySmall?.copyWith(
              color: problemText == null ? palette.muted : palette.error,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: pickKey,
                onPressed: onPick,
                icon: const Icon(CupertinoIcons.doc, size: 18),
                label: Text(
                  picked == null
                      ? l10n.jobApplyChoosePdf
                      : l10n.jobApplyReplacePdf,
                ),
              ),
              if (onRemove != null && (picked != null || problem != null))
                TextButton(
                  onPressed: onRemove,
                  child: Text(l10n.jobApplyRemovePdf),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A borderless text field for a [BisoFormRow] that, when focused, scrolls
/// clear of the page's header and bottom bar.
class _Field extends StatelessWidget {
  const _Field({
    super.key,
    required this.controller,
    this.hintText,
    this.keyboardType,
    this.maxLength,
    this.minLines,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
  });

  final TextEditingController controller;
  final String? hintText;
  final TextInputType? keyboardType;
  final int? maxLength;
  final int? minLines;
  final int maxLines;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    final insets = BisoPageInsets.maybeOf(context);
    return TextField(
      controller: controller,
      decoration: bisoInputDecoration(context, hintText: hintText),
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines,
      textCapitalization: textCapitalization,
      autofillHints: autofillHints,
      inputFormatters: [
        if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
      ],
      scrollPadding: insets == null
          ? const EdgeInsets.all(20)
          : EdgeInsets.fromLTRB(20, insets.top + 20, 20, insets.bottom + 20),
    );
  }
}
