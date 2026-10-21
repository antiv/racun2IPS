import 'package:flutter/material.dart';

import '../i18n/translations.dart';
import '../models/invoice_data.dart';
import '../models/saved_code.dart';
import '../theme.dart';
import '../widgets/quick_qr_sheet.dart';
import 'edit_saved_code_screen.dart';

enum _SavedFilter { all, bills, own }

/// Zasebna strana za pregled, filtriranje, pretragu i upravljanje sačuvanim
/// računima (šablonima) i sopstvenim IPS kodovima.
class SavedCodesScreen extends StatefulWidget {
  const SavedCodesScreen({
    super.key,
    required this.t,
    required this.codes,
    required this.onUpdate,
    required this.onAddCode,
    required this.onDelete,
    required this.onTogglePin,
    required this.onTogglePaid,
    required this.onAmountUpdated,
    required this.onCopy,
    required this.onShare,
    required this.onStartCamera,
    required this.onStartGallery,
    required this.onExport,
    required this.onImport,
  });

  final Translations t;
  final List<SavedCode> codes;
  final Future<void> Function(SavedCode updated) onUpdate;
  final Future<void> Function(SavedCode newCode) onAddCode;
  final ValueChanged<String> onDelete;
  final ValueChanged<String> onTogglePin;
  final ValueChanged<String> onTogglePaid;
  final void Function(String id, double amount) onAmountUpdated;
  final ValueChanged<String> onCopy;
  final void Function(SavedCode code) onShare;
  final VoidCallback onStartCamera;
  final VoidCallback onStartGallery;
  final VoidCallback onExport;
  final VoidCallback onImport;

  @override
  State<SavedCodesScreen> createState() => _SavedCodesScreenState();
}

class _SavedCodesScreenState extends State<SavedCodesScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  _SavedFilter _filter = _SavedFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SavedCode> get _filteredAndSorted {
    final q = _query.trim().toLowerCase();
    final list = widget.codes.where((c) {
      // 1. Filter po kategoriji
      switch (_filter) {
        case _SavedFilter.all:
          break;
        case _SavedFilter.bills:
          if (c.kind != SavedCodeKind.billTemplate) return false;
        case _SavedFilter.own:
          if (c.kind != SavedCodeKind.ownAccount) return false;
      }

      // 2. Filter po pretrazi
      if (q.isEmpty) return true;
      final data = c.data;
      return c.title.toLowerCase().contains(q) ||
          data.recipientName.toLowerCase().contains(q) ||
          data.accountNumber.toLowerCase().contains(q) ||
          data.referenceNumber.toLowerCase().contains(q) ||
          data.purpose.toLowerCase().contains(q);
    }).toList();

