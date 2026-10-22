enum Language { sr, en }

class Translations {
  const Translations({
    required this.title,
    required this.subtitle,
    required this.scanTitle,
    required this.scanDesc,
    required this.openCamera,
    required this.uploadGallery,
    required this.pickPdf,
    required this.pasteClipboard,
    required this.clipboardEmpty,
    required this.or,
    required this.analyzing,
    required this.extracting,
    required this.processingSteps,
    required this.extracted,
    required this.extractedQr,
    required this.extractedOcr,
    required this.amount,
    required this.recipient,
    required this.account,
    required this.purpose,
    required this.reference,
    required this.paymentCode,
    required this.scanInstruction,
    required this.scanAnother,
    required this.errorTitle,
    required this.tryAgain,
    required this.cameraError,
    required this.processingError,
    required this.quotaError,
    required this.copied,
    required this.shareDesc,
    required this.copyIps,
    required this.share,
    required this.infoTitle,
    required this.version,
    required this.poweredBy,
    required this.close,
    required this.disclaimer,
    required this.validationError,
    required this.charLimit,
    required this.resDefault,
    required this.res720p,
    required this.res1080p,
    required this.resMax,
    required this.viewInvoice,
    required this.invalidFormNote,
    required this.savedCodesTitle,
    required this.searchHint,
    required this.filterAll,
    required this.filterBills,
    required this.filterOwn,
    required this.pin,
    required this.unpin,
    required this.markAsPaid,
    required this.paidThisMonth,
    required this.paidBadge,
    required this.editDetails,
    required this.codeTitleLabel,
    required this.codeTitleHint,
    required this.duplicateFoundTitle,
    required this.duplicateFoundMessage,
    required this.updateExisting,
    required this.saveNew,
    required this.noSavedCodesTitle,
    required this.noSavedCodesDesc,
    required this.noSearchResults,
    required this.addNew,
    required this.addViaCamera,
    required this.addViaGallery,
    required this.addViaManual,
    required this.save,
    required this.update,
    required this.delete,
    required this.cancel,
    required this.confirmDeleteTitle,
    required this.confirmDeleteMessage,
    required this.openAmountLabel,
    required this.openAmountHint,
    required this.ownCodeBannerTitle,
    required this.ownCodeInstruction,
    required this.savedToast,
    required this.exportCodes,
    required this.importCodes,
    required this.exportShareDesc,
    required this.importSuccessPrefix,
    required this.importErrorToast,
    required this.reviewTitle,
    required this.reviewMessage,
    required this.reviewRate,
    required this.reviewLater,
    required this.menu,
    required this.language,
    required this.back,
    required this.showAll,
    required this.pinnedSection,
    required this.otherSection,
    required this.paymentDetails,
    required this.add,
    required this.resultReady,
    required this.sourceQr,
    required this.sourceOcr,
    required this.sourceText,
    required this.sourceAi,
    required this.showQr,
    required this.markPaidShort,
    required this.saveInvoice,
    required this.newInvoice,
  });

  final String title;
  final String subtitle;
  final String scanTitle;
  final String scanDesc;
  final String openCamera;
  final String uploadGallery;
  final String pickPdf;
  final String pasteClipboard;
  final String clipboardEmpty;
  final String or;
  final String analyzing;
  final String extracting;
  final List<String> processingSteps;
  final String extracted;
  final String extractedQr;
  final String extractedOcr;
  final String amount;
  final String recipient;
  final String account;
  final String purpose;
  final String reference;
  final String paymentCode;
  final String scanInstruction;
  final String scanAnother;
  final String errorTitle;
  final String tryAgain;
  final String cameraError;
  final String processingError;
  final String quotaError;
  final String copied;
  final String shareDesc;
  final String copyIps;
  final String share;
  final String infoTitle;
  final String version;
  final String poweredBy;
  final String close;
  final String disclaimer;
  final String validationError;
  final String charLimit;
  final String resDefault;
  final String res720p;
  final String res1080p;
  final String resMax;
  final String viewInvoice;
  final String invalidFormNote;
  final String savedCodesTitle;
  final String searchHint;
  final String filterAll;
  final String filterBills;
  final String filterOwn;
  final String pin;
  final String unpin;
  final String markAsPaid;
  final String paidThisMonth;
  final String paidBadge;
  final String editDetails;
  final String codeTitleLabel;
  final String codeTitleHint;
  final String duplicateFoundTitle;
  final String duplicateFoundMessage;
  final String updateExisting;
  final String saveNew;
  final String noSavedCodesTitle;
  final String noSavedCodesDesc;
  final String noSearchResults;
  final String addNew;
  final String addViaCamera;
  final String addViaGallery;
  final String addViaManual;
  final String save;
  final String update;
  final String delete;
  final String cancel;
  final String confirmDeleteTitle;
  final String confirmDeleteMessage;
  final String openAmountLabel;
  final String openAmountHint;
  final String ownCodeBannerTitle;
  final String ownCodeInstruction;
  final String savedToast;
  final String exportCodes;
  final String importCodes;
  final String exportShareDesc;
  final String importSuccessPrefix;
  final String importErrorToast;
  final String reviewTitle;
  final String reviewMessage;
  final String reviewRate;
  final String reviewLater;
  final String menu;
  final String language;
  final String back;
  final String showAll;
  final String pinnedSection;
  final String otherSection;
  final String paymentDetails;
  final String add;
  final String resultReady;
  final String sourceQr;
  final String sourceOcr;
  final String sourceText;
  final String sourceAi;
  final String showQr;
  final String markPaidShort;
  final String saveInvoice;
  final String newInvoice;
}

