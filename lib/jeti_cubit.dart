import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';

class JetiState {
  final bool isScanning;
  final bool isConnected;
  final double x;
  final double y;
  final double photometricY;
  final double cct;
  final DateTime? lastUpdate;
  final String statusMessage;

  const JetiState({
    this.isScanning = false,
    this.isConnected = false,
    this.x = 0.0,
    this.y = 0.0,
    this.photometricY = 0.0,
    this.cct = 0.0,
    this.lastUpdate,
    this.statusMessage = 'Disconnected',
  });

  // Calculate X and Z from xyY coordinates locally
  double get tristimulusX => y > 0 ? (x * photometricY) / y : 0;
  double get tristimulusZ => y > 0 ? ((1 - x - y) * photometricY) / y : 0;

  JetiState copyWith({
    bool? isScanning,
    bool? isConnected,
    double? x,
    double? y,
    double? photometricY,
    double? cct,
    DateTime? lastUpdate,
    String? statusMessage,
  }) {
    return JetiState(
      isScanning: isScanning ?? this.isScanning,
      isConnected: isConnected ?? this.isConnected,
      x: x ?? this.x,
      y: y ?? this.y,
      photometricY: photometricY ?? this.photometricY,
      cct: cct ?? this.cct,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}

class JetiCubit extends Cubit<JetiState> {
  final _classicBluetooth = FlutterClassicBluetooth();
  BtcConnection? _connection;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _inputSubscription;

  bool _isLooping = false;
  String _rxBuffer = "";

  JetiCubit() : super(const JetiState());

  Future<void> startScanning() async {
    emit(
      state.copyWith(
        isScanning: true,
        statusMessage: 'Checking permissions...',
      ),
    );

    final pStatus = await _classicBluetooth.checkPermissions();
    if (pStatus == BtcPermissionStatus.denied) {
      final reqStatus = await _classicBluetooth.requestPermissions();
      if (reqStatus != BtcPermissionStatus.granted) {
        emit(
          state.copyWith(
            isScanning: false,
            statusMessage: 'Permissions denied.',
          ),
        );
        return;
      }
    } else if (pStatus == BtcPermissionStatus.permanentlyDenied) {
      emit(
        state.copyWith(
          isScanning: false,
          statusMessage:
              'Permissions permanently denied. Please enable in Settings.',
        ),
      );
      await _classicBluetooth.openAppSettings();
      return;
    }

    if (await _classicBluetooth.isLocationServiceRequired() &&
        !await _classicBluetooth.isLocationServiceEnabled()) {
      emit(
        state.copyWith(
          isScanning: false,
          statusMessage: 'Please enable Location (GPS) to scan.',
        ),
      );
      await _classicBluetooth.openLocationSettings();
      return;
    }

    try {
      final pairedDevices = await _classicBluetooth.getPairedDevices();
      for (var device in pairedDevices) {
        if (device.displayName != null &&
            device.displayName!.contains("JETI S/N: 2500243")) {
          emit(
            state.copyWith(
              isScanning: false,
              statusMessage: 'Found in paired devices. Connecting...',
            ),
          );
          await _connectToDevice(device.address);
          return;
        }
      }

      emit(state.copyWith(statusMessage: 'Scanning for JETI...'));

      _scanSubscription = _classicBluetooth.discoveryResults.listen((
        device,
      ) async {
        if (device.displayName != null &&
            device.displayName!.contains("JETI S/N: 2500243")) {
          _scanSubscription?.cancel();

          try {
            await _classicBluetooth.stopDiscovery();
          } catch (_) {}

          emit(
            state.copyWith(
              isScanning: false,
              statusMessage: 'Device found. Connecting...',
            ),
          );
          await _connectToDevice(device.address);
        }
      });

      await _classicBluetooth.startDiscovery();
    } catch (e) {
      _scanSubscription?.cancel();
      emit(
        state.copyWith(
          isScanning: false,
          statusMessage: 'Operation failed: $e',
        ),
      );
    }
  }

  Future<void> _connectToDevice(String address) async {
    try {
      _connection = await _classicBluetooth.connect(address: address);
      emit(
        state.copyWith(
          isConnected: true,
          statusMessage: 'Port open. Handshaking...',
        ),
      );

      // Accumulate raw string characters into the buffer
      _inputSubscription = _connection!.input.listen((data) {
        // Using the optimized decode approach
        _rxBuffer += ascii.decode(data, allowInvalid: true);
      });

      await Future.delayed(const Duration(milliseconds: 500));

      // --- CALIBRATION SETUP ---
      emit(state.copyWith(statusMessage: 'Configuring calibration...'));

      // Set to 0 for automatic selection based on the attached diffuser
      await _sendCommand("*PARA:CALIBN 0");

      // Optional: Save to internal flash so it remembers this setting on next boot
      // await _sendCommand("*PARA:SAVE");

      // Clear out any ACK replies from the config commands before starting the loop
      await Future.delayed(const Duration(milliseconds: 200));
      _clearBuffer();
      // ----------------------------------

      // Launch the procedural loop
      _startProceduralLoop();
    } catch (e) {
      emit(
        state.copyWith(
          isConnected: false,
          statusMessage: 'Connection failed: $e',
        ),
      );
    }
  }

  Future<void> _sendCommand(String cmd) async {
    if (_connection != null) {
      debugPrint("TX: $cmd");
      await _connection!.output.writeString("$cmd\r");
      await _connection!.output.allSent;
    }
  }

  // Equivalent to ser.reset_input_buffer()
  void _clearBuffer() {
    _rxBuffer = "";
  }

  Future<String> _readUntilCR() async {
    int timeout = 50;
    while (timeout > 0 && _isLooping) {
      int crIndex = _rxBuffer.indexOf('\r');
      if (crIndex != -1) {
        // Extract everything up to the <CR>
        String line = _rxBuffer.substring(0, crIndex);
        // Remove the extracted line and the <CR> from the buffer
        _rxBuffer = _rxBuffer.substring(crIndex + 1);

        // Strip control characters (ACK, BELL)
        return line.replaceAll(RegExp(r'[\x00-\x1F]+'), ' ').trim();
      }
      await Future.delayed(const Duration(milliseconds: 100));
      timeout--;
    }
    return "";
  }

  Future<void> _waitForMeasurementComplete() async {
    int timeout = 50; // 5.0 seconds maximum wait
    while (timeout > 0 && _isLooping) {
      // 0x07 is the ASCII BELL character emitted by the specbos
      if (_rxBuffer.contains(String.fromCharCode(0x07))) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 100));
      timeout--;
    }
  }

