import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/activity_detection_model.dart';
import '../models/detection_event.dart';
import 'event_history_service.dart';

/// Notifier managing pagination, filtering, and data lifecycle for Detection Events History.
class EventHistoryNotifier extends ChangeNotifier {
  final EventHistoryService _service;
  final String? deviceId;

  List<DetectionEvent> _events = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _errorMessage;
  int _currentPage = 1;
  String _selectedCategory = 'all';

  static const int pageSize = 20;

  EventHistoryNotifier({
    required EventHistoryService service,
    this.deviceId,
    List<ActivityDetectionModel>? liveActivities,
  }) : _service = service {
    if (liveActivities != null && liveActivities.isNotEmpty) {
      _events = liveActivities
          .map((a) => DetectionEvent.fromActivityDetection(a, deviceId: deviceId ?? 'HK-2'))
          .toList();
    }
  }

  List<DetectionEvent> get events => List.unmodifiable(_events);
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  bool get isEmpty => !_isLoading && _events.isEmpty;
  String? get errorMessage => _errorMessage;
  String get selectedCategory => _selectedCategory;
  int get currentPage => _currentPage;

  /// Initial load of detection events for the selected category.
  Future<void> loadInitial() async {
    if (_isLoading) return;

    _isLoading = true;
    _errorMessage = null;
    _currentPage = 1;
    notifyListeners();

    try {
      final response = await _service.fetchEvents(
        page: 1,
        size: pageSize,
        category: _selectedCategory,
        deviceId: deviceId,
      );

      final liveSessionEvents = _events.where((e) => e.id.startsWith('live_')).toList();
      final cloudIds = response.events.map((e) => e.id).toSet();
      final merged = [
        ...liveSessionEvents.where((e) => !cloudIds.contains(e.id)),
        ...response.events,
      ];
      _events = merged;
      _hasMore = response.hasMore;
      _errorMessage = null;
    } catch (e) {
      // If error occurs (e.g. offline), retain live session events
      if (_events.isEmpty) {
        _errorMessage = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Pull-to-refresh: resets pagination and reloads the current category without blocking UI.
  Future<void> refresh() async {
    _currentPage = 1;
    _hasMore = true;
    _errorMessage = null;

    try {
      final response = await _service.fetchEvents(
        page: 1,
        size: pageSize,
        category: _selectedCategory,
        deviceId: deviceId,
      );

      final liveSessionEvents = _events.where((e) => e.id.startsWith('live_')).toList();
      final cloudIds = response.events.map((e) => e.id).toSet();
      final merged = [
        ...liveSessionEvents.where((e) => !cloudIds.contains(e.id)),
        ...response.events,
      ];
      _events = merged;
      _hasMore = response.hasMore;
      _errorMessage = null;
    } catch (e) {
      if (_events.isEmpty) {
        _errorMessage = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      }
    } finally {
      notifyListeners();
    }
  }

  /// Loads the next page of events (Infinite Scroll).
  Future<void> loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;

    _isLoadingMore = true;
    notifyListeners();

    final nextPage = _currentPage + 1;

    try {
      final response = await _service.fetchEvents(
        page: nextPage,
        size: pageSize,
        category: _selectedCategory,
        deviceId: deviceId,
      );

      if (response.events.isNotEmpty) {
        // Prevent duplicates if any overlap occurs
        final existingIds = _events.map((e) => e.id).toSet();
        final newItems = response.events.where((e) => !existingIds.contains(e.id)).toList();
        _events.addAll(newItems);
        _currentPage = nextPage;
      }

      _hasMore = response.hasMore;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Changes the active category filter and reloads page 1.
  Future<void> setCategory(String category) async {
    if (_selectedCategory == category) return;
    _selectedCategory = category;
    _events = [];
    await loadInitial();
  }

  void clear() {
    _events = [];
    _isLoading = false;
    _isLoadingMore = false;
    _hasMore = true;
    _errorMessage = null;
    _currentPage = 1;
    notifyListeners();
  }
}
