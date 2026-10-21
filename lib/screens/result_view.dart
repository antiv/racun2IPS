import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../constants/ips.dart';
import '../i18n/translations.dart';
import '../models/invoice_data.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../utils/ips.dart';
import '../widgets/editable_row.dart';
import '../widgets/editable_select_row.dart';

/// Ekran rezultata: QR kartica sa iznosom i deljenjem/kopiranjem,
/// editabilna polja sa validacijom i oznakom izvora podataka, donji bar
/// "Sačuvaj račun"/"Novi račun" (payInvoice) ili "Sačuvaj"/"Ažuriraj"/"Obriši"
/// (ownCode).
class ResultView extends StatelessWidget {
  const ResultView({
    super.key,
    required this.t,
    required this.data,
    required this.copied,
    required this.onChanged,
    required this.onCopy,
    required this.onShare,
    required this.onReset,
    required this.mode,
    this.isEditingExisting = false,
    this.onSave,
    this.onDelete,
    this.onSaveScanned,
    this.extractionSource,
    this.codeTitle,
    this.onTitleChanged,
  });

  final Translations t;
  final InvoiceData data;
  final bool copied;
  final ExtractionSource? extractionSource;
  final String? codeTitle;
  final ValueChanged<String>? onTitleChanged;
  final VoidCallback onChanged;
  final ValueChanged<String> onCopy;
  final VoidCallback onShare;
  final VoidCallback onReset;
  final ResultMode mode;
  final bool isEditingExisting;
  // Suvišni u payInvoice modu, pa ostaju nullable za razliku od ostatka fajla.
  final VoidCallback? onSave;
  final VoidCallback? onDelete;
  // Čuvanje skeniranog (payInvoice) računa među sačuvane kodove — nezavisno
  // od onSave (koje se koristi za Sačuvaj/Ažuriraj u ownCode modu).
  final VoidCallback? onSaveScanned;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    final isOwnCode = mode == ResultMode.ownCode;
    final isAccountValid = validateAccountNumber(data.accountNumber);
    final isAmountValid = isOwnCode ? data.amount >= 0 : data.amount > 0;
    final isRecipientValid = data.recipientName.trim().isNotEmpty &&
        data.recipientName.length <= IpsLimits.n;
    final isPurposeValid = data.purpose.isEmpty || data.purpose.length <= IpsLimits.s;
    final isReferenceValid = validateReferenceNumber(data.referenceNumber);
    final isSfValid = RegExp(r'^\d{3}$')
        .hasMatch(data.paymentCode.isEmpty ? '289' : data.paymentCode);
    final hasPipe = [
      data.recipientName,
      data.purpose,
      data.referenceNumber,
      data.paymentCode,
    ].any((v) => v.contains('|'));
    final isFormValid = isAccountValid &&
        isAmountValid &&
        isRecipientValid &&
        isPurposeValid &&
        isReferenceValid &&
        isSfValid &&
        !hasPipe;