  Future<void> _startProceduralLoop() async {
    _isLooping = true;

    while (_isLooping && _connection != null) {
      try {
        // Dark Measurement
        emit(state.copyWith(statusMessage: 'Taking dark measurement...'));
        await _sendCommand("*MEAS:DARK 100 1 0");
        await _waitForMeasurementComplete(); // Wait for mechanical shutter
        _clearBuffer();

        if (!_isLooping) break;

        // Light Measurement
        emit(state.copyWith(statusMessage: 'Taking light measurement...'));
        await _sendCommand("*MEAS:LIGHT 100 1 0");
        await _waitForMeasurementComplete();
        _clearBuffer();

        if (!_isLooping) break;

        // Query Chromaticity (x, y)
        emit(state.copyWith(statusMessage: 'Querying Chromaticity...'));
        await _sendCommand("*CALC:CHROMXY");
        final chromResponse = await _readUntilCR();

        double newX = state.x;
        double newY = state.y;
        if (chromResponse.isNotEmpty) {
          final parts = chromResponse.split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            newX = double.tryParse(parts[0]) ?? state.x;
            newY = double.tryParse(parts[1]) ?? state.y;
          }
        }

        if (!_isLooping) break;

        // Query Photometry (Y)
        _clearBuffer();
        emit(state.copyWith(statusMessage: 'Querying Photometry...'));
        await _sendCommand("*CALC:PHOTO");
        final photoResponse = await _readUntilCR();
        double newPhotoY = double.tryParse(photoResponse) ?? state.photometricY;

        if (!_isLooping) break;

        // Query CCT
        _clearBuffer();
        emit(state.copyWith(statusMessage: 'Querying CCT...'));
        await _sendCommand("*CALC:CCT");
        final cctResponse = await _readUntilCR();
        double newCct = double.tryParse(cctResponse) ?? state.cct;

        // Push parsed values to the UI
        emit(
          state.copyWith(
            x: newX,
            y: newY,
            photometricY: newPhotoY,
            cct: newCct,
            lastUpdate: DateTime.now(),
            statusMessage: 'Looping...',
          ),
        );
      } catch (e) {
        debugPrint("Loop error: $e");
        emit(state.copyWith(statusMessage: 'Loop Error: $e'));
        await Future.delayed(const Duration(seconds: 2)); // Backoff on error
      }
    }
  }

  void disconnect() {
    _isLooping = false;
    _scanSubscription?.cancel();
    _inputSubscription?.cancel();
    _connection?.close();
    emit(
      state.copyWith(
        isConnected: false,
        isScanning: false,
        statusMessage: 'Disconnected',
      ),
    );
  }

  @override
  Future<void> close() {
    disconnect();
    return super.close();
  }
}
