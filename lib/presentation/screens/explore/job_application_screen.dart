import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/logging/app_logger.dart';
import '../../../data/models/job_model.dart';
import '../../../data/services/application_service.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/job/application_provider.dart';

class JobApplicationScreen extends ConsumerStatefulWidget {
  final JobModel job;

  const JobApplicationScreen({super.key, required this.job});

  @override
  ConsumerState<JobApplicationScreen> createState() =>
      _JobApplicationScreenState();
}

class _JobApplicationScreenState extends ConsumerState<JobApplicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _coverLetterController = TextEditingController();
  final _availabilityController = TextEditingController();
  final Map<String, TextEditingController> _textAnswers = {};
  final Map<String, String?> _selectAnswers = {};
  final Map<String, Set<String>> _multiSelectAnswers = {};
  final Map<String, bool> _booleanAnswers = {};

  File? _resume;
  bool _gdprConsent = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authStateProvider).user;
    _nameController.text = user?.name ?? '';
    _phoneController.text = user?.phone ?? '';
    for (final question in widget.job.customQuestions) {
      switch (question.type) {
        case 'select':
          _selectAnswers[question.id] = null;
        case 'multi_select':
          _multiSelectAnswers[question.id] = <String>{};
        case 'boolean':
          _booleanAnswers[question.id] = false;
        default:
          _textAnswers[question.id] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _coverLetterController.dispose();
    _availabilityController.dispose();
    for (final controller in _textAnswers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<ApplicationAnswerInput> _collectAnswers() {
    final answers = <ApplicationAnswerInput>[];
    for (final question in widget.job.customQuestions) {
      String answer;
      switch (question.type) {
        case 'select':
          answer = _selectAnswers[question.id] ?? '';
        case 'multi_select':
          answer = (_multiSelectAnswers[question.id] ?? {}).join(', ');
        case 'boolean':
          answer = (_booleanAnswers[question.id] ?? false) ? 'Yes' : 'No';
        default:
          answer = _textAnswers[question.id]?.text.trim() ?? '';
      }
      answers.add(ApplicationAnswerInput(question: question, answer: answer));
    }
    return answers;
  }

  String? _validateRequiredQuestions() {
    for (final question in widget.job.customQuestions) {
      if (!question.required) continue;
      final answered = switch (question.type) {
        'select' => (_selectAnswers[question.id] ?? '').isNotEmpty,
        'multi_select' => (_multiSelectAnswers[question.id] ?? {}).isNotEmpty,
        'boolean' => true,
        _ => (_textAnswers[question.id]?.text.trim() ?? '').isNotEmpty,
      };
      if (!answered) {
        return 'Please answer "${question.label}"';
      }
    }
    return null;
  }

  Future<void> _pickResume() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = result?.files.single.path;
    if (path != null) {
      setState(() => _resume = File(path));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final questionError = _validateRequiredQuestions();
    if (questionError != null) {
      _showError(questionError);
      return;
    }
    if (widget.job.cvRequired && _resume == null) {
      _showError('A CV (PDF) is required for this position');
      return;
    }
    if (!_gdprConsent) {
      _showError('You must consent to data processing to apply');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final availability = _availabilityController.text
          .split(RegExp(r'\r?\n|,'))
          .map((slot) => slot.trim())
          .where((slot) => slot.isNotEmpty)
          .toList();

      final applicationId = await ref
          .read(applicationServiceProvider)
          .submitApplication(
            jobId: widget.job.id,
            applicantName: _nameController.text.trim(),
            applicantPhone: _phoneController.text.trim(),
            coverLetter: _coverLetterController.text.trim(),
            availability: availability,
            answers: _collectAnswers(),
            resume: _resume,
            gdprConsent: _gdprConsent,
          );

      AppLogger.info(
        '[APPLICATION] Submitted',
        extra: {'job_id': widget.job.id, 'application_id': applicationId},
      );
      ref.invalidate(myApplicationsProvider);

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(
            Icons.check_circle,
            color: AppColors.success,
            size: 48,
          ),
          title: const Text('Application sent'),
          content: const Text(
            'Your application has been submitted. You can follow its status '
            'under My Applications.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/explore/volunteer');
        }
      }
    } on ApplicationException catch (e) {
      _showError(
        e.isDuplicate ? 'You have already applied for this position' : e.message,
      );
    } catch (e) {
      AppLogger.error('[APPLICATION] Submit failed', error: e);
      _showError('Could not submit your application. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authStateProvider);

    if (!authState.isAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('Apply')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 48,
                  color: AppColors.defaultBlue,
                ),
                const SizedBox(height: 16),
                Text(
                  'Sign in to apply',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'You need a verified BISO account to apply for positions.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.push('/auth/login'),
                  child: const Text('Sign in'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Apply')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.job.title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.job.department,
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppColors.defaultBlue,
              ),
            ),
            const SizedBox(height: 24),

            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Full name *',
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Name is required'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _coverLetterController,
              maxLines: 6,
              maxLength: 4000,
              decoration: const InputDecoration(
                labelText: 'Motivation / cover letter',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _availabilityController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Availability for interviews',
                hintText: 'One suggestion per line, e.g. "Mondays after 16:00"',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),

            if (widget.job.customQuestions.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'Questions from ${widget.job.department}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              ...widget.job.customQuestions.map(_buildQuestion),
            ],

            const SizedBox(height: 24),
            Text(
              widget.job.cvRequired ? 'CV (PDF) *' : 'CV (PDF, optional)',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickResume,
              icon: const Icon(Icons.attach_file),
              label: Text(
                _resume == null
                    ? 'Attach CV'
                    : _resume!.uri.pathSegments.last,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            const SizedBox(height: 24),
            CheckboxListTile(
              value: _gdprConsent,
              onChanged: (value) =>
                  setState(() => _gdprConsent = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'I consent to BISO processing my personal data for this '
                'recruitment process (GDPR). Data is deleted after the '
                'retention period.',
                style: TextStyle(fontSize: 13),
              ),
            ),

            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit application'),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion(JobQuestionModel question) {
    final theme = Theme.of(context);
    final label = question.required ? '${question.label} *' : question.label;

    Widget field;
    switch (question.type) {
      case 'select':
        field = DropdownButtonFormField<String>(
          value: _selectAnswers[question.id],
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          items: question.options
              .map(
                (option) =>
                    DropdownMenuItem(value: option, child: Text(option)),
              )
              .toList(),
          onChanged: (value) =>
              setState(() => _selectAnswers[question.id] = value),
        );
      case 'multi_select':
        final selected = _multiSelectAnswers[question.id] ?? <String>{};
        field = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: question.options
                  .map(
                    (option) => FilterChip(
                      label: Text(option),
                      selected: selected.contains(option),
                      onSelected: (isSelected) => setState(() {
                        if (isSelected) {
                          selected.add(option);
                        } else {
                          selected.remove(option);
                        }
                        _multiSelectAnswers[question.id] = selected;
                      }),
                    ),
                  )
                  .toList(),
            ),
          ],
        );
      case 'boolean':
        field = SwitchListTile(
          value: _booleanAnswers[question.id] ?? false,
          onChanged: (value) =>
              setState(() => _booleanAnswers[question.id] = value),
          title: Text(label, style: theme.textTheme.bodyMedium),
          contentPadding: EdgeInsets.zero,
        );
      case 'number':
        field = TextFormField(
          controller: _textAnswers[question.id],
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: label,
            helperText: question.helpText,
            border: const OutlineInputBorder(),
          ),
        );
      case 'long_text':
        field = TextFormField(
          controller: _textAnswers[question.id],
          maxLines: 4,
          maxLength: 4000,
          decoration: InputDecoration(
            labelText: label,
            helperText: question.helpText,
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
          ),
        );
      default:
        field = TextFormField(
          controller: _textAnswers[question.id],
          decoration: InputDecoration(
            labelText: label,
            helperText: question.helpText,
            border: const OutlineInputBorder(),
          ),
        );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: field,
    );
  }
}
