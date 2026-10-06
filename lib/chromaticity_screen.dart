import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'jeti_cubit.dart';

class ChromaticityScreen extends StatefulWidget {
  const ChromaticityScreen({super.key});

  @override
  State<ChromaticityScreen> createState() => _ChromaticityScreenState();
}

class _ChromaticityScreenState extends State<ChromaticityScreen> {
  ui.Image? _backgroundPng;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGraphBackground();
  }

  Future<void> _loadGraphBackground() async {
    try {
      final ByteData data = await rootBundle.load(
        'assets/cie_1931_cropped.png',
      );
      final Uint8List bytes = data.buffer.asUint8List();
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();

      if (mounted) {
        setState(() {
          _backgroundPng = frame.image;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chromaticity Plot')),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.tealAccent),
            )
          : _backgroundPng == null
          ? const Center(child: Text('Failed to load background image.'))
          : BlocBuilder<JetiCubit, JetiState>(
              builder: (context, state) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F222A),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Correlated Color Temp (CCT)',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${state.cct.toInt()} K',
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'CIE 1931 xy Color Space',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF16181D),
                            border: Border.all(color: Colors.white24),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: CustomPaint(
                              painter: ImageChromaticityPainter(
                                chrX: state.x,
                                chrY: state.y,
                                backgroundPng: _backgroundPng!,
                              ),
                              child: Container(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class ImageChromaticityPainter extends CustomPainter {
  final double chrX;
  final double chrY;
  final ui.Image backgroundPng;

  ImageChromaticityPainter({
    required this.chrX,
    required this.chrY,
    required this.backgroundPng,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double maxX = 0.8;
    const double maxY = 0.9;

    final Rect srcRect = Rect.fromLTWH(
      0,
      0,
      backgroundPng.width.toDouble(),
      backgroundPng.height.toDouble(),
    );
    final Rect dstRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(backgroundPng, srcRect, dstRect, Paint());

    final double pointX = (chrX / maxX) * size.width;
    final double pointY = size.height - ((chrY / maxY) * size.height);

    canvas.drawCircle(
      Offset(pointX, pointY),
      12,
      Paint()
        ..color = Colors.black45
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(pointX, pointY),
      12,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    canvas.drawCircle(
      Offset(pointX, pointY),
      6,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant ImageChromaticityPainter oldDelegate) {
    return oldDelegate.chrX != chrX || oldDelegate.chrY != chrY;
  }
}