const translations = <Language, Translations>{
  Language.sr: Translations(
    title: 'Invoice2IPS',
    subtitle: 'Skeniraj i plati IPS-om',
    scanTitle: 'Skenirajte račun',
    scanDesc:
        'Fotografišite račun i dobijte IPS QR kod za vašu bankarsku aplikaciju.',
    openCamera: 'Otvori kameru',
    uploadGallery: 'Galerija',
    pickPdf: 'PDF račun',
    pasteClipboard: 'Nalepi tekst',
    clipboardEmpty: 'Privremena memorija ne sadrži tekst',
    or: 'Ili',
    analyzing: 'Analiziranje računa',
    extracting: 'Očitavanje podataka sa računa...',
    processingSteps: [
      'Provera QR koda i teksta...',
      'Prepoznavanje iznosa i računa...',
      'Validacija podataka za plaćanje...',
    ],
    extracted: 'Podaci su pročitani',
    extractedQr: 'Učitan postojeći IPS QR kod',
    extractedOcr: 'Podaci su pročitani (OCR)',
    amount: 'Iznos (RSD)',
    recipient: 'Primalac',
    account: 'Račun',
    purpose: 'Svrha',
    reference: 'Poziv na broj',
    paymentCode: 'Šifra plaćanja',
    scanInstruction:
        'Skenirajte ovaj kod svojom mobilnom bankarskom aplikacijom za trenutno plaćanje.',
    scanAnother: 'Skeniraj sledeći',
    errorTitle: 'Nešto nije u redu',
    tryAgain: 'Pokušaj ponovo',
    cameraError: 'Nije moguće pristupiti kameri. Proverite dozvole.',
    processingError:
        'Nije uspelo izvlačenje podataka. Pokušajte ponovo sa jasnijom slikom.',
    quotaError:
        'Svi besplatni tokeni su iskorišćeni za ovaj obračunski period. Molimo vas da pokušate ponovo kasnije.',
    copied: 'Kopirano u privremenu memoriju',
    shareDesc: 'Podelite IPS QR kod kao sliku.',
    copyIps: 'Kopiraj IPS',
    share: 'Podeli',
    infoTitle: 'O aplikaciji',
    version: 'Verzija',
    poweredBy: 'Powered by',
    close: 'Zatvori',
    disclaimer:
        'Napomena: Uvek proverite pročitane podatke! AI ponekad može da pogreši.',
    validationError:
        'Nismo uspeli da dobijemo sve neophodne podatke za plaćanje sa slike (primalac, račun od 18 cifara, iznos). Molimo pokušajte ponovo.',
    charLimit: 'karaktera',
    resDefault: 'Automatski',
    res720p: 'HD (720p)',
    res1080p: 'Full HD (1080p)',
    resMax: 'Maksimalna (4K)',
    viewInvoice: 'Račun',
    invalidFormNote:
        'Popunite i ispravite sva obavezna polja označena crvenom bojom da bi QR kod bio validan.',
    savedCodesTitle: 'Sačuvani kodovi',
    searchHint: 'Pretraga po primaocu ili računu',
    filterAll: 'Svi',
    filterBills: 'Računi',
    filterOwn: 'Moji kodovi',
    pin: 'Zakači na vrh',
    unpin: 'Otkači sa vrha',
    markAsPaid: 'Označi kao plaćeno ovog meseca',
    paidThisMonth: 'Plaćeno ovog meseca',
    paidBadge: 'Plaćeno',
    editDetails: 'Izmeni sve detalje računa',
    codeTitleLabel: 'Naziv / Šablon (opciono)',
    codeTitleHint: 'npr. Struja - Stan',
    duplicateFoundTitle: 'Račun već postoji',
    duplicateFoundMessage:
        'Šablon za ovaj račun već postoji. Da li želite da ažurirate iznos na postojećem šablonu?',
    updateExisting: 'Ažuriraj postojeći',
    saveNew: 'Sačuvaj kao novi',
    noSavedCodesTitle: 'Nemate sačuvanih kodova',
    noSavedCodesDesc:
        'Napravite svoj IPS kod da vam neko drugi uplati na račun.',
    noSearchResults: 'Nema rezultata za ovu pretragu',
    addNew: 'Dodaj novi kod',
    addViaCamera: 'Skeniraj kamerom',
    addViaGallery: 'Izaberi iz galerije',
    addViaManual: 'Unesi ručno',
    save: 'Sačuvaj',
    update: 'Ažuriraj',
    delete: 'Obriši',
    cancel: 'Otkaži',
    confirmDeleteTitle: 'Obrisati kod?',
    confirmDeleteMessage: 'Ova radnja se ne može poništiti.',
    openAmountLabel: 'Otvoren iznos',
    openAmountHint:
        'Ostavite prazno za otvoren iznos — platilac sam unosi koliko šalje.',
    ownCodeBannerTitle: 'Vaš IPS kod',
    ownCodeInstruction:
        'Pokažite ovaj kod drugoj osobi da ga skenira svojom bankarskom aplikacijom i uplati vama.',
    savedToast: 'Kod je sačuvan',
    exportCodes: 'Izvezi kodove',
    importCodes: 'Uvezi kodove',
    exportShareDesc:
        'Fajl sa sačuvanim IPS kodovima — sačuvajte ga ili ga uvezite na drugom uređaju.',
    importSuccessPrefix: 'Uvezeno novih kodova: ',
    importErrorToast: 'Uvoz nije uspeo — proverite da li je fajl ispravan.',
    reviewTitle: 'Da li vam se sviđa Invoice2IPS?',
    reviewMessage:
        'Ocena u prodavnici aplikacija mnogo znači i pomaže drugima da pronađu aplikaciju.',
    reviewRate: 'Oceni aplikaciju',
    reviewLater: 'Možda kasnije',
    menu: 'Meni',
    language: 'Jezik',
    back: 'Nazad',
    showAll: 'Prikaži sve',
    pinnedSection: 'Prikačeno',
    otherSection: 'Ostalo',
    paymentDetails: 'Podaci za plaćanje',
    add: 'Dodaj',
    resultReady: 'IPS kod je spreman',
    sourceQr: 'Iz QR koda',
    sourceOcr: 'Pročitano sa računa',
    sourceText: 'Iz teksta',
    sourceAi: 'Izdvojeno AI-jem',
    showQr: 'Prikaži QR',
    markPaidShort: 'Označi plaćeno',
    saveInvoice: 'Sačuvaj račun',
    newInvoice: 'Novi račun',
  ),
  Language.en: Translations(
    title: 'Invoice2IPS',
    subtitle: 'Instant Pay Scan & Generate',
    scanTitle: 'Scan Your Invoice',
    scanDesc: 'Snap your invoice and get an IPS QR code for your banking app.',
    openCamera: 'Open Camera',
    uploadGallery: 'Gallery',
    pickPdf: 'PDF invoice',
    pasteClipboard: 'Paste text',
    clipboardEmpty: 'Clipboard does not contain any text',
    or: 'Or',
    analyzing: 'Analyzing Invoice',
    extracting: 'Reading invoice details...',
    processingSteps: [
      'Checking QR code & text...',
      'Detecting amount & account...',
      'Validating details...',
    ],
    extracted: 'Invoice Details Read',
    extractedQr: 'Existing IPS QR Code Read',
    extractedOcr: 'Invoice Details Read (OCR)',
    amount: 'Amount (RSD)',
    recipient: 'Recipient',
    account: 'Account',
    purpose: 'Purpose',
    reference: 'Reference',
    paymentCode: 'Payment Code',
    scanInstruction:
        'Scan this code with your mobile banking app to pay instantly.',
    scanAnother: 'Scan Another',
    errorTitle: 'Something went wrong',
    tryAgain: 'Try Again',
    cameraError: 'Could not access camera. Please check permissions.',
    processingError:
        'Failed to extract data from the invoice. Please try again with a clearer picture.',
    quotaError:
        'All available free tokens have been consumed for this billing period. Please try again later.',
    copied: 'Copied to clipboard',
    shareDesc: 'Share the IPS QR code as an image.',
    copyIps: 'Copy IPS',
    share: 'Share',
    infoTitle: 'About App',
    version: 'Version',
    poweredBy: 'Powered by',
    close: 'Close',
    disclaimer:
        'Note: Always verify the extracted data! AI can sometimes make mistakes.',
    validationError:
        "We couldn't extract all the necessary payment data from the image (recipient, 18-digit account, amount). Please try again.",
    charLimit: 'characters',
    resDefault: 'Auto',
    res720p: 'HD (720p)',
    res1080p: 'Full HD (1080p)',
    resMax: 'Maximum (4K)',
    viewInvoice: 'Invoice',
    invalidFormNote:
        'Fill in and correct all required fields marked in red for the QR code to be valid.',
    savedCodesTitle: 'Saved codes',
    searchHint: 'Search by recipient or account',
    filterAll: 'All',
    filterBills: 'Bills',
    filterOwn: 'My codes',
    pin: 'Pin to top',
    unpin: 'Unpin',
    markAsPaid: 'Mark as paid this month',
    paidThisMonth: 'Paid this month',
    paidBadge: 'Paid',
    editDetails: 'Edit all bill details',
    codeTitleLabel: 'Title / Template (optional)',
    codeTitleHint: 'e.g. Electricity - Home',
    duplicateFoundTitle: 'Bill already saved',
    duplicateFoundMessage:
        'A template for this bill already exists. Would you like to update the amount on the existing template?',
    updateExisting: 'Update existing',
    saveNew: 'Save as new',
    noSavedCodesTitle: 'No saved codes yet',
    noSavedCodesDesc: 'Create your own IPS code so someone can pay you.',
    noSearchResults: 'No results for this search',
    addNew: 'Add new code',
    addViaCamera: 'Scan with camera',
    addViaGallery: 'Choose from gallery',
    addViaManual: 'Enter manually',
    save: 'Save',
    update: 'Update',
    delete: 'Delete',
    cancel: 'Cancel',
    confirmDeleteTitle: 'Delete this code?',
    confirmDeleteMessage: 'This action cannot be undone.',
    openAmountLabel: 'Open amount',
    openAmountHint: 'Leave blank for an open amount — the payer enters it.',
    ownCodeBannerTitle: 'Your IPS code',
    ownCodeInstruction:
        'Show this code to someone else to scan with their banking app and pay you.',
    savedToast: 'Code saved',
    exportCodes: 'Export codes',
    importCodes: 'Import codes',
    exportShareDesc:
        'A file with your saved IPS codes — save it or import it on another device.',
    importSuccessPrefix: 'New codes imported: ',
    importErrorToast: 'Import failed — check that the file is valid.',
    reviewTitle: 'Enjoying Invoice2IPS?',
    reviewMessage:
        'A rating in the app store means a lot and helps others discover the app.',
    reviewRate: 'Rate the app',
    reviewLater: 'Maybe later',
    menu: 'Menu',
    language: 'Language',
    back: 'Back',
    showAll: 'See all',
    pinnedSection: 'Pinned',
    otherSection: 'Others',
    paymentDetails: 'Payment details',
    add: 'Add',
    resultReady: 'IPS code is ready',
    sourceQr: 'From QR code',
    sourceOcr: 'Read from invoice',
    sourceText: 'From text',
    sourceAi: 'Extracted by AI',
    showQr: 'Show QR',
    markPaidShort: 'Mark paid',
    saveInvoice: 'Save invoice',
    newInvoice: 'New invoice',
  ),
};
