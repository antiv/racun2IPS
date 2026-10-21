import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/translations.dart';
import '../models/invoice_data.dart';
import '../models/saved_code.dart';
import '../screens/result_view.dart';
import '../theme.dart';
import '../utils/ips.dart';
import '../utils/share.dart' as share_utils;

/// Zaseban ekran za uređivanje svih detalja sačuvanog šablona računa ili
/// sopstvenog IPS koda.
class EditSavedCodeScreen extends StatefulWidget {
  const EditSavedCodeScreen({
    super.key,
    required this.t,
    required this.code,
    this.isEditingExisting = true,
    required this.onSave,
    this.onDelete,
  });

  final Translations t;
  final SavedCode code;
  final bool isEditingExisting;
  final Future<void> Function(SavedCode updated) onSave;
  final Future<void> Function(String id)? onDelete;

  @override
  State<EditSavedCodeScreen> createState() => _EditSavedCodeScreenState();
}

class _EditSavedCodeScreenState extends State<EditSavedCodeScreen> {
  late final InvoiceData _data = widget.code.data.copyWith();
  late String _title = widget.code.title;
  bool _copied = false;
  bool _saving = false;

  void _handleCopy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _handleShare() {
    final ipsString = generateIpsString(
      _data,
      allowOpenAmount: widget.code.kind == SavedCodeKind.ownAccount,
    );
    share_utils.shareQrCode(ipsString, widget.t.title, widget.t.shareDesc);
  }

  Future<void> _handleSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    final updated = widget.code.copyWith(
      title: _title,
      data: _data.copyWith(),
      updatedAt: DateTime.now(),
    );
    await widget.onSave(updated);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _handleDelete() async {
    if (_saving || widget.onDelete == null) return;
    setState(() => _saving = true);
    await widget.onDelete!(widget.code.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isEditingExisting
        ? widget.t.editDetails
        : widget.t.addNew;

    return Scaffold(
      backgroundColor: AppColors.stone50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: AppColors.stone200,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.stone800),
          tooltip: widget.t.cancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: AppColors.stone900,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: AppColors.stone100),
        ),
      ),
      body: ResultView(
        t: widget.t,
        data: _data,
        copied: _copied,
        mode: ResultMode.ownCode,
        isEditingExisting: widget.isEditingExisting,
        codeTitle: _title,
        onTitleChanged: (val) => setState(() => _title = val),
        onSave: _handleSave,
        onDelete: widget.isEditingExisting ? _handleDelete : null,
        onChanged: () => setState(() {}),
        onCopy: _handleCopy,
        onShare: _handleShare,
        onReset: () => Navigator.of(context).pop(),
        onViewImage: () {},
      ),
    );
  }
}
