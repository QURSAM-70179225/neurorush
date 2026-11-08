import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A one-field input dialog that owns (and safely disposes) its controller.
/// Returns the entered text, or null when cancelled.
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initial = '',
  String? label,
  String? prefixText,
  String? helperText,
  int? maxLength,
  TextCapitalization capitalization = TextCapitalization.none,
  List<TextInputFormatter>? inputFormatters,
  String? Function(String)? validator,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TextPromptDialog(
        title: title,
        confirmLabel: confirmLabel,
        initial: initial,
        label: label,
        prefixText: prefixText,
        helperText: helperText,
        maxLength: maxLength,
        capitalization: capitalization,
        inputFormatters: inputFormatters,
        validator: validator,
      ),
    );

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.confirmLabel,
    required this.initial,
    this.label,
    this.prefixText,
    this.helperText,
    this.maxLength,
    required this.capitalization,
    this.inputFormatters,
    this.validator,
  });

  final String title;
  final String confirmLabel;
  final String initial;
  final String? label;
  final String? prefixText;
  final String? helperText;
  final int? maxLength;
  final TextCapitalization capitalization;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String)? validator;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Form(
          key: _formKey,
          child: TextFormField(
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            maxLength: widget.maxLength,
            textCapitalization: widget.capitalization,
            inputFormatters: widget.inputFormatters,
            decoration: InputDecoration(labelText: widget.label, prefixText: widget.prefixText, helperText: widget.helperText),
            validator: widget.validator == null ? null : (v) => widget.validator!(v?.trim() ?? ''),
            onFieldSubmitted: (_) => _submit(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
        ],
      );
}
