import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../i18n/translations.dart';
import '../models/invoice_data.dart';
import '../models/saved_code.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/quick_qr_sheet.dart';
import '../widgets/saved_code_tile.dart';
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

  // widget.codes je snimak liste iz roditelja u trenutku otvaranja ekrana, pa
  // se promena primenjuje i na lokalni objekat da bi se odmah videla.
  void _togglePin(SavedCode code) {
    code.isPinned = !code.isPinned;
    widget.onTogglePin(code.id);
    setState(() {});
  }

  void _togglePaid(SavedCode code) {
    code.lastPaidAt = code.isPaidThisMonth ? null : DateTime.now();
    widget.onTogglePaid(code.id);
    setState(() {});
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
        onTogglePin: () => _togglePin(code),
        onTogglePaid: () => _togglePaid(code),
        onAmountUpdated: (newAmt) {
          code.data.amount = newAmt;
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
              leading: const Icon(
                LucideIcons.camera,
                size: 22,
                color: AppColors.emerald600,
              ),
              title: Text(t.addViaCamera),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                Navigator.of(context).pop();
                widget.onStartCamera();
              },
            ),
            ListTile(
              leading: const Icon(
                LucideIcons.image,
                size: 22,
                color: AppColors.emerald600,
              ),
              title: Text(t.addViaGallery),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                Navigator.of(context).pop();
                widget.onStartGallery();
              },
            ),
            ListTile(
              leading: const Icon(
                LucideIcons.penLine,
                size: 22,
                color: AppColors.emerald600,
              ),
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
    final pinned = filtered.where((c) => c.isPinned).toList();
    final others = filtered.where((c) => !c.isPinned).toList();
    // Naslovi grupa samo kad postoje obe grupe — inače su suvišni.
    final showGroups = pinned.isNotEmpty && others.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.stone50,
      appBar: AppBar(
        backgroundColor: AppColors.stone50,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            LucideIcons.arrowLeft,
            size: 22,
            color: AppColors.stone800,
          ),
          tooltip: t.back,
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            onPressed: widget.onExport,
            tooltip: t.exportCodes,
            icon: const Icon(
              LucideIcons.upload,
              size: 20,
              color: AppColors.stone600,
            ),
          ),
          IconButton(
            onPressed: widget.onImport,
            tooltip: t.importCodes,
            icon: const Icon(
              LucideIcons.download,
              size: 20,
              color: AppColors.stone600,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Gornji kontrolni deo: naslov, pretraga i filteri
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t.savedCodesTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.7,
                      color: AppColors.stone900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Pretraga
                  Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.stone200),
                    ),
                    alignment: Alignment.center,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _query = val),
                      textAlignVertical: TextAlignVertical.center,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        prefixIcon: const Icon(
                          LucideIcons.search,
                          size: 18,
                          color: AppColors.stone500,
                        ),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  LucideIcons.x,
                                  size: 18,
                                  color: AppColors.stone400,
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                              )
                            : null,
                        hintText: t.searchHint,
                        hintStyle: const TextStyle(
                          fontSize: 14,
                          color: AppColors.stone400,
                        ),
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.stone800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Filter kao segmentirana kontrola
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.stone100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        for (final (filter, label) in [
                          (_SavedFilter.all, t.filterAll),
                          (_SavedFilter.bills, t.filterBills),
                          (_SavedFilter.own, t.filterOwn),
                        ])
                          Expanded(
                            child: _FilterSegment(
                              label: label,
                              isSelected: _filter == filter,
                              onTap: () => setState(() => _filter = filter),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Lista sačuvanih kodova
            Expanded(
              child: widget.codes.isEmpty
                  ? _EmptyState(
                      title: t.noSavedCodesTitle,
                      desc: t.noSavedCodesDesc,
                    )
                  : filtered.isEmpty
                  ? _EmptyState(title: t.noSearchResults, desc: null)
                  : ListView(
                      physics: const BouncingScrollPhysics(),
                      // Donji prostor da FAB ne prekrije poslednji red.
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      children: [
                        if (showGroups) _GroupLabel(t.pinnedSection),
                        for (final code in pinned)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _PinnedCard(
                              t: t,
                              code: code,
                              onShowQr: () => _showQuickSheet(code),
                              onTogglePaid: () => _togglePaid(code),
                              onDismissed: () => widget.onDelete(code.id),
                              confirmDismiss: () => _confirmDelete(context),
                            ),
                          ),
                        if (showGroups) _GroupLabel(t.otherSection),
                        if (others.isNotEmpty)
                          _GroupedCard(
                            t: t,
                            codes: others,
                            onTap: _showQuickSheet,
                            onDismissed: (code) => widget.onDelete(code.id),
                            confirmDismiss: () => _confirmDelete(context),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: SizedBox(
        height: 56,
        child: FloatingActionButton.extended(
          onPressed: _showAddCodeDialog,
          backgroundColor: AppColors.emerald600,
          foregroundColor: Colors.white,
          elevation: 3,
          highlightElevation: 5,
          extendedPadding: const EdgeInsets.only(left: 18, right: 22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          icon: const Icon(LucideIcons.plus, size: 20),
          label: Text(
            t.add,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

/// Alias za unazadnu kompatibilnost.
typedef SavedCodesView = SavedCodesScreen;

class _FilterSegment extends StatelessWidget {
  const _FilterSegment({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: isSelected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 36,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isSelected
                ? const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isSelected ? AppColors.stone900 : AppColors.stone500,
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppColors.stone500,
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
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.stone100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                LucideIcons.qrCode,
                size: 30,
                color: AppColors.stone400,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                color: AppColors.stone700,
              ),
            ),
            if (desc != null) ...[
              const SizedBox(height: 6),
              Text(
                desc!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.stone500),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Crvena pozadina za brisanje prevlačenjem.
Widget _dismissBackground(double radius) => Container(
  alignment: Alignment.centerRight,
  padding: const EdgeInsets.only(right: 20),
  decoration: BoxDecoration(
    color: AppColors.red50,
    borderRadius: BorderRadius.circular(radius),
  ),
  child: const Icon(LucideIcons.trash2, size: 20, color: AppColors.red600),
);

/// Prikačen kod: istaknuta kartica sa iznosom i brzim akcijama.
class _PinnedCard extends StatelessWidget {
  const _PinnedCard({
    required this.t,
    required this.code,
    required this.onShowQr,
    required this.onTogglePaid,
    required this.onDismissed,
    required this.confirmDismiss,
  });

  final Translations t;
  final SavedCode code;
  final VoidCallback onShowQr;
  final VoidCallback onTogglePaid;
  final VoidCallback onDismissed;
  final Future<bool> Function() confirmDismiss;

  @override
  Widget build(BuildContext context) {
    final amount = code.data.amount;
    final isTemplate = code.kind == SavedCodeKind.billTemplate;
    final isPaid = code.isPaidThisMonth;
    return Dismissible(
      key: ValueKey(code.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => confirmDismiss(),
      onDismissed: (_) => onDismissed(),
      background: _dismissBackground(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.stone200),
        ),
        child: Column(
          children: [
            SavedCodeTile(
              t: t,
              code: code,
              subtitle: code.data.recipientName.isNotEmpty
                  ? code.data.recipientName
                  : SavedCodeTile.maskedAccount(code),
              padding: EdgeInsets.zero,
              trailing: amount > 0
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatAmount(amount),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.stone900,
                          ),
                        ),
                        const Text(
                          'RSD',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.stone500,
                          ),
                        ),
                      ],
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _CardButton(
                    onTap: onShowQr,
                    icon: LucideIcons.qrCode,
                    label: t.showQr,
                    primary: true,
                  ),
                ),
                if (isTemplate) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CardButton(
                      onTap: onTogglePaid,
                      icon: isPaid
                          ? LucideIcons.circleCheck
                          : LucideIcons.check,
                      label: isPaid ? t.paidBadge : t.markPaidShort,
                      highlighted: isPaid,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.onTap,
    required this.icon,
    required this.label,
    this.primary = false,
    this.highlighted = false,
  });

  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final bool primary;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    return SizedBox(
      height: 40,
      child: primary
          ? FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.emerald600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: shape,
                elevation: 0,
              ),
              child: child,
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                backgroundColor: highlighted
                    ? AppColors.emerald50
                    : Colors.white,
                foregroundColor: highlighted
                    ? AppColors.emerald700
                    : AppColors.stone700,
                side: BorderSide(
                  color: highlighted
                      ? AppColors.emerald200
                      : AppColors.stone200,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: shape,
              ),
              child: child,
            ),
    );
  }
}

/// Ostali kodovi: jedna kartica sa redovima odvojenim linijom.
class _GroupedCard extends StatelessWidget {
  const _GroupedCard({
    required this.t,
    required this.codes,
    required this.onTap,
    required this.onDismissed,
    required this.confirmDismiss,
  });

  final Translations t;
  final List<SavedCode> codes;
  final ValueChanged<SavedCode> onTap;
  final ValueChanged<SavedCode> onDismissed;
  final Future<bool> Function() confirmDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.stone200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < codes.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, thickness: 1, color: AppColors.stone100),
            Dismissible(
              key: ValueKey(codes[i].id),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) => confirmDismiss(),
              onDismissed: (_) => onDismissed(codes[i]),
              background: _dismissBackground(0),
              child: Material(
                color: Colors.white,
                child: InkWell(
                  onTap: () => onTap(codes[i]),
                  child: SavedCodeTile(
                    t: t,
                    code: codes[i],
                    subtitle: _subtitle(codes[i]),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    trailing: const Icon(
                      LucideIcons.chevronRight,
                      size: 18,
                      color: AppColors.stone400,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _subtitle(SavedCode code) {
    final recipient =
        code.title.isNotEmpty && code.data.recipientName.isNotEmpty
        ? code.data.recipientName
        : SavedCodeTile.maskedAccount(code);
    return '$recipient · ${SavedCodeTile.amountLabel(code, t)}';
  }
}
