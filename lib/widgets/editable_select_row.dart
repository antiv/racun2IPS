import 'package:flutter/material.dart';

import '../constants/payment_codes.dart';
import '../theme.dart';

/// Red za izbor šifre plaćanja — pandan EditableSelectRow.tsx.
/// Tap otvara bottom sheet sa listom šifara.
class EditableSelectRow extends StatelessWidget {
  const EditableSelectRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.error = false,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final selected = paymentCodes.where((c) => c.code == value).firstOrNull;
    final displayLabel =
        selected != null ? '${selected.code} - ${selected.description}' : value;

    return InkWell(
      onTap: () => _showPicker(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.05,
                color: error ? AppColors.red400 : AppColors.stone400,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                displayLabel,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 13.5,
                  color: error ? AppColors.red600 : AppColors.stone600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down,
                size: 18, color: AppColors.stone300),
          ],
        ),
      ),
    );
  }

  Future<void> _showPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      builder: (context) => Column(
        children: [
          Container(
            width: 38,
            height: 5,
            margin: const EdgeInsets.only(top: 10, bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.stone200,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
              itemCount: paymentCodes.length,
              separatorBuilder: (_, _) => const Divider(
                height: 1,
                indent: 16,
                color: AppColors.stone100,
              ),
              itemBuilder: (context, i) {
                final item = paymentCodes[i];
                final isSelected = item.code == value;
                return ListTile(
                  dense: true,
                  selected: isSelected,
                  selectedTileColor: AppColors.emerald50,
                  title: Text(
                    '${item.code} - ${item.description}',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w400,
                      color: isSelected
                          ? AppColors.emerald700
                          : AppColors.stone600,
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop(item.code),
                );
              },
            ),
          ),
        ],
      ),
    );
    if (picked != null) onChanged(picked);
  }
}
