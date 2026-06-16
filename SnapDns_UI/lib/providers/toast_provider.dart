import 'dart:async';
import 'package:flutter/material.dart';

class ToastProvider extends ChangeNotifier {
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

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }
}
