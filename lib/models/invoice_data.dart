class InvoiceData {
  InvoiceData({
    this.recipientName = '',
    this.accountNumber = '',
    this.amount = 0,
    this.paymentCode = '289',
    this.purpose = '',
    this.referenceNumber = '',
  });

  String recipientName;
  String accountNumber;
  double amount;
  String paymentCode;
  String purpose;
  String referenceNumber;

  factory InvoiceData.fromJson(Map<String, dynamic> json) => InvoiceData(
        recipientName: json['recipientName'] as String? ?? '',
        accountNumber: json['accountNumber'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        paymentCode: json['paymentCode'] as String? ?? '289',
        purpose: json['purpose'] as String? ?? '',
        referenceNumber: json['referenceNumber'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'recipientName': recipientName,
        'accountNumber': accountNumber,
        'amount': amount,
        'paymentCode': paymentCode,
        'purpose': purpose,
        'referenceNumber': referenceNumber,
      };

  // Nezavisna kopija — ResultView mutira polja in-place, pa se otvaranje
  // sačuvanog koda za editovanje mora raditi nad klonom, ne originalom.
  InvoiceData copyWith() => InvoiceData(
        recipientName: recipientName,
        accountNumber: accountNumber,
        amount: amount,
        paymentCode: paymentCode,
        purpose: purpose,
        referenceNumber: referenceNumber,
      );
}

enum AppState { idle, capturing, processing, result, error, savedList }

enum CameraRes { def, hd720, fhd1080, max }

// payInvoice: skeniran tuđi račun koji se plaća (postojeći tok).
// ownCode: sopstveni IPS kod koji korisnik pravi da ga neko drugi skenira i plati njemu.
enum ResultMode { payInvoice, ownCode }

/// Izvor iz kog su podaci računa izvučeni:
/// - [qr]: direktno pročitan postojeći NBS IPS QR kod (ili IPS string u tekstu),
/// - [ocr]: izvučeno lokalnim OCR-om na uređaju (ML Kit),
/// - [text]: izvučeno lokalnim parserom iz nalepljenog/deljenog teksta,
/// - [ai]: izvučeno pomoću Gemini AI modela.
enum ExtractionSource { qr, ocr, text, ai }
