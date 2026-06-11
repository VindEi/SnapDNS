import 'dart:async';
import 'package:flutter/material.dart';

class ToastService extends ChangeNotifier {
  static final ToastService _instance = ToastService._internal();
  factory ToastService() => _instance;
  ToastService._internal();

  String statusMessage = "";
  Timer? _toastTimer;

  void showToast(String m) {
    _toastTimer?.cancel();
    statusMessage = m;
    notifyListeners();
    _toastTimer = Timer(const Duration(seconds: 2), () {
      statusMessage = "";
      notifyListeners();
    });
  }
}
