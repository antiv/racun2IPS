import 'package:flutter/material.dart';

import '../i18n/translations.dart';
import '../models/saved_code.dart';
import '../theme.dart';

/// Lista sačuvanih ličnih IPS kodova, sa pretragom i brisanjem.
class SavedCodesView extends StatefulWidget {
  const SavedCodesView({
    super.key,
    required this.t,
    required this.codes,
    required this.onOpen,
    required this.onDelete,
    required this.onAddPressed,
    required this.onExport,
    required this.onImport,
  });

  final Translations t;
  final List<SavedCode> codes;
  final ValueChanged<SavedCode> onOpen;
  final ValueChanged<String> onDelete;
  final VoidCallback onAddPressed;
  final VoidCallback onExport;
  final VoidCallback onImport;

  @override
  State<SavedCodesView> createState() => _SavedCodesViewState();
}

class _SavedCodesViewState extends State<SavedCodesView> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SavedCode> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.codes;
    return widget.codes.where((c) {
      final data = c.data;
      return data.recipientName.toLowerCase().contains(q) ||
          data.accountNumber.toLowerCase().contains(q) ||
          data.purpose.toLowerCase().contains(q);
    }).toList();
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final t = widget.t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.confirmDeleteTitle),
        content: Text(t.confirmDeleteMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red600),
            child: Text(t.delete),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final filtered = _filtered;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t.savedCodesTitle,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: AppColors.stone800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onExport,
                    tooltip: t.exportCodes,
                    icon: const Icon(Icons.ios_share,
                        size: 20, color: AppColors.stone400),
                  ),
                  IconButton(
                    onPressed: widget.onImport,
                    tooltip: t.importCodes,
                    icon: const Icon(Icons.file_download_outlined,
                        size: 20, color: AppColors.stone400),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.stone100),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _query = val),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    prefixIcon: const Icon(Icons.search,
                        size: 20, color: AppColors.stone400),
                    hintText: t.searchHint,
                    hintStyle: const TextStyle(
                      fontSize: 13.5,
                      color: AppColors.stone400,
                    ),
                  ),
                  style: const TextStyle(fontSize: 14, color: AppColors.stone800),
                ),
              ),
              const SizedBox(height: 18),
              if (widget.codes.isEmpty)
                _EmptyState(
                  title: t.noSavedCodesTitle,
                  desc: t.noSavedCodesDesc,
                )
              else if (filtered.isEmpty)
                _EmptyState(title: t.noSearchResults, desc: null)
              else
                for (var i = 0; i < filtered.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _SavedCodeRow(
                    t: t,
                    code: filtered[i],
                    onTap: () => widget.onOpen(filtered[i]),
                    onDismissed: () => widget.onDelete(filtered[i].id),
                    confirmDismiss: () => _confirmDelete(context),
                  ),
                ],
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(18, 12, 18, 16 + bottomInset),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [AppColors.stone50, Color(0x00FAFAF9)],
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              onPressed: widget.onAddPressed,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.emerald600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              icon: const Icon(Icons.add, size: 20),
              label: Text(t.addNew),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.desc});

  final String title;
  final String? desc;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Icon(Icons.qr_code_2, size: 40, color: AppColors.stone300),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.stone500,
            ),
          ),
          if (desc != null) ...[
            const SizedBox(height: 6),
            Text(
              desc!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.stone400),
            ),
          ],
        ],
      ),
    );
  }
}

class _SavedCodeRow extends StatelessWidget {
  const _SavedCodeRow({
    required this.t,
    required this.code,
    required this.onTap,
    required this.onDismissed,
    required this.confirmDismiss,
  });

  final Translations t;
  final SavedCode code;
  final VoidCallback onTap;
  final VoidCallback onDismissed;
  final Future<bool> Function() confirmDismiss;

  String get _maskedAccount {
    final acc = code.data.accountNumber;
    if (acc.length < 4) return acc;
    return '•••• ${acc.substring(acc.length - 4)}';
  }

  String get _amountLabel {
    final amount = code.data.amount;
    if (amount <= 0) return t.openAmountLabel;
    final formatted = amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
    return '$formatted RSD';
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(code.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => confirmDismiss(),
      onDismissed: (_) => onDismissed(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.red50,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.delete_outline, color: AppColors.red600),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.stone100),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      code.data.recipientName.isEmpty
                          ? _maskedAccount
                          : code.data.recipientName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.stone800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      code.data.purpose.isEmpty ? _maskedAccount : code.data.purpose,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.stone400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: code.data.amount <= 0
                      ? AppColors.amber50
                      : AppColors.emerald50,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _amountLabel,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: code.data.amount <= 0
                        ? AppColors.amber700
                        : AppColors.emerald700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
