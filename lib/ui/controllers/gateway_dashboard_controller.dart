import 'package:flutter/material.dart';
import '../../models/activity_detection_model.dart';
import '../../models/log_entry_model.dart';
import '../../models/step_data_model.dart';
import '../../services/ble/ble_connection_manager.dart';

/// State and logic controller for the Gateway Dashboard.
/// Keeps presentation logic and state decoupled from the Widget tree.
class GatewayDashboardController extends ChangeNotifier {
  final List<LogEntry> _logs = [];
  final List<ActivityDetectionModel> _recentActivities = [];

  BleConnectionStatus _bleStatus = BleConnectionStatus.disconnected;
  bool _mqttConnected = false;
  StepDataModel? _latestStepData;
  int _mtu = 23;

  List<LogEntry> get logs => List.unmodifiable(_logs);
  List<ActivityDetectionModel> get recentActivities => List.unmodifiable(_recentActivities);
  BleConnectionStatus get bleStatus => _bleStatus;
  bool get mqttConnected => _mqttConnected;
  StepDataModel? get latestStepData => _latestStepData;
  int get mtu => _mtu;

  void setBleStatus(BleConnectionStatus status) {
    if (_bleStatus != status) {
      _bleStatus = status;
      notifyListeners();
    }
  }

  void setMqttConnected(bool connected) {
    if (_mqttConnected != connected) {
      _mqttConnected = connected;
      notifyListeners();
    }
  }

  void setMtu(int mtu) {
    if (_mtu != mtu) {
      _mtu = mtu;
      notifyListeners();
    }
  }

  void setLatestStepData(StepDataModel stepData) {
    _latestStepData = stepData;
    notifyListeners();
  }

  void addLog(String source, String message, {Color? color, bool isError = false}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      tag: source,
      message: message,
      color: color ?? (isError ? Colors.red : Colors.grey),
    );
    _logs.insert(0, entry);
    if (_logs.length > 200) {
      _logs.removeLast();
    }
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  void addActivity(ActivityDetectionModel activity, {int maxItems = 20}) {
    _recentActivities.insert(0, activity);
    if (_recentActivities.length > maxItems) {
      _recentActivities.removeLast();
    }
    notifyListeners();
  }

  void clearActivities() {
    _recentActivities.clear();
    notifyListeners();
  }
}

