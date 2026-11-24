import 'package:flutter/material.dart';

import '../services/date_format.dart';
import '../theme/app_theme.dart';

const _danger = Color(0xFFC0392B);

/// A short message at the bottom of the screen.
void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Asks before deleting; true when the admin chose Delete.
Future<bool> confirmDelete(
  BuildContext context,
  String title,
  String question,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(question),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('confirmDelete'),
          style: TextButton.styleFrom(foregroundColor: _danger),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// An icon and a message in the middle; scrollable so pull to refresh works.
class InfoView extends StatelessWidget {
  const InfoView({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Icon(icon, size: 56, color: AppColors.terracotta),
        const SizedBox(height: 16),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

/// A small rounded label such as "10 rooms".
class CountChip extends StatelessWidget {
  const CountChip(this.number, this.label, {super.key});

  final int number;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.contentBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$number $label',
        style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
      ),
    );
  }
}

/// A labelled text box for the add and edit forms.
class FormTextField extends StatelessWidget {
  const FormTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.maxLength,
    this.required = false,
    this.enabled = true,
    this.keyboard,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final int maxLength;
  final bool required;
  final bool enabled;
  final TextInputType? keyboard;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        enabled: enabled,
        maxLength: maxLength,
        maxLines: maxLines,
        minLines: 1,
        keyboardType: keyboard,
        textCapitalization:
            keyboard == null || keyboard == TextInputType.streetAddress
            ? TextCapitalization.words
            : TextCapitalization.none,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
          counterText: '',
        ),
      ),
    );
  }
}

/// The red message under a form.
class FormMessage extends StatelessWidget {
  const FormMessage(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(message, style: const TextStyle(color: _danger)),
    );
  }
}

/// The terracotta Save button, with a spinner while saving.
class SaveButton extends StatelessWidget {
  const SaveButton({super.key, required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.terracotta,
          disabledBackgroundColor: AppColors.terracottaDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Text(
                'Save',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }
}

/// The ⋮ menu on a list card with Edit and Delete.
class EditDeleteMenu extends StatelessWidget {
  const EditDeleteMenu({
    super.key,
    required this.onEdit,
    required this.onDelete,
  });

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }
}

/// A date box that opens the calendar. With [optional] it can be left empty
/// and has a clear button.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.firstDate,
    required this.lastDate,
    this.optional = false,
    this.required = false,
    this.enabled = true,
    this.initialPickerDate,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final DateTime firstDate;
  final DateTime lastDate;
  final bool optional;
  final bool required;
  final bool enabled;

  /// Where the calendar opens when the box is empty.
  final DateTime? initialPickerDate;

  Future<void> _pick(BuildContext context) async {
    var initial = value ?? initialPickerDate ?? DateTime.now();
    if (initial.isBefore(firstDate)) initial = firstDate;
    if (initial.isAfter(lastDate)) initial = lastDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: label.toUpperCase(),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: enabled ? () => _pick(context) : null,
        child: InputDecorator(
          isEmpty: value == null,
          decoration: InputDecoration(
            labelText: required ? '$label *' : label,
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
            enabled: enabled,
            suffixIcon: optional && value != null && enabled
                ? IconButton(
                    tooltip: 'Clear $label',
                    icon: const Icon(Icons.clear),
                    onPressed: () => onChanged(null),
                  )
                : const Icon(Icons.calendar_today_outlined),
          ),
          child: Text(value == null ? '' : _format(value!)),
        ),
      ),
    );
  }

  static String _format(DateTime d) => formatDate(d);
}

/// A drop-down box for the add and edit forms.
class FormDropdown<T> extends StatelessWidget {
  const FormDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.required = false,
    this.enabled = true,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final bool required;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
        items: items,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

/// A heading between groups of fields in a long form.
class FormSection extends StatelessWidget {
  const FormSection(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 10),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppColors.groupText,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