    final ipsString = generateIpsString(data, allowOpenAmount: isOwnCode);
    // Kratka oznaka izvora podataka pored naslova "Podaci za plaćanje".
    final sourceLabel = isOwnCode
        ? null
        : switch (extractionSource) {
            ExtractionSource.qr => t.sourceQr,
            ExtractionSource.ocr => t.sourceOcr,
            ExtractionSource.text => t.sourceText,
            ExtractionSource.ai => t.sourceAi,
            null => null,
          };

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            children: [
              // 2. QR kartica
              Container(
                padding: const EdgeInsets.all(20),
                decoration: _cardDecoration(24),
                child: Column(
                  children: [
                    Opacity(
                      opacity: isFormValid ? 1 : 0.4,
                      child: IgnorePointer(
                        ignoring: !isFormValid,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: AppColors.stone100),
                              ),
                              child: QrImageView(
                                data: ipsString,
                                version: QrVersions.auto,
                                errorCorrectionLevel: QrErrorCorrectLevel.M,
                                size: 176,
                                padding: EdgeInsets.zero,
                                backgroundColor: Colors.transparent,
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
                            if (data.amount > 0)
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text.rich(
                                  TextSpan(
                                    text: formatAmount(data.amount),
                                    children: const [
                                      TextSpan(
                                        text: ' RSD',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0,
                                          color: AppColors.stone500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.8,
                                    color: AppColors.stone900,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 2),
                            Text(
                              isOwnCode ? t.ownCodeInstruction : t.scanInstruction,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: AppColors.stone500,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: _QrActionButton(
                                    onTap: onShare,
                                    icon: LucideIcons.share2,
                                    label: t.share,
                                    primary: true,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _QrActionButton(
                                    onTap: () => onCopy(ipsString),
                                    icon: copied
                                        ? LucideIcons.circleCheck
                                        : LucideIcons.copy,
                                    label: t.copyIps,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!isFormValid) ...[
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.red50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          t.invalidFormNote,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.red600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 3. Kartica sa poljima
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        t.paymentDetails,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.stone900,
                        ),
                      ),
                    ),
                    if (sourceLabel != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.emerald50,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          sourceLabel,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.emerald700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                decoration: _cardDecoration(20),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    if (isOwnCode || isEditingExisting) ...[
                      EditableRow(
                        label: t.codeTitleLabel,
                        value: codeTitle ?? '',
                        maxLength: 40,
                        hintText: t.codeTitleHint,
                        onChanged: (val) {
                          onTitleChanged?.call(val);
                        },
                      ),
                      const _RowDivider(),
                    ],
                    EditableRow(
                      label: t.recipient,
                      value: data.recipientName,
                      maxLength: IpsLimits.n,
                      error: !isRecipientValid || data.recipientName.contains('|'),
                      onChanged: (val) {
                        data.recipientName = val;
                        onChanged();
                      },
                    ),
                    const _RowDivider(),
                    EditableRow(
                      label: t.account,
                      value: data.accountNumber,
                      isMono: true,
                      error: !isAccountValid,
                      keyboardType: TextInputType.number,
                      onChanged: (val) {
                        data.accountNumber = parseAccountNumber(val);
                        onChanged();
                      },
                    ),
                    const _RowDivider(),
                    _AmountRow(
                      label: t.amount,
                      amount: data.amount,
                      error: !isAmountValid,
                      onChanged: (val) {
                        data.amount = val;
                        onChanged();
                      },
                    ),
                    if (isOwnCode)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 11),
                        child: Text(
                          t.openAmountHint,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.stone400,
                          ),
                        ),
                      ),
                    const _RowDivider(),
                    EditableSelectRow(
                      label: t.paymentCode,
                      value: data.paymentCode.isEmpty ? '289' : data.paymentCode,
                      error: !isSfValid || data.paymentCode.contains('|'),
                      onChanged: (val) {
                        data.paymentCode = val;
                        onChanged();
                      },
                    ),
                    const _RowDivider(),
                    EditableRow(
                      label: t.purpose,
                      value: data.purpose,
                      maxLength: IpsLimits.s,
                      error: !isPurposeValid || data.purpose.contains('|'),
                      onChanged: (val) {
                        data.purpose = val;
                        onChanged();
                      },
                    ),
                    const _RowDivider(),
                    EditableRow(
                      label: t.reference,
                      value: data.referenceNumber,
                      maxLength: IpsLimits.ro,
                      isMono: true,
                      error: !isReferenceValid || data.referenceNumber.contains('|'),
                      onChanged: (val) {
                        data.referenceNumber = val;
                        onChanged();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Donji bar sa akcijama, uvek vidljiv
        Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
          child: SizedBox(
            height: 50,
            child: Row(
              children: !isOwnCode
                  ? [
                      if (onSaveScanned != null) ...[
                        Expanded(
                          child: _BottomButton(
                            onTap: isFormValid ? onSaveScanned : null,
                            icon: LucideIcons.bookmark,
                            label: t.saveInvoice,
                            style: _BottomStyle.outline,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: _BottomButton(
                          onTap: onReset,
                          icon: LucideIcons.rotateCcw,
                          label: t.newInvoice,
                          style: _BottomStyle.soft,
                        ),
                      ),
                    ]
                  : [
                      if (isEditingExisting) ...[
                        Expanded(
                          child: _BottomButton(
                            onTap: onDelete,
                            icon: LucideIcons.trash2,
                            label: t.delete,
                            style: _BottomStyle.danger,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: _BottomButton(
                          onTap: isFormValid ? onSave : null,
                          icon: LucideIcons.check,
                          label: isEditingExisting ? t.update : t.save,
                          style: _BottomStyle.primary,
                        ),
                      ),
                    ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _BottomStyle { outline, soft, primary, danger }

/// Dugme u donjem baru ekrana rezultata.
class _BottomButton extends StatelessWidget {
  const _BottomButton({
    required this.onTap,
    required this.icon,
    required this.label,
    required this.style,
  });

  final VoidCallback? onTap;
  final IconData icon;
  final String label;
  final _BottomStyle style;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (style) {
      _BottomStyle.outline => (Colors.white, AppColors.stone700, AppColors.stone200),
      _BottomStyle.soft => (AppColors.stone100, AppColors.stone800, AppColors.stone100),
      _BottomStyle.primary => (AppColors.emerald600, Colors.white, AppColors.emerald600),
      _BottomStyle.danger => (Colors.white, AppColors.red600, AppColors.red400),
    };
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: bg.withValues(alpha: 0.5),
        side: BorderSide(color: border),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}


/// Bela kartica sa tankom ivicom i jedva vidljivom senkom.
BoxDecoration _cardDecoration(double radius) => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppColors.stone200),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A1C1917),
          blurRadius: 2,
          offset: Offset(0, 1),
        ),
      ],
    );

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 14),
      child: Divider(height: 1, thickness: 1, color: AppColors.stone100),
    );
  }
}

class _AmountRow extends StatefulWidget {
  const _AmountRow({
    required this.label,
    required this.amount,
    required this.error,
    required this.onChanged,
  });

  final String label;
  final double amount;
  final bool error;
  final ValueChanged<double> onChanged;

  @override
  State<_AmountRow> createState() => _AmountRowState();
}

class _AmountRowState extends State<_AmountRow> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.amount > 0 ? _format(widget.amount) : '',
  );

  static String _format(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: widget.error ? AppColors.red600 : AppColors.stone500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _controller,
                  textAlign: TextAlign.right,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  onChanged: (val) {
                    final parsed = double.tryParse(val.replaceAll(',', '.'));
                    widget.onChanged(parsed ?? 0);
                  },
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: '0.00',
                    hintStyle: TextStyle(color: AppColors.stone300),
                  ),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color:
                        widget.error ? AppColors.red600 : AppColors.emerald600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                'RSD',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.stone400,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QrActionButton extends StatelessWidget {
  const _QrActionButton({
    required this.onTap,
    required this.icon,
    required this.label,
    this.primary = false,
  });

  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 17),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    return SizedBox(
      height: 46,
      child: primary
          ? FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.emerald600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                shape: shape,
                elevation: 0,
              ),
              child: content,
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.stone700,
                side: const BorderSide(color: AppColors.stone200),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                shape: shape,
              ),
              child: content,
            ),
    );
  }
}
