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
}

enum AppState { idle, capturing, processing, result, error }

enum CameraRes { def, hd720, fhd1080, max }
