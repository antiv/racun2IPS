import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../i18n/translations.dart';
import '../models/invoice_data.dart';
import '../models/saved_code.dart';
import '../services/gemini_service.dart';
import '../services/saved_codes_service.dart';
import '../services/shared_image.dart';
import '../theme.dart';
import '../utils/backup.dart' as backup_utils;
import '../utils/ips.dart';
import '../utils/share.dart' as share_utils;
import '../widgets/info_sheet.dart';
import 'camera_view.dart';
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
  List<SavedCode> _savedCodes = [];
  ResultMode _resultMode = ResultMode.payInvoice;
  // Not null samo kad je ResultView otvoren nad postojećim sačuvanim kodom.
  String? _editingSavedId;

  Translations get _t => translations[_lang]!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSavedCodes();
    _checkSharedImage();
    // Android WebView/intent događaji umeju da budu nepouzdani — original
    // koristi polling na 1.5s, zadržavamo isto ponašanje.
    _sharedPollTimer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => _checkSharedImage(),
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
      _checkSharedImage();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (_state == AppState.capturing) _reset();
    }
  }

  // --- Slika podeljena iz druge aplikacije (ACTION_SEND) ---

  Future<void> _checkSharedImage() async {
    if (_checkingShared || _state == AppState.processing) return;
    _checkingShared = true;
    try {
      final bytes = await getSharedImage();
      if (bytes != null && mounted) {
        _stopCameraQueued();
        // Slika deljena iz druge aplikacije je uvek "plati ovaj račun".
        _resultMode = ResultMode.payInvoice;
        _editingSavedId = null;
        setState(() => _image = bytes);
        await _processInvoice(bytes);
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

  // --- Obrada ---

  Future<void> _processInvoice(Uint8List imageBytes) async {
    setState(() {
      _state = AppState.processing;
      _error = null;
    });
    try {
      final data = await processInvoice(imageBytes);
      if (!mounted) return;
      setState(() {
        _invoiceData = data;
        _state = AppState.result;
      });
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
    setState(() {
      _image = null;
      _invoiceData = null;
      _error = null;
      _editingSavedId = null;
      _resultMode = ResultMode.payInvoice;
      _state = wasOwnCode ? AppState.savedList : AppState.idle;
    });
  }

  // --- Sačuvani IPS kodovi ("IPS pokaži") ---

  Future<void> _loadSavedCodes() async {
    final codes = await _savedCodesService.loadAll();
    if (!mounted) return;
    setState(() => _savedCodes = codes);
  }

  void _openSavedList() {
    setState(() => _state = AppState.savedList);
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

  void _startManualEntry() {
    setState(() {
      _resultMode = ResultMode.ownCode;
      _editingSavedId = null;
      _image = null;
      _invoiceData = InvoiceData();
      _state = AppState.result;
    });
  }

  void _openSavedCode(SavedCode saved) {
    setState(() {
      _resultMode = ResultMode.ownCode;
      _editingSavedId = saved.id;
      _image = null;
      _invoiceData = saved.data.copyWith();
      _state = AppState.result;
    });
  }

  Future<void> _saveCurrentCode() async {
    final data = _invoiceData;
    if (data == null) return;
    final editingId = _editingSavedId;
    if (editingId == null) {
      await _savedCodesService.add(SavedCode(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        createdAt: DateTime.now(),
        data: data.copyWith(),
      ));
    } else {
      await _savedCodesService.update(editingId, data.copyWith());
    }
    await _loadSavedCodes();
    if (!mounted) return;
    _reset();
  }

  // Čuvanje skeniranog (payInvoice) računa među sačuvane kodove — za razliku
  // od _saveCurrentCode (ownCode), ostaje na ResultView umesto da resetuje,
  // jer korisnik možda još želi da podeli/kopira ili skenira sledeći.
  Future<void> _saveScannedInvoice() async {
    final data = _invoiceData;
    if (data == null) return;
    await _savedCodesService.add(SavedCode(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
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

  void _showAddOwnCodeSheet() {
    final t = _t;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
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
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(t.addViaCamera),
              onTap: () {
                Navigator.of(context).pop();
                _startOwnCodeCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: Text(t.addViaGallery),
              onTap: () {
                Navigator.of(context).pop();
                _startOwnCodeGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: Text(t.addViaManual),
              onTap: () {
                Navigator.of(context).pop();
                _startManualEntry();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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
                        Icons.close,
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
    return Scaffold(
      backgroundColor: AppColors.stone50,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448),
            child: Container(
              color: Colors.white,
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
                                  Icons.check_circle_outline,
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
    );
  }

  Widget _buildHeader(Translations t) {
    final topInset = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(18, topInset + 12, 18, 13),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.stone100)),
      ),
      child: Row(
        children: [
          // Levi deo: ikona + naziv
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x4D059669),
                  blurRadius: 15,
                  offset: Offset(0, 6),
                  spreadRadius: -4,
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset('assets/images/app-icon.png', fit: BoxFit.cover),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.34,
                      height: 1,
                    ),
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
                ),
                const SizedBox(height: 3),
                Text(
                  t.subtitle.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.76,
                    color: AppColors.stone400,
                  ),
                ),
              ],
            ),
          ),
          // Desni deo: info, jezik, sačuvani kodovi/nazad
          _HeaderIconButton(
            icon: Icons.info_outline,
            tooltip: t.infoTitle,
            onTap: () => showInfoSheet(context, t),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              color: AppColors.stone100,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                for (final l in Language.values)
                  GestureDetector(
                    onTap: () => setState(() => _lang = l),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _lang == l ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: _lang == l
                            ? const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 2,
                                  offset: Offset(0, 1),
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        l.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.42,
                          color: _lang == l
                              ? AppColors.stone800
                              : AppColors.stone400,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _state == AppState.idle
              ? _HeaderIconButton(
                  icon: Icons.qr_code_2,
                  tooltip: t.savedCodesTitle,
                  onTap: _openSavedList,
                )
              : _HeaderIconButton(icon: _headerSecondaryIcon, onTap: _reset),
        ],
      ),
    );
  }

  IconData get _headerSecondaryIcon {
    if (_state == AppState.savedList) return Icons.close;
    if (_resultMode == ResultMode.ownCode) return Icons.arrow_back;
    return Icons.refresh;
  }

  Widget _buildBody(Translations t) {
    switch (_state) {
      case AppState.idle:
        return IdleView(
          key: const ValueKey('idle'),
          t: t,
          onOpenCamera: _startInvoiceCamera,
          onPickGallery: _startInvoiceGallery,
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
          image: _image,
          mode: _resultMode,
          isEditingExisting: _editingSavedId != null,
          onSave: _resultMode == ResultMode.ownCode ? _saveCurrentCode : null,
          onDelete: _editingSavedId != null ? _deleteCurrentAndReturn : null,
          onSaveScanned:
              _resultMode == ResultMode.payInvoice ? _saveScannedInvoice : null,
          onChanged: () => setState(() {}),
          onCopy: _handleCopy,
          onShare: _handleShare,
          onReset: _reset,
          onViewImage: _showImagePreview,
        );
      case AppState.error:
        return ErrorView(
          key: const ValueKey('error'),
          t: t,
          message: _error,
          onRetry: _reset,
        );
      case AppState.savedList:
        return SavedCodesView(
          key: const ValueKey('savedList'),
          t: t,
          codes: _savedCodes,
          onOpen: _openSavedCode,
          onDelete: _deleteSavedCode,
          onAddPressed: _showAddOwnCodeSheet,
          onExport: _exportSavedCodes,
          onImport: _importSavedCodes,
        );
    }
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 20, color: AppColors.stone400),
        ),
      ),
    );
    if (tooltip != null) return Tooltip(message: tooltip!, child: button);
    return button;
  }
}
