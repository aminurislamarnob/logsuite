import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';

enum ScanMode { receipt, prescription }

/// What the OCR pass managed to pull out of the image.
@immutable
class ScanResult {
  final String rawText;
  final String? imagePath;

  // Receipt fields
  final double? amount;
  final String? merchant;

  // Prescription fields
  final String? medicineName;
  final String? dosage;
  final int? timesPerDay;
  final int? durationDays;

  const ScanResult({
    required this.rawText,
    this.imagePath,
    this.amount,
    this.merchant,
    this.medicineName,
    this.dosage,
    this.timesPerDay,
    this.durationDays,
  });
}

/// On-device OCR over a captured photo, using ML Kit.
class CameraScanScreen extends StatefulWidget {
  final ScanMode mode;
  const CameraScanScreen({super.key, required this.mode});

  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen> {
  final _recognizer = TextRecognizer();
  final _picker = ImagePicker();

  late ScanMode _mode;
  bool _busy = false;
  String? _error;
  ScanResult? _result;
  String? _imagePath;

  @override
  void initState() {
    super.initState();
    _mode = widget.mode;
  }

  @override
  void dispose() {
    _recognizer.close();
    super.dispose();
  }

  void _setMode(ScanMode mode) {
    if (_mode == mode) return;
    AppHaptics.selection();
    setState(() {
      _mode = mode;
      if (_result != null) {
        final raw = _result!.rawText;
        _result = _mode == ScanMode.receipt
            ? ReceiptParser.parse(raw, _imagePath)
            : PrescriptionParser.parse(raw, _imagePath);
      }
    });
  }

  Future<void> _scan(ImageSource source) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final photo = await _picker.pickImage(source: source, imageQuality: 90);
      if (photo == null) {
        setState(() => _busy = false);
        return;
      }
      _imagePath = photo.path;

      final recognized = await _recognizer.processImage(
        InputImage.fromFilePath(photo.path),
      );
      final text = recognized.text;

      if (text.trim().isEmpty) {
        setState(() {
          _busy = false;
          _error = 'No text found. Try a sharper, better-lit photo.';
        });
        return;
      }

      setState(() {
        _busy = false;
        _result = _mode == ScanMode.receipt
            ? ReceiptParser.parse(text, _imagePath)
            : PrescriptionParser.parse(text, _imagePath);
      });
    } on Exception catch (e) {
      setState(() {
        _busy = false;
        _error = 'Scan failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReceipt = _mode == ScanMode.receipt;

    return BrandScaffold(
      header: BrandTopBar(
        title: _result != null
            ? 'What we found'
            : (isReceipt ? 'Scan receipt' : 'Scan prescription'),
        leadingIcon: AppIcons.back,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          8,
          AppSpacing.gutter,
          24,
        ),
        child: _busy
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BrandSpinner(),
                    SizedBox(height: 16),
                    Text('Reading the image…'),
                  ],
                ),
              )
            : _result != null
            ? _buildResult(_result!, isReceipt)
            : _buildPrompt(isReceipt),
      ),
    );
  }

  Widget _buildModeTabs(BuildContext context, bool isReceipt) {
    final brand = context.brand;
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: ShapeDecoration(
        color: brand.well,
        shape: const StadiumBorder(),
      ),
      child: Row(
        children: [
          Expanded(
            child: BrandTappable(
              onPressed: () => _setMode(ScanMode.receipt),
              child: Container(
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: isReceipt ? brand.ink : Colors.transparent,
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  'Receipt',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isReceipt ? FontWeight.w700 : FontWeight.w600,
                    color: isReceipt ? brand.onInk : context.muted,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: BrandTappable(
              onPressed: () => _setMode(ScanMode.prescription),
              child: Container(
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: !isReceipt ? brand.ink : Colors.transparent,
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  'Prescription',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: !isReceipt ? FontWeight.w700 : FontWeight.w600,
                    color: !isReceipt ? brand.onInk : context.muted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrompt(bool isReceipt) {
    final theme = Theme.of(context);
    final brand = context.brand;
    return Column(
      children: [
        _buildModeTabs(context, isReceipt),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: brand.surface,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: AppShadows.card(theme.brightness),
                  ),
                  child: AppIcon(
                    isReceipt ? AppIcons.bills : AppIcons.prescription,
                    size: 36,
                    color: isReceipt
                        ? brand.expenseRoles.graphicOnTint
                        : brand.medicineRoles.graphicOnTint,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  isReceipt
                      ? 'Point at a receipt to pull out the total'
                      : 'Point at a prescription to pre-fill the schedule',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: context.muted),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: brand.danger),
                  ),
                ],
                const SizedBox(height: 28),
                BrandButton(
                  label: 'Take a photo',
                  icon: AppIcons.camera,
                  expand: false,
                  onPressed: () => _scan(ImageSource.camera),
                ),
                const SizedBox(height: 10),
                BrandButton(
                  label: 'Choose from gallery',
                  icon: AppIcons.gallery,
                  kind: BrandButtonKind.outline,
                  expand: false,
                  onPressed: () => _scan(ImageSource.gallery),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResult(ScanResult r, bool isReceipt) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final rows = isReceipt
        ? <(String, String?, bool)>[
            ('Merchant', r.merchant, false),
            ('Amount', r.amount?.toStringAsFixed(2), true),
          ]
        : <(String, String?, bool)>[
            ('Medicine', r.medicineName, false),
            ('Dosage', r.dosage, true),
            ('Times per day', r.timesPerDay?.toString(), false),
            (
              'Duration',
              r.durationDays == null ? null : '${r.durationDays} days',
              false,
            ),
          ];

    final fieldsRead = rows.where((row) => row.$2 != null).length;
    final lineCount = r.rawText
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildModeTabs(context, isReceipt),
        const SizedBox(height: 14),
        Expanded(
          child: ListView(
            children: [
              // Scanned image banner (39-scan-result.html)
              Container(
                height: 184,
                decoration: BoxDecoration(
                  color: brand.heroSurface,
                  borderRadius: BorderRadius.circular(24),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_imagePath != null)
                      Image.file(File(_imagePath!), fit: BoxFit.cover),
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: brand.medicineRoles.onInk,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$fieldsRead ${fieldsRead == 1 ? 'field' : 'fields'} read',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Detected fields white card (39-scan-result.html)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: AppShadows.card(theme.brightness),
                ),
                child: Column(
                  children: [
                    for (final (i, row) in rows.indexed)
                      Container(
                        height: 60,
                        decoration: BoxDecoration(
                          border: i < rows.length - 1
                              ? Border(
                                  bottom: BorderSide(color: brand.hairline),
                                )
                              : null,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 96,
                              child: Text(
                                row.$1,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: context.muted,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                row.$2 ?? 'not detected',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: row.$3 ? 22 : 16,
                                  fontWeight: row.$3
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  letterSpacing: row.$3 ? -0.5 : 0,
                                  color: row.$2 == null
                                      ? context.muted
                                      : brand.ink,
                                ),
                              ),
                            ),
                            AppIcon(
                              AppIcons.edit,
                              size: 16,
                              color: brand.subtle,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Raw text collapsible pill
              Container(
                decoration: BoxDecoration(
                  color: brand.well,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: BrandAccordion(
                  title: 'Raw text · $lineCount lines',
                  leading: AppIcons.notes,
                  child: Text(
                    r.rawText,
                    style: TextStyle(fontSize: 12, color: brand.ink),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            BrandButton(
              label: 'Rescan',
              icon: AppIcons.replay,
              kind: BrandButtonKind.outline,
              expand: false,
              onPressed: () => setState(() {
                _result = null;
                _imagePath = null;
              }),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: BrandButton(
                label: 'Use these details',
                onPressed: () => Navigator.pop(context, r),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Extracts a total and merchant name from receipt OCR text.
class ReceiptParser {
  const ReceiptParser._();

  static ScanResult parse(String text, String? imagePath) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    double? amount;

    // Prefer a line that explicitly names the total.
    for (final line in lines.reversed) {
      if (!RegExp(
        r'\b(grand\s+total|total|amount|due|payable)\b',
        caseSensitive: false,
      ).hasMatch(line)) {
        continue;
      }
      final value = _lastNumber(line);
      if (value != null) {
        amount = value;
        break;
      }
    }

    // Otherwise fall back to the largest number on the receipt, which is
    // almost always the total.
    amount ??= lines
        .map(_lastNumber)
        .whereType<double>()
        .fold<double?>(null, (max, v) => max == null || v > max ? v : max);

    // The merchant is conventionally the first substantial line.
    final merchant = lines
        .take(4)
        .where((l) => l.length > 3 && !RegExp(r'^\d').hasMatch(l))
        .firstOrNull;

    return ScanResult(
      rawText: text,
      imagePath: imagePath,
      amount: amount,
      merchant: merchant,
    );
  }

  static double? _lastNumber(String line) {
    final matches = RegExp(
      r'(\d[\d,]*(?:\.\d{1,2})?)',
    ).allMatches(line).toList();
    if (matches.isEmpty) return null;
    return double.tryParse(matches.last.group(1)!.replaceAll(',', ''));
  }
}

/// Extracts medicine name, dose and course length from prescription OCR text.
class PrescriptionParser {
  const PrescriptionParser._();

  static ScanResult parse(String text, String? imagePath) {
    final lower = text.toLowerCase();

    // "500mg", "5 ml", "10 mcg"
    final dosage = RegExp(
      r'(\d+(?:\.\d+)?)\s*(mg|ml|mcg|g|iu)\b',
      caseSensitive: false,
    ).firstMatch(text)?.group(0);

    // A medicine name usually sits immediately before its strength.
    String? name;
    final nameMatch = RegExp(
      r'([A-Z][A-Za-z\-]{2,})\s+\d+(?:\.\d+)?\s*(?:mg|ml|mcg|g|iu)\b',
    ).firstMatch(text);
    if (nameMatch != null) {
      name = nameMatch.group(1);
    } else {
      // Fall back to the first capitalised word after an Rx marker.
      final rx = RegExp(
        r'(?:rx|tab|cap|syp)[.:\s]+([A-Za-z][A-Za-z\-]{2,})',
        caseSensitive: false,
      ).firstMatch(text);
      name = rx?.group(1);
    }

    // Frequency: "twice daily", "3 times a day", or the 1+0+1 convention.
    int? timesPerDay;
    if (RegExp(r'\bonce\b').hasMatch(lower)) timesPerDay = 1;
    if (RegExp(r'\btwice\b').hasMatch(lower)) timesPerDay = 2;
    if (RegExp(r'\b(thrice|three times)\b').hasMatch(lower)) timesPerDay = 3;

    final timesMatch = RegExp(
      r'(\d+)\s*times?\s*(?:a|per)?\s*day',
    ).firstMatch(lower);
    if (timesMatch != null) {
      timesPerDay = int.tryParse(timesMatch.group(1)!);
    }

    // The South-Asian "1+0+1" dosing notation: count the non-zero slots.
    final plusNotation = RegExp(
      r'\b([01])\s*\+\s*([01])\s*\+\s*([01])\b',
    ).firstMatch(lower);
    if (plusNotation != null) {
      timesPerDay = [
        1,
        2,
        3,
      ].map((i) => plusNotation.group(i)).where((g) => g != '0').length;
    }

    // Course length: "for 7 days", "for 2 weeks".
    int? durationDays;
    final dayMatch = RegExp(r'for\s+(\d+)\s*day').firstMatch(lower);
    final weekMatch = RegExp(r'for\s+(\d+)\s*week').firstMatch(lower);
    if (dayMatch != null) {
      durationDays = int.tryParse(dayMatch.group(1)!);
    } else if (weekMatch != null) {
      final weeks = int.tryParse(weekMatch.group(1)!);
      durationDays = weeks == null ? null : weeks * 7;
    }

    return ScanResult(
      rawText: text,
      imagePath: imagePath,
      medicineName: name,
      dosage: dosage,
      timesPerDay: timesPerDay,
      durationDays: durationDays,
    );
  }
}
