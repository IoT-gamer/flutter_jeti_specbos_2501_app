import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'dart:math' as math;

import 'jeti_cubit.dart';
import 'chromaticity_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  Color _xyzToColor(double X, double Y, double Z) {
    double rLin = (3.2404542 * X) - (1.5371385 * Y) - (0.4985314 * Z);
    double gLin = (-0.9692660 * X) + (1.8760108 * Y) + (0.0415560 * Z);
    double bLin = (0.0556434 * X) - (0.2040259 * Y) + (1.0572252 * Z);

    final double maxLin = math.max(rLin, math.max(gLin, bLin));
    if (maxLin > 0) {
      rLin /= maxLin;
      gLin /= maxLin;
      bLin /= maxLin;
    }

    double gamma(double c) =>
        c <= 0.0031308 ? 12.92 * c : 1.055 * math.pow(c, 1.0 / 2.4) - 0.055;
    int clamp(double val) => (val.clamp(0.0, 1.0) * 255).round();

    return Color.fromARGB(
      255,
      clamp(gamma(rLin)),
      clamp(gamma(gLin)),
      clamp(gamma(bLin)),
    );
  }

  String _getFormattedTime(DateTime? time) {
    if (time == null) return "Waiting for JETI measurement data...";
    return "Last updated: ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<JetiCubit, JetiState>(
      builder: (context, state) {
        final previewColor = _xyzToColor(
          state.tristimulusX,
          state.photometricY,
          state.tristimulusZ,
        );

        return Scaffold(
          appBar: AppBar(
            title: const Text('JETI specbos 2501 Monitor'),
            actions: [
              IconButton(
                icon: const Icon(Icons.analytics_outlined),
                tooltip: 'Chromaticity Plot',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BlocProvider.value(
                        value: context.read<JetiCubit>(),
                        child: const ChromaticityScreen(),
                      ),
                    ),
                  );
                },
              ),
              IconButton(
                icon: Icon(
                  state.isScanning || state.isConnected
                      ? Icons.stop_circle
                      : Icons.play_circle_fill,
                ),
                color: state.isScanning || state.isConnected
                    ? Colors.redAccent
                    : Colors.tealAccent,
                onPressed: () {
                  if (state.isScanning || state.isConnected) {
                    context.read<JetiCubit>().disconnect();
                  } else {
                    context.read<JetiCubit>().startScanning();
                  }
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.bluetooth,
                      size: 18,
                      color: state.isConnected
                          ? Colors.tealAccent
                          : Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      state.statusMessage,
                      style: TextStyle(
                        color: state.isConnected
                            ? Colors.tealAccent
                            : Colors.grey,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F222A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: previewColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24, width: 2),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'CIE 1931 Chromaticity',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'x: ${state.x.toStringAsFixed(4)}  y: ${state.y.toStringAsFixed(4)}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _getFormattedTime(state.lastUpdate),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    _buildChannelCard(
                      'X (Tristimulus)',
                      state.tristimulusX,
                      Colors.redAccent,
                    ),
                    const SizedBox(width: 12),
                    _buildChannelCard(
                      'Y (Photometric)',
                      state.photometricY,
                      Colors.greenAccent,
                    ),
                    const SizedBox(width: 12),
                    _buildChannelCard(
                      'Z (Tristimulus)',
                      state.tristimulusZ,
                      Colors.blueAccent,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Container(
                  width: double.infinity,
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
                        style: TextStyle(color: Colors.grey, fontSize: 14),
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
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChannelCard(String label, double value, Color accentColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1F222A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accentColor.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: accentColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value.toStringAsExponential(2),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ), // Handles scientific notation cleanly
          ],
        ),
      ),
    );
  }
}
