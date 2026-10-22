import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../i18n/translations.dart';
import '../models/saved_code.dart';
import '../theme.dart';
import '../utils/ips.dart';

/// Modalni prikaz (Bottom Sheet) za brzi pregled QR koda, brzu izmenu iznosa,
/// kopiranje/deljenje i označavanje računa kao plaćenog za tekući mesec.
class QuickQrSheet extends StatefulWidget {
  const QuickQrSheet({
    super.key,
    required this.t,
    required this.code,
    required this.onCopy,
    required this.onShare,
    required this.onTogglePin,
    required this.onTogglePaid,
    required this.onAmountUpdated,
    required this.onEditDetails,
  });

  final Translations t;
  final SavedCode code;
  final ValueChanged<String> onCopy;
  final VoidCallback onShare;
  final VoidCallback onTogglePin;
  final VoidCallback onTogglePaid;
  final ValueChanged<double> onAmountUpdated;
  final VoidCallback onEditDetails;

  @override
  State<QuickQrSheet> createState() => _QuickQrSheetState();
}

class _QuickQrSheetState extends State<QuickQrSheet> {
  late double _amount = widget.code.data.amount;
  late final TextEditingController _amountController;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: _amount > 0 ? _formatAmount(_amount) : '',
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  static String _formatAmount(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  String get _maskedAccount {
    final acc = widget.code.data.accountNumber;
    if (acc.length < 4) return acc;
    return '•••• ${acc.substring(acc.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final code = widget.code;
    final isTemplate = code.kind == SavedCodeKind.billTemplate;

    // Kloniramo podatke sa trenutno unetim iznosom za dinamičko generisanje QR koda
    final currentData = code.data.copyWith()..amount = _amount;
    final ipsString = generateIpsString(
      currentData,
      allowOpenAmount: !isTemplate,
    );

    final title = code.title.isNotEmpty
        ? code.title
        : (code.data.recipientName.isNotEmpty
              ? code.data.recipientName
              : _maskedAccount);

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 38,
              height: 5,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.stone200,
                borderRadius: BorderRadius.circular(3),
              ),
            ),

            // Header sa nazivom, pinom i zatvaranjem
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: AppColors.stone800,
                        ),
                      ),
                      if (code.title.isNotEmpty &&
                          code.data.recipientName.isNotEmpty)
                        Text(
                          code.data.recipientName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.stone400,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: code.isPinned ? t.unpin : t.pin,
                  icon: Icon(
                    code.isPinned ? LucideIcons.pin : LucideIcons.pinOff,
                    size: 20,
                    color: code.isPinned
                        ? AppColors.emerald600
                        : AppColors.stone400,
                  ),
                  onPressed: () {
                    widget.onTogglePin();
                    setState(() {});
                  },
                ),
                IconButton(
                  icon: const Icon(
                    LucideIcons.x,
                    size: 20,
                    color: AppColors.stone400,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // QR kod
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.stone50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.stone100),
              ),
              child: QrImageView(
                data: ipsString,
                version: QrVersions.auto,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
                size: 200,
                padding: EdgeInsets.zero,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: AppColors.qrFg,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: AppColors.qrFg,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Brza izmena iznosa za mesečne račune
            if (isTemplate) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.stone50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.stone200),
                ),
                child: Row(
                  children: [
                    Text(
                      t.amount.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: AppColors.stone500,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 140,
                      child: TextField(
                        controller: _amountController,
                        textAlign: TextAlign.right,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        onChanged: (val) {
                          final parsed = double.tryParse(
                            val.replaceAll(',', '.'),
                          );
                          final newAmt = parsed ?? 0;
                          setState(() => _amount = newAmt);
                          widget.onAmountUpdated(newAmt);
                        },
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.emerald700,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          hintText: '0.00',
                          hintStyle: TextStyle(color: AppColors.stone300),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'RSD',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.stone500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Detalji: račun i poziv na broj
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.stone50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        t.account,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.stone400,
                        ),
                      ),
                      Text(
                        code.data.accountNumber,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                          color: AppColors.stone700,
                        ),
                      ),
                    ],
                  ),
                  if (code.data.referenceNumber.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          t.reference,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.stone400,
                          ),
                        ),
                        Text(
                          code.data.referenceNumber,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                            color: AppColors.stone700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Dugmad akcija
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      widget.onCopy(ipsString);
                      setState(() => _copied = true);
                      Future.delayed(const Duration(seconds: 2), () {
                        if (mounted) setState(() => _copied = false);
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.stone200),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: Icon(
                      _copied ? LucideIcons.circleCheck : LucideIcons.copy,
                      size: 16,
                      color: _copied
                          ? AppColors.emerald600
                          : AppColors.stone700,
                    ),
                    label: Text(
                      t.copyIps,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.stone700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onShare,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.stone200),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(
                      LucideIcons.share2,
                      size: 16,
                      color: AppColors.stone700,
                    ),
                    label: Text(
                      t.share,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.stone700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Oznaka "Plaćeno ovog meseca" za šablone
            if (isTemplate)
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    widget.onTogglePaid();
                    setState(() {});
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: code.isPaidThisMonth
                        ? AppColors.emerald50
                        : AppColors.stone100,
                    foregroundColor: code.isPaidThisMonth
                        ? AppColors.emerald700
                        : AppColors.stone600,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: Icon(
                    code.isPaidThisMonth
                        ? LucideIcons.circleCheck
                        : LucideIcons.circle,
                    size: 18,
                  ),
                  label: Text(
                    code.isPaidThisMonth ? t.paidThisMonth : t.markAsPaid,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 4),

            // Uredi sve detalje
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onEditDetails();
              },
              child: Text(
                t.editDetails,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.stone500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
