import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/config/app_config.dart';
import '../models/step_data_model.dart';
import '../services/auth/auth_service.dart';
import '../services/auth/token_storage_service.dart';
import '../services/local_storage/step_storage_service.dart';
import '../services/step_sync_service.dart';

/// Delegate coordinator responsible for managing net daily step calculations from the
/// hardware monotonic odometer, local SQLite storage persistence, and cloud synchronization.
class DashboardOdometerCoordinator {
  final String deviceId;
  final AuthService? authService;
  final StepStorageService storageService;
  late final StepSyncService syncService;
  final void Function(String tag, String message, {Color? color}) onLog;
  final VoidCallback onStepDataUpdated;

  StepDataModel? _latestStepData;
  bool _isDisposed = false;

  DashboardOdometerCoordinator({
    required this.deviceId,
    this.authService,
    StepStorageService? storageService,
    StepSyncService? syncService,
    required this.onLog,
    required this.onStepDataUpdated,
  }) : storageService = storageService ?? StepStorageService() {
    this.syncService = syncService ??
        StepSyncService(
          storageService: this.storageService,
          tokenStorage: TokenStorageService(),
          authService: authService,
          backendBaseUrl: AppConfig.backendBaseUrl,
          onLog: (msg, {bool isError = false}) {
            onLog('SYNC', msg, color: isError ? Colors.red : Colors.cyan);
          },
        );
  }

  StepDataModel? get latestStepData => _latestStepData;

  void initialize() {
    syncService.startPeriodicSync(deviceId: deviceId);
    unawaited(loadInitialDailySteps());
  }

  void setForegroundState(bool isForeground) {
    syncService.setForegroundState(isForeground);
  }

  void flushSteps() {
    unawaited(syncService.flushImmediateSync(deviceId: deviceId));
  }

  Future<void> loadInitialDailySteps() async {
    try {
      final now = DateTime.now();
      final localRecord = await storageService.getDailySteps(now);
      if (localRecord != null && !_isDisposed) {
        _latestStepData = StepDataModel(
          totalSteps: localRecord.totalSteps,
          walkSteps: localRecord.walkSteps,
          runSteps: localRecord.runSteps,
          stairsSteps: localRecord.stairsSteps,
          unclassifiedSteps: localRecord.unclassifiedSteps,
          cadenceSpm: 0,
          timestamp: now,
        );
        onStepDataUpdated();
      }

      final cloudSteps = await syncService.fetchTodaySteps(deviceId: deviceId);
      if (cloudSteps != null && !_isDisposed) {
        final currentTotal = _latestStepData?.totalSteps ?? 0;
        if (cloudSteps.totalSteps >= currentTotal) {
          _latestStepData = cloudSteps;
          onStepDataUpdated();
          await storageService.recordStepSnapshot(DateTime.now(), cloudSteps);
          final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
          await storageService.markDaysSynced([todayStr]);
        }
      }
    } catch (e) {
      onLog('SYNC', 'Erreur chargement initial des pas : $e', color: Colors.orange);
    }
  }

  Future<void> handleOdometerReading(StepDataModel stepData) async {
    try {
      final dailyRecord = await storageService.recordOdometerSnapshot(
        deviceId: deviceId,
        date: DateTime.now(),
        rawModel: stepData,
      );
      if (_isDisposed) return;
      _latestStepData = StepDataModel(
        totalSteps: dailyRecord.totalSteps,
        walkSteps: dailyRecord.walkSteps,
        runSteps: dailyRecord.runSteps,
        stairsSteps: dailyRecord.stairsSteps,
        unclassifiedSteps: dailyRecord.unclassifiedSteps,
        cadenceSpm: stepData.cadenceSpm,
        gctMs: stepData.gctMs,
        timestamp: stepData.timestamp,
      );
      onStepDataUpdated();
    } catch (e) {
      onLog('SYNC', 'Erreur enregistrement odomètre : $e', color: Colors.orange);
    }
  }

  void dispose() {
    _isDisposed = true;
    syncService.dispose();
    storageService.close();
  }
}
