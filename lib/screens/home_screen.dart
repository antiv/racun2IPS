import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';

import '../i18n/translations.dart';
import '../models/invoice_data.dart';
import '../models/saved_code.dart';
import '../services/gemini_service.dart';
import '../services/local_ocr_service.dart';
import '../services/qr_scanner_service.dart';
import '../services/review_service.dart';
import '../services/saved_codes_service.dart';
import '../services/shared_image.dart';
import '../theme.dart';
import '../utils/backup.dart' as backup_utils;
import '../utils/invoice_text_parser.dart';
import '../utils/ips.dart';
import '../utils/share.dart' as share_utils;
import '../widgets/app_menu_sheet.dart';
import '../widgets/info_sheet.dart';
import '../widgets/quick_qr_sheet.dart';
import '../widgets/review_sheet.dart';
import 'camera_view.dart';
import 'edit_saved_code_screen.dart';
import 'error_view.dart';
import 'idle_view.dart';
import 'processing_view.dart';
import 'result_view.dart';
import 'saved_codes_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Language _lang = Language.sr;
  CameraRes _resolution = CameraRes.max;
  AppState _state = AppState.idle;
  Uint8List? _image;
  InvoiceData? _invoiceData;
  String? _error;
  bool _copied = false;
  Timer? _copiedTimer;
  // Poruka prikazana u donjem toast-u (kopirano/sačuvano/uvezeno...).
  String? _toastText;
  Timer? _toastTimer;

  CameraController? _cameraController;
  bool _cameraReady = false;
  Future<void> _cameraOp = Future.value();
  bool _torchOn = false;
  bool _hasTorch = false;

  Timer? _sharedPollTimer;
  bool _checkingShared = false;

  final _savedCodesService = SavedCodesService();
  final _reviewService = ReviewService();
  final _qrScannerService = QrScannerService();
  final _localOcrService = LocalOcrService();
  // True kad je dostignut prag skeniranih računa, a ponuda za ocenjivanje
  // čeka da korisnik napusti ekran rezultata (da ne prekriva QR kod).
  bool _reviewPending = false;

  List<SavedCode> _savedCodes = [];
  ResultMode _resultMode = ResultMode.payInvoice;
  ExtractionSource? _extractionSource;
  // Not null samo kad je ResultView otvoren nad postojećim sačuvanim kodom.
  String? _editingSavedId;
  String _editingTitle = '';

  Translations get _t => translations[_lang]!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSavedCodes();
    _checkSharedPayload();
    // Android WebView/intent događaji umeju da budu nepouzdani — original
    // koristi polling na 1.5s, zadržavamo isto ponašanje.
    _sharedPollTimer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => _checkSharedPayload(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sharedPollTimer?.cancel();
    _copiedTimer?.cancel();
    _toastTimer?.cancel();
    _stopCameraQueued();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkSharedPayload();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (_state == AppState.capturing) _reset();
    }
  }

  // --- Slika, PDF ili tekst podeljen iz druge aplikacije (ACTION_SEND) ---

  Future<void> _checkSharedPayload() async {
    if (_checkingShared || _state == AppState.processing) return;
    _checkingShared = true;
    try {
      final payload = await getSharedPayload();
      if (payload != null && mounted) {
        _stopCameraQueued();
        // Sadržaj deljen iz druge aplikacije je uvek "plati ovaj račun".
        _resultMode = ResultMode.payInvoice;
        _editingSavedId = null;
        switch (payload.type) {
          case SharedPayloadType.image:
            setState(() => _image = payload.bytes);
            await _processInvoice(payload.bytes!);
          case SharedPayloadType.pdf:
            await _processPdf(payload.bytes!);
          case SharedPayloadType.text:
            await _processText(payload.text!);
        }
      }
    } finally {
      _checkingShared = false;
    }
  }

  // --- Kamera ---

  ResolutionPreset get _preset {
    switch (_resolution) {
      case CameraRes.def:
        return ResolutionPreset.medium;
      case CameraRes.hd720:
        return ResolutionPreset.high;
      case CameraRes.fhd1080:
        return ResolutionPreset.veryHigh;
      case CameraRes.max:
        return ResolutionPreset.max;
    }
  }

  // Serijalizuje start/stop kamere: sprečava da se novi poziv (npr. brza
  // promena rezolucije) dispose-uje kontroler dok mu je initialize() još
  // u toku, što izaziva "used after being disposed" iz camera plugin-a.
  Future<void> _startCamera([CameraRes? res]) {
    final op = _cameraOp.then((_) => _startCameraImpl(res));
    _cameraOp = op;
    return op;
  }

  Future<void> _startCameraImpl(CameraRes? res) async {
    try {
      setState(() => _cameraReady = false);
      if (res != null) _resolution = res;
      await _stopCamera();

      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        _preset,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _cameraController = controller;
      setState(() => _state = AppState.capturing);
      await controller.initialize();
      if (!mounted) return;
      // Torch podrška se ne može upitati unapred — probaj, pa sakrij dugme.
      var hasTorch = true;
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {
        hasTorch = false;
      }
      setState(() {
        _cameraReady = true;
        _hasTorch = hasTorch;
      });
    } catch (e) {
      debugPrint('Error accessing camera: $e');
      if (!mounted) return;
      setState(() {
        _error = _t.cameraError;
        _state = AppState.error;
      });
    }
  }

  // Isto kao _startCamera: sprečava dispose kontrolera dok je start još u toku.
  Future<void> _stopCameraQueued() {
    final op = _cameraOp.then((_) => _stopCamera());
    _cameraOp = op;
    return op;
  }

  Future<void> _stopCamera() async {
    final controller = _cameraController;
    _cameraController = null;
    _torchOn = false;
    _hasTorch = false;
    _cameraReady = false;
    await controller?.dispose();
  }

  Future<void> _toggleTorch() async {
    final controller = _cameraController;
    if (controller == null || !_hasTorch) return;
    try {
      final next = !_torchOn;
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      setState(() => _torchOn = next);
    } catch (e) {
      debugPrint('Error toggling torch: $e');
      setState(() => _hasTorch = false);
    }
  }

  Future<void> _capturePhoto() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      await _stopCameraQueued();
      if (!mounted) return;
      setState(() => _image = bytes);
      await _processInvoice(bytes);
    } catch (e) {
      debugPrint('Error capturing photo: $e');
    }
  }

  Future<void> _pickFromGallery() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    setState(() => _image = bytes);
    await _processInvoice(bytes);
  }

  Future<void> _pickPdf() async {
    try {
      final bytes = await backup_utils.pickPdfDocumentBytes();
      if (bytes == null) {
        // Korisnik je otkazao izbor - osiguraj da aplikacija ostane u idle stanju
        if (mounted && _state != AppState.idle) {
          setState(() => _state = AppState.idle);
        }
        return;
      }
      if (!mounted) return;
      _resultMode = ResultMode.payInvoice;
      _editingSavedId = null;
      await _processPdf(bytes);
    } catch (e) {
      debugPrint('Greška pri izboru PDF-a: $e');
      if (mounted) {
        _showToast('Nije moguće otvoriti izabrani PDF');
      }
    }
  }

  Future<void> _pasteFromClipboard() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clip?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      _showToast(_t.clipboardEmpty);
      return;
    }
    _resultMode = ResultMode.payInvoice;
    _editingSavedId = null;
    await _processText(text);
  }

  // --- Obrada ---

  Future<void> _processInvoice(Uint8List imageBytes) {
    return _runExtraction(
      () => _extractFromImages(
        [imageBytes],
        aiFallback: () => processInvoice(imageBytes),
      ),
    );
  }

  /// PDF: stranice se renderuju u slike (native PdfRenderer / PDFKit) i
  /// prolaze isti QR → OCR tok kao fotografija. Ako lokalno ne uspe, Gemini-ju
  /// se šalje originalni PDF (podržava application/pdf), ne samo jedna stranica.
  Future<void> _processPdf(Uint8List pdfBytes) {
    return _runExtraction(() async {
      final pages = await renderPdfPages(pdfBytes);
      if (pages.isEmpty) {
        // Renderovanje nije uspelo (npr. zaštićen PDF) — probaj direktno AI.
        final aiData = await processInvoice(pdfBytes);
        return (aiData, ExtractionSource.ai, null);
      }
      return _extractFromImages(
        pages,
        aiFallback: () => processInvoice(pdfBytes),
      );
    });
  }

  /// Tekst (clipboard ili deljena poruka): IPS string → lokalni parser → Gemini
  /// tekstualni prompt (bez slike, znatno jeftinije u tokenima).
  Future<void> _processText(String text) {
    setState(() => _image = null);
    return _runExtraction(() async {
      final ipsMatch = RegExp(r'K:(?:PR|EK)\|[^\r\n]+', caseSensitive: false)
          .firstMatch(text);
      if (ipsMatch != null) {
        final ipsData = parseIpsString(ipsMatch.group(0)!);
        if (ipsData != null && validateAccountNumber(ipsData.accountNumber)) {
          return (ipsData, ExtractionSource.qr, null);
        }
      }
      final local = tryParseInvoiceText(text);
      if (local != null) return (local, ExtractionSource.text, null);

      // Tekst bez ijednog broja (npr. podeljen link ili obična poruka) ne može
      // sadržati račun — ne troši AI poziv.
      if (!RegExp(r'\d{3,}').hasMatch(text)) {
        throw Exception('ValidationFailed: tekst ne sadrži podatke za plaćanje');
      }
      final aiData = await processInvoiceText(text);
      return (aiData, ExtractionSource.ai, null);
    });
  }

  /// Zajednički okvir obrade: prikaz ProcessingView-a, prelaz na rezultat
  /// i mapiranje grešaka (kvota / validacija / ostalo) na poruke.
  Future<void> _runExtraction(
    Future<(InvoiceData, ExtractionSource, Uint8List?)> Function() job,
  ) async {
    setState(() {
      _state = AppState.processing;
      _error = null;
      _extractionSource = null;
    });
    try {
      final (data, source, previewImage) = await job();
      if (!mounted) return;
      setState(() {
        _invoiceData = data;
        _extractionSource = source;
        if (previewImage != null) _image = previewImage;
        _state = AppState.result;
      });
      // Broje se samo skenirani računi — pravljenje sopstvenog IPS koda nije
      // skeniranje računa. Ne ide kroz setState, polje ne utiče na render.
      if (_resultMode == ResultMode.payInvoice) {
        _reviewPending = await _reviewService.registerScan();
      }
    } catch (e) {
      debugPrint('Processing error: $e');
      if (!mounted) return;
      final msg = e.toString();
      setState(() {
        if (msg.contains('Quota exceeded') || msg.contains('429')) {
          _error = _t.quotaError;
        } else if (msg.contains('ValidationFailed')) {
          _error = _t.validationError;
        } else {
          _error = _t.processingError;
        }
        _state = AppState.error;
      });
    }
  }

  /// Trostepena ekstrakcija nad jednom ili više slika (stranica):
  /// 1. Lokalni QR skener na svim stranicama (postojeći NBS IPS QR kod),
  /// 2. Lokalni OCR na uređaju + Modulo-97 validacija,
  /// 3. [aiFallback] (Gemini) ako lokalne metode ne izvuku potpune podatke.
  /// Vraća i sliku stranice na kojoj su podaci nađeni, za "Pogledaj račun".
  Future<(InvoiceData, ExtractionSource, Uint8List?)> _extractFromImages(
    List<Uint8List> images, {
    required Future<InvoiceData> Function() aiFallback,
  }) async {
    final tempFiles = <File>[];
    try {
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().microsecondsSinceEpoch;
      for (var i = 0; i < images.length; i++) {
        final bytes = images[i];
        final isPng = bytes.length >= 8 &&
            bytes[0] == 0x89 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x4E &&
            bytes[3] == 0x47;
        final ext = isPng ? 'png' : 'jpg';
        final f = File('${dir.path}/ips_scan_${stamp}_$i.$ext');
        await f.writeAsBytes(bytes, flush: true);
        tempFiles.add(f);
      }

      // Korak 1: Postojeći NBS IPS QR kod (<100ms, 100% tačnost)
      for (var i = 0; i < tempFiles.length; i++) {
        final qrData =
            await _qrScannerService.tryExtractIpsFromFile(tempFiles[i].path);
        if (qrData != null) return (qrData, ExtractionSource.qr, images[i]);
      }

      // Korak 2: Lokalni OCR sa Modulo-97 proverom
      for (var i = 0; i < tempFiles.length; i++) {
        final ocrData =
            await _localOcrService.tryExtractFromFile(tempFiles[i].path);
        if (ocrData != null) return (ocrData, ExtractionSource.ocr, images[i]);
      }
    } catch (e) {
      debugPrint('Local extraction skipped: $e');
    } finally {
      for (final f in tempFiles) {
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }

    // Korak 3: Fallback na Gemini AI
    final aiData = await aiFallback();
    return (aiData, ExtractionSource.ai, images.first);
  }

  // --- Akcije ---

  void _showToast(String message) {
    setState(() => _toastText = message);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _toastText = null);
    });
  }

  Future<void> _handleCopy(String text) async {
    final ok = await share_utils.copyToClipboard(text);
    if (ok && mounted) {
      setState(() => _copied = true);
      _copiedTimer?.cancel();
      _copiedTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
      _showToast(_t.copied);
    }
  }

  Future<void> _handleShare() async {
    final data = _invoiceData;
    if (data == null) return;
    await share_utils.shareQrCode(
      generateIpsString(data, allowOpenAmount: _resultMode == ResultMode.ownCode),
      _t.title,
      _t.shareDesc,
    );
  }

  void _reset() {
    _stopCameraQueued();
    // Napuštanje own-code toka (iz bilo kog stanja) vraća na listu sačuvanih
    // kodova, ne na idle — payInvoice tok se i dalje vraća na idle.
    final wasOwnCode = _resultMode == ResultMode.ownCode;
    final fromResult = _state == AppState.result;
    setState(() {
      _image = null;
      _invoiceData = null;
      _error = null;
      _editingSavedId = null;
      _editingTitle = '';
      _extractionSource = null;
      _resultMode = ResultMode.payInvoice;
      _state = AppState.idle;
    });
    if (_reviewPending && fromResult && !wasOwnCode) {
      _reviewPending = false;
      // Sačekaj da AnimatedSwitcher (360ms) završi prelaz na idle.
      Future.delayed(const Duration(milliseconds: 420), _showReviewPrompt);
    }
  }

  /// Nudi ocenjivanje aplikacije: prvo naš sheet, pa tek na potvrdu native
  /// prompt prodavnice — da se Play-ov ograničen broj prompt-a ne troši
  /// na korisnike koji ionako ne bi ocenili.
  Future<void> _showReviewPrompt() async {
    if (!mounted) return;
    // Flag se upisuje pre prikaza — pitamo tačno jednom, bez obzira na izbor.
    await _reviewService.markPrompted();
    if (!mounted) return;
    final wantsToRate = await showReviewSheet(context, _t);
    if (wantsToRate != true) return;
    final review = InAppReview.instance;
    if (await review.isAvailable()) {
      await review.requestReview();
    }
  }

  // --- Sačuvani IPS kodovi ("IPS pokaži") ---

  Future<void> _loadSavedCodes() async {
    final codes = await _savedCodesService.loadAll();
    if (!mounted) return;
    setState(() => _savedCodes = codes);
  }

  void _openSavedList() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => SavedCodesScreen(
          t: _t,
          codes: _savedCodes,
          onUpdate: (updated) async {
            await _savedCodesService.update(
              updated.id,
              updated.data,
              title: updated.title,
            );
            await _loadSavedCodes();
          },
          onAddCode: (newCode) async {
            await _savedCodesService.add(newCode);
            await _loadSavedCodes();
          },
          onDelete: _deleteSavedCode,
          onTogglePin: (id) async {
            await _savedCodesService.togglePin(id);
            await _loadSavedCodes();
          },
          onTogglePaid: (id) async {
            await _savedCodesService.togglePaidThisMonth(id);
            await _loadSavedCodes();
          },
          onAmountUpdated: (id, amt) async {
            await _savedCodesService.updateAmount(id, amt);
            await _loadSavedCodes();
          },
          onCopy: _handleCopy,
          onShare: _shareSavedCode,
          onStartCamera: _startOwnCodeCamera,
          onStartGallery: () => _startOwnCodeGallery(),
          onExport: _exportSavedCodes,
          onImport: _importSavedCodes,
        ),
      ),
    );
    if (mounted) {
      await _loadSavedCodes();
    }
  }

  void _startInvoiceCamera() {
    _resultMode = ResultMode.payInvoice;
    _editingSavedId = null;
    _startCamera();
  }

  Future<void> _startInvoiceGallery() {
    _resultMode = ResultMode.payInvoice;
    _editingSavedId = null;
    return _pickFromGallery();
  }

  void _startOwnCodeCamera() {
    _resultMode = ResultMode.ownCode;
    _editingSavedId = null;
    _startCamera();
  }

  Future<void> _startOwnCodeGallery() {
    _resultMode = ResultMode.ownCode;
    _editingSavedId = null;
    return _pickFromGallery();
  }

  Future<void> _saveCurrentCode() async {
    final data = _invoiceData;
    if (data == null) return;
    final editingId = _editingSavedId;
    if (editingId == null) {
      await _savedCodesService.add(SavedCode(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        createdAt: DateTime.now(),
        title: _editingTitle,
        kind: SavedCodeKind.ownAccount,
        data: data.copyWith(),
      ));
    } else {
      await _savedCodesService.update(
        editingId,
        data.copyWith(),
        title: _editingTitle,
      );
    }
    await _loadSavedCodes();
    if (!mounted) return;
    _reset();
  }

  // Čuvanje skeniranog (payInvoice) računa među sačuvane kodove (šablone).
  Future<void> _saveScannedInvoice() async {
    final data = _invoiceData;
    if (data == null) return;

    // Provera duplikata: ako šablon sa istim računom i pozivom već postoji, ponudi ažuriranje
    final existing = await _savedCodesService.findDuplicate(
      accountNumber: data.accountNumber,
      referenceNumber: data.referenceNumber,
      recipientName: data.recipientName,
    );
    if (existing != null && mounted) {
      final shouldUpdate = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_t.duplicateFoundTitle),
          content: Text(_t.duplicateFoundMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(_t.saveNew),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.emerald600),
              child: Text(_t.updateExisting),
            ),
          ],
        ),
      );
      if (shouldUpdate == true) {
        await _savedCodesService.updateAmount(existing.id, data.amount);
        await _loadSavedCodes();
        if (!mounted) return;
        _showToast(_t.savedToast);
        return;
      }
    }

    await _savedCodesService.add(SavedCode(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      kind: SavedCodeKind.billTemplate,
      title: _editingTitle.isNotEmpty ? _editingTitle : data.recipientName,
      data: data.copyWith(),
    ));
    await _loadSavedCodes();
    if (!mounted) return;
    _showToast(_t.savedToast);
  }

  // --- Izvoz/uvoz sačuvanih kodova (nema sopstvenog servera za sync) ---

  Future<void> _exportSavedCodes() async {
    final json = await _savedCodesService.exportJson();
    if (!mounted) return;
    final now = DateTime.now();
    final stamp = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    await share_utils.shareJsonBackup(
      json,
      'invoice2ips-kodovi-$stamp.json',
      _t.exportCodes,
      _t.exportShareDesc,
    );
  }

  Future<void> _importSavedCodes() async {
    final raw = await backup_utils.pickJsonBackupContent();
    if (raw == null || !mounted) return;
    try {
      final count = await _savedCodesService.importMerge(raw);
      await _loadSavedCodes();
      if (!mounted) return;
      _showToast('${_t.importSuccessPrefix}$count');
    } catch (e) {
      debugPrint('Import error: $e');
      if (!mounted) return;
      _showToast(_t.importErrorToast);
    }
  }

  Future<void> _deleteSavedCode(String id) async {
    await _savedCodesService.delete(id);
    await _loadSavedCodes();
  }

  Future<void> _deleteCurrentAndReturn() async {
    final id = _editingSavedId;
    if (id == null) return;
    await _deleteSavedCode(id);
    if (!mounted) return;
    _reset();
  }

  void _showImagePreview() {
    final image = _image;
    if (image == null) return;
    showDialog(
      context: context,
      barrierColor: AppColors.stone900.withValues(alpha: 0.82),
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: () {},
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.memory(image, fit: BoxFit.contain),
                  ),
                ),
                Positioned(
                  top: -8,
                  right: -8,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black38, blurRadius: 12),
                        ],
                      ),
                      child: const Icon(
                        LucideIcons.x,
                        size: 20,
                        color: AppColors.stone600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final toastMessage = _toastText;
    return PopScope(
      canPop: _state == AppState.idle,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _reset();
      },
      child: Scaffold(
        backgroundColor: AppColors.stone50,
        body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448),
            child: Container(
              color: AppColors.stone50,
              child: Stack(
                children: [
                  Column(
                    children: [
                      // Header — sakriven tokom kamere (full-bleed prikaz)
                      if (_state != AppState.capturing) _buildHeader(t),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 360),
                          switchInCurve: const Cubic(0.22, 1, 0.36, 1),
                          switchOutCurve: Curves.easeOut,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.015),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: _buildBody(t),
                        ),
                      ),
                    ],
                  ),
                  // Toast za kopiranje/čuvanje
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 24,
                    child: IgnorePointer(
                      child: AnimatedSlide(
                        offset: toastMessage != null
                            ? Offset.zero
                            : const Offset(0, 0.4),
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        child: AnimatedOpacity(
                          opacity: toastMessage != null ? 1 : 0,
                          duration: const Duration(milliseconds: 250),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.stone900,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black45,
                                  blurRadius: 24,
                                  offset: Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  LucideIcons.circleCheck,
                                  size: 18,
                                  color: AppColors.emerald400,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    toastMessage ?? '',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

  Widget _buildHeader(Translations t) {
    final topInset = MediaQuery.of(context).padding.top;
    final isIdle = _state == AppState.idle;
    final isResult = _state == AppState.result;
    final image = _image;
    const wordmark = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Invoice',
            style: TextStyle(color: AppColors.emerald600),
          ),
          TextSpan(
            text: '2IPS',
            style: TextStyle(color: AppColors.stone900),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
    );

    if (isIdle) {
      return Padding(
        padding: EdgeInsets.fromLTRB(20, topInset + 10, 8, 8),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.emerald600,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(LucideIcons.qrCode, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 10),
            const Expanded(child: wordmark),
            _HeaderIconButton(
              icon: LucideIcons.ellipsisVertical,
              tooltip: t.menu,
              onTap: _openMenu,
            ),
          ],
        ),
      );
    }

    // Van početnog ekrana: nazad levo, naslov ekrana i (na rezultatu)
    // dugme za pregled fotografije računa desno.
    final title = !isResult
        ? null
        : _resultMode == ResultMode.ownCode
            ? t.ownCodeBannerTitle
            : t.resultReady;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, topInset + 10, 16, 6),
      child: Row(
        children: [
          _HeaderIconButton(
            icon: LucideIcons.arrowLeft,
            tooltip: t.back,
            color: AppColors.stone800,
            onTap: _reset,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: title == null
                ? const Align(alignment: Alignment.centerLeft, child: wordmark)
                : Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.stone900,
                    ),
                  ),
          ),
          if (isResult && image != null)
            OutlinedButton.icon(
              onPressed: _showImagePreview,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.stone700,
                backgroundColor: Colors.white,
                side: const BorderSide(color: AppColors.stone200),
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontFamily: kFontFamily,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              icon: const Icon(LucideIcons.image, size: 15, color: AppColors.stone600),
              label: Text(t.viewInvoice),
            ),
        ],
      ),
    );
  }

  void _openMenu() {
    showAppMenuSheet(
      context,
      t: _t,
      language: _lang,
      onLanguageChanged: (l) => setState(() => _lang = l),
      onInfo: () => showInfoSheet(context, _t),
      onExport: _exportSavedCodes,
      onImport: _importSavedCodes,
      onRate: _rateApp,
    );
  }

  /// Ocenjivanje iz menija: Android otvara stranicu u Play prodavnici, iOS
  /// sistemski prompt (App Store stranica zahteva appStoreId).
  Future<void> _rateApp() async {
    final review = InAppReview.instance;
    if (Platform.isAndroid) {
      await review.openStoreListing();
    } else if (await review.isAvailable()) {
      await review.requestReview();
    }
  }

  /// Brzi QR prikaz sačuvanog koda sa početnog ekrana — isti sheet kao na
  /// ekranu sačuvanih kodova.
  void _openSavedCode(SavedCode code) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => QuickQrSheet(
        t: _t,
        code: code,
        onCopy: _handleCopy,
        onShare: () => _shareSavedCode(code),
        // Lokalna izmena objekta da sheet odmah prikaže novo stanje.
        onTogglePin: () async {
          code.isPinned = !code.isPinned;
          await _savedCodesService.togglePin(code.id);
          await _loadSavedCodes();
        },
        onTogglePaid: () async {
          code.lastPaidAt = code.isPaidThisMonth ? null : DateTime.now();
          await _savedCodesService.togglePaidThisMonth(code.id);
          await _loadSavedCodes();
        },
        onAmountUpdated: (amt) async {
          code.data.amount = amt;
          await _savedCodesService.updateAmount(code.id, amt);
          await _loadSavedCodes();
        },
        onEditDetails: () {
          // QuickQrSheet se sam zatvara pre onEditDetails poziva.
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EditSavedCodeScreen(
                t: _t,
                code: code,
                isEditingExisting: true,
                onSave: (updated) async {
                  await _savedCodesService.update(
                    updated.id,
                    updated.data,
                    title: updated.title,
                  );
                  await _loadSavedCodes();
                },
                onDelete: (id) => _deleteSavedCode(id),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _shareSavedCode(SavedCode code) {
    return share_utils.shareQrCode(
      generateIpsString(
        code.data,
        allowOpenAmount: code.kind == SavedCodeKind.ownAccount,
      ),
      _t.title,
      _t.shareDesc,
    );
  }

  Widget _buildBody(Translations t) {
    switch (_state) {
      case AppState.idle:
        return IdleView(
          key: const ValueKey('idle'),
          t: t,
          onOpenCamera: _startInvoiceCamera,
          onPickGallery: _startInvoiceGallery,
          onPickPdf: _pickPdf,
          onPasteClipboard: _pasteFromClipboard,
          savedCodes: _savedCodes,
          onOpenSavedList: _openSavedList,
          onOpenSavedCode: _openSavedCode,
        );
      case AppState.capturing:
        return CameraView(
          key: const ValueKey('capturing'),
          t: t,
          controller: _cameraController,
          cameraReady: _cameraReady,
          resolution: _resolution,
          torchOn: _torchOn,
          hasTorch: _hasTorch,
          onBack: _reset,
          onCapture: _capturePhoto,
          onToggleTorch: _toggleTorch,
          onSelectResolution: (res) => _startCamera(res),
        );
      case AppState.processing:
        return ProcessingView(
          key: const ValueKey('processing'),
          t: t,
          image: _image,
        );
      case AppState.result:
        return ResultView(
          key: const ValueKey('result'),
          t: t,
          data: _invoiceData!,
          copied: _copied,
          extractionSource: _extractionSource,
          mode: _resultMode,
          isEditingExisting: _editingSavedId != null,
          codeTitle: _editingTitle,
          onTitleChanged: (val) => setState(() => _editingTitle = val),
          onSave: _resultMode == ResultMode.ownCode ? _saveCurrentCode : null,
          onDelete: _editingSavedId != null ? _deleteCurrentAndReturn : null,
          onSaveScanned:
              _resultMode == ResultMode.payInvoice ? _saveScannedInvoice : null,
          onChanged: () => setState(() {}),
          onCopy: _handleCopy,
          onShare: _handleShare,
          onReset: _reset,
        );
      case AppState.error:
        return ErrorView(
          key: const ValueKey('error'),
          t: t,
          message: _error,
          onRetry: _reset,
        );
      case AppState.savedList:
        return const SizedBox.shrink();
    }
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.color = AppColors.stone600,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 22, color: color),
        ),
      ),
    );
    if (tooltip != null) return Tooltip(message: tooltip!, child: button);
    return button;
  }
}
