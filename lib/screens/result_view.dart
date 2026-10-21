import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../constants/ips.dart';
import '../i18n/translations.dart';
import '../models/invoice_data.dart';
import '../theme.dart';
import '../utils/ips.dart';
import '../widgets/editable_row.dart';
import '../widgets/editable_select_row.dart';

/// Ekran rezultata: banner, QR kartica sa kopiranjem/deljenjem,
/// editabilna polja sa validacijom, dugme "Skeniraj sledeći" (payInvoice)
/// ili "Sačuvaj"/"Ažuriraj"/"Obriši" (ownCode).
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
    required this.onViewImage,
    required this.mode,
    this.isEditingExisting = false,
    this.onSave,
    this.onDelete,
    this.onSaveScanned,
    this.image,
    this.extractionSource,
  });

  final Translations t;
  final InvoiceData data;
  final bool copied;
  final Uint8List? image;
  final ExtractionSource? extractionSource;
  final VoidCallback onChanged;
  final ValueChanged<String> onCopy;
  final VoidCallback onShare;
  final VoidCallback onReset;
  final VoidCallback onViewImage;
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
    final bannerTitle = isOwnCode
        ? t.ownCodeBannerTitle
        : switch (extractionSource) {
            ExtractionSource.qr => t.extractedQr,
            ExtractionSource.ocr => t.extractedOcr,
            _ => t.extracted,
          };

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            children: [
              // 1. Banner uspeha
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                decoration: BoxDecoration(
                  color: AppColors.emerald50,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Icon(
                      isOwnCode || extractionSource == ExtractionSource.qr
                          ? Icons.qr_code_2
                          : Icons.check_circle_outline,
                      size: 22,
                      color: AppColors.emerald700,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        bannerTitle,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.emerald700,
                        ),
                      ),
                    ),
                    if (image != null)
                      GestureDetector(
                        onTap: onViewImage,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppColors.emerald600,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.open_in_new,
                                  size: 13, color: Colors.white),
                              const SizedBox(width: 5),
                              Text(
                                t.viewInvoice,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 2. QR kartica
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.stone100),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                      spreadRadius: -16,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Opacity(
                      opacity: isFormValid ? 1 : 0.4,
                      child: IgnorePointer(
                        ignoring: !isFormValid,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.stone50,
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
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: _QrActionButton(
                                    onTap: () => onCopy(ipsString),
                                    icon: copied
                                        ? Icons.check_circle_outline
                                        : Icons.copy,
                                    iconColor: copied
                                        ? AppColors.emerald500
                                        : AppColors.stone600,
                                    label: t.copyIps,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _QrActionButton(
                                    onTap: onShare,
                                    icon: Icons.share_outlined,
                                    iconColor: AppColors.stone600,
                                    label: t.share,
                                  ),
                                ),
                                if (onSaveScanned != null) ...[
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _QrActionButton(
                                      onTap: onSaveScanned!,
                                      icon: Icons.bookmark_add_outlined,
                                      iconColor: AppColors.stone600,
                                      label: t.save,
                                    ),
                                  ),
                                ],
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
              const SizedBox(height: 16),

              // 3. Kartica sa poljima
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.stone100),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x38000000),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                      spreadRadius: -18,
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
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
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 11),
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
              const SizedBox(height: 16),

              // 4. Instrukcija
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  isOwnCode ? t.ownCodeInstruction : t.scanInstruction,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: AppColors.stone400,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Donji bar sa akcijom, uvek vidljiv
        Container(
          padding: EdgeInsets.fromLTRB(18, 12, 18, 16 + bottomInset),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [AppColors.stone50, Color(0x00FAFAF9)],
            ),
          ),
          child: !isOwnCode
              ? SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: onReset,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.stone900,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(t.scanAnother),
                  ),
                )
              : isEditingExisting
                  ? SizedBox(
                      height: 54,
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: onDelete,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.red600,
                                side:
                                    const BorderSide(color: AppColors.red400),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              child: Text(t.delete),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: isFormValid ? onSave : null,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.stone900,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              child: Text(t.update),
                            ),
                          ),
                        ],
                      ),
                    )
                  : SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        onPressed: isFormValid ? onSave : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.stone900,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: Text(t.save),
                      ),
                    ),
        ),
      ],
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 16),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            widget.label.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.05,
              color: widget.error ? AppColors.red400 : AppColors.stone400,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SizedBox(
                width: 120,
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
    required this.iconColor,
    required this.label,
  });

  final VoidCallback onTap;
  final IconData icon;
  final Color iconColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.stone50,
          foregroundColor: AppColors.stone600,
          side: const BorderSide(color: AppColors.stone100),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: iconColor),
            const SizedBox(width: 7),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.48,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
