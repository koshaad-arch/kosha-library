import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/book_lookup.dart';
import '../services/library_store.dart';

/// Opens the camera and returns the first ISBN barcode it sees.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;
  String _hint = 'Point at the barcode on the back cover';

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final raw = code.rawValue ?? '';
      if (BookLookup.looksLikeIsbn(raw)) {
        _done = true;
        Navigator.pop(context, LibraryStore.normIsbn(raw));
        return;
      }
    }
    setState(() => _hint = 'That barcode isn’t an ISBN — look for the one starting 978 or 979');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final boxW = size.width * 0.78;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan ISBN', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            tooltip: 'Torch',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          Center(
            child: Container(
              width: boxW,
              height: boxW * 0.5,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFF0AC2E), width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(14)),
              child: Text(_hint, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}