    // Sortiranje: Pinovani prvi, pa po datumu ažuriranja
    list.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });

    return list;
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

  void _showQuickSheet(SavedCode code) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => QuickQrSheet(
        t: widget.t,
        code: code,
        onCopy: widget.onCopy,
        onShare: () => widget.onShare(code),
        onTogglePin: () {
          widget.onTogglePin(code.id);
          setState(() {});
        },
        onTogglePaid: () {
          widget.onTogglePaid(code.id);
          setState(() {});
        },
        onAmountUpdated: (newAmt) {
          widget.onAmountUpdated(code.id, newAmt);
          setState(() {});
        },
        onEditDetails: () {
          // QuickQrSheet se sam zatvara pre onEditDetails poziva.
          // Otvaramo zaseban ekran za izmenu svih detalja bez ikakvog dodatnog pop-a!
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EditSavedCodeScreen(
                t: widget.t,
                code: code,
                isEditingExisting: true,
                onSave: (updated) async {
                  await widget.onUpdate(updated);
                  if (mounted) setState(() {});
                },
                onDelete: (id) async {
                  widget.onDelete(id);
                  if (mounted) setState(() {});
                },
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAddCodeDialog() {
    final t = widget.t;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 5,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: AppColors.stone200,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: AppColors.emerald600),
              title: Text(t.addViaCamera),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                Navigator.of(context).pop();
                widget.onStartCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.emerald600),
              title: Text(t.addViaGallery),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                Navigator.of(context).pop();
                widget.onStartGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: AppColors.emerald600),
              title: Text(t.addViaManual),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EditSavedCodeScreen(
                      t: widget.t,
                      code: SavedCode(
                        id: DateTime.now().microsecondsSinceEpoch.toString(),
                        createdAt: DateTime.now(),
                        title: '',
                        kind: SavedCodeKind.ownAccount,
                        data: InvoiceData(),
                      ),
                      isEditingExisting: false,
                      onSave: (newCode) async {
                        await widget.onAddCode(newCode);
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final filtered = _filteredAndSorted;

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
          tooltip: t.cancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            t.savedCodesTitle,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: AppColors.stone900,
            ),
          ),
        ),
        actions: [
          IconButton(
            onPressed: widget.onExport,
            tooltip: t.exportCodes,
            icon: const Icon(Icons.ios_share, size: 21, color: AppColors.stone700),
          ),
          IconButton(
            onPressed: widget.onImport,
            tooltip: t.importCodes,
            icon: const Icon(Icons.file_download_outlined,
                size: 22, color: AppColors.stone700),
          ),
          const SizedBox(width: 4),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: AppColors.stone100),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            // Gornji kontrolni deo: pretraga i filteri
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                children: [
                  // Pretraga
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.stone50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.stone200),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _query = val),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        prefixIcon: const Icon(Icons.search,
                            size: 19, color: AppColors.stone400),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear,
                                    size: 18, color: AppColors.stone400),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                              )
                            : null,
                        hintText: t.searchHint,
                        hintStyle: const TextStyle(
                          fontSize: 13,
                          color: AppColors.stone400,
                        ),
                      ),
                      style: const TextStyle(fontSize: 14, color: AppColors.stone800),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Filter tabovi (horizontalno skrolabilni za sprečavanje overflow-a)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _FilterPill(
                          label: t.filterAll,
                          isSelected: _filter == _SavedFilter.all,
                          onTap: () => setState(() => _filter = _SavedFilter.all),
                        ),
                        const SizedBox(width: 8),
                        _FilterPill(
                          label: t.filterBills,
                          isSelected: _filter == _SavedFilter.bills,
                          onTap: () => setState(() => _filter = _SavedFilter.bills),
                        ),
                        const SizedBox(width: 8),
                        _FilterPill(
                          label: t.filterOwn,
                          isSelected: _filter == _SavedFilter.own,
                          onTap: () => setState(() => _filter = _SavedFilter.own),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: AppColors.stone100),

            // Lista sačuvanih kodova
            Expanded(
              child: widget.codes.isEmpty
                  ? _EmptyState(
                      title: t.noSavedCodesTitle,
                      desc: t.noSavedCodesDesc,
                    )
                  : filtered.isEmpty
                      ? _EmptyState(title: t.noSearchResults, desc: null)
                      : ListView.separated(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final code = filtered[i];
                            return _SavedCodeRow(
                              t: t,
                              code: code,
                              onTap: () => _showQuickSheet(code),
                              onTogglePin: () {
                                widget.onTogglePin(code.id);
                                setState(() {});
                              },
                              onDismissed: () => widget.onDelete(code.id),
                              confirmDismiss: () => _confirmDelete(context),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.stone100)),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _showAddCodeDialog,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.emerald600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.add, size: 20),
              label: Text(t.addNew),
            ),
          ),
        ),
      ),
    );
  }
}

/// Alias za unazadnu kompatibilnost.
typedef SavedCodesView = SavedCodesScreen;

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.stone900 : AppColors.stone100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.stone600,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.desc});

  final String title;
  final String? desc;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_2, size: 44, color: AppColors.stone300),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                color: AppColors.stone600,
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
      ),
    );
  }
}

class _SavedCodeRow extends StatelessWidget {
  const _SavedCodeRow({
    required this.t,
    required this.code,
    required this.onTap,
    required this.onTogglePin,
    required this.onDismissed,
    required this.confirmDismiss,
  });

  final Translations t;
  final SavedCode code;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
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
    final hasTitle = code.title.isNotEmpty;
    final displayTitle = hasTitle ? code.title : code.data.recipientName;
    final displaySubtitle = hasTitle
        ? (code.data.recipientName.isNotEmpty
            ? '${code.data.recipientName} • $_maskedAccount'
            : _maskedAccount)
        : (code.data.purpose.isNotEmpty ? code.data.purpose : _maskedAccount);

    final isPaid = code.isPaidThisMonth;

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
            border: Border.all(
              color: code.isPinned ? AppColors.emerald200 : AppColors.stone100,
              width: code.isPinned ? 1.5 : 1.0,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x06000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              if (code.isPinned) ...[
                const Icon(Icons.push_pin, size: 16, color: AppColors.emerald600),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayTitle.isEmpty ? _maskedAccount : displayTitle,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.stone800,
                            ),
                          ),
                        ),
                        if (isPaid) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.emerald50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check,
                                    size: 11, color: AppColors.emerald700),
                                const SizedBox(width: 2),
                                Text(
                                  t.paidBadge,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.emerald700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      displaySubtitle,
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
