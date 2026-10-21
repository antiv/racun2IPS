import 'package:flutter/material.dart';

import '../theme.dart';

/// Red sa labelom, editabilnim tekstom i opcionim brojačem karaktera —
/// pandan EditableRow.tsx iz originalnog dizajna.
class EditableRow extends StatefulWidget {
  const EditableRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.isMono = false,
    this.error = false,
    this.maxLength,
    this.keyboardType,
    this.hintText,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool isMono;
  final bool error;
  final int? maxLength;
  final TextInputType? keyboardType;
  final String? hintText;

  @override
  State<EditableRow> createState() => _EditableRowState();
}

class _EditableRowState extends State<EditableRow> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(EditableRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Spoljna promena vrednosti (npr. normalizacija računa) — sinhronizuj.
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxLength = widget.maxLength;
    final isOverLimit = maxLength != null && widget.value.length > maxLength;
    final showCounter = maxLength != null && widget.value.isNotEmpty;
    final hasError = widget.error || isOverLimit;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.05,
                  color: hasError ? AppColors.red400 : AppColors.stone400,
                ),
              ),
              if (showCounter)
                Text(
                  '${widget.value.length}/$maxLength',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isOverLimit ? FontWeight.w700 : FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: isOverLimit
                        ? AppColors.red400
                        : widget.value.length > maxLength * 0.8
                            ? AppColors.amber400
                            : AppColors.stone300,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          TextField(
            controller: _controller,
            onChanged: widget.onChanged,
            keyboardType: widget.keyboardType,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: widget.hintText,
              hintStyle: const TextStyle(color: AppColors.stone300),
            ),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              fontFamily: widget.isMono ? 'monospace' : null,
              color: hasError ? AppColors.red600 : AppColors.stone800,
            ),
          ),
        ],
      ),
    );
  }
}
