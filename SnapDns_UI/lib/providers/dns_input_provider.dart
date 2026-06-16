import 'dart:io';
import 'package:flutter/material.dart';
import '../models/dns_configuration.dart';

enum DnsInputMode { ip, link }

enum IpType { v4, v6 }

enum SecureType { dot, doh }

class DnsInputProvider extends ChangeNotifier {
  DnsInputMode activeMode = DnsInputMode.ip;
  IpType activeIpType = IpType.v4;
  SecureType activeSecureType = SecureType.doh;

  final p4Controller = TextEditingController();
  final s4Controller = TextEditingController();
  final p6Controller = TextEditingController();
  final s6Controller = TextEditingController();
  final dohController = TextEditingController();
  final dotController = TextEditingController();

  TextEditingController get primaryController =>
      activeIpType == IpType.v4 ? p4Controller : p6Controller;
  TextEditingController get secondaryController =>
      activeIpType == IpType.v4 ? s4Controller : s6Controller;
  TextEditingController get activeSecureController =>
      activeSecureType == SecureType.doh ? dohController : dotController;

  void toggleInputMode() {
    if (activeMode == DnsInputMode.ip) {
      activeMode = DnsInputMode.link;
    } else {
      activeMode = DnsInputMode.ip;
    }
    notifyListeners();
  }

  void setIpType(IpType t) {
    activeIpType = t;
    notifyListeners();
  }

  void setSecureType(SecureType t) {
    activeSecureType = t;
    notifyListeners();
  }

  void clearInputs() {
    p4Controller.clear();
    s4Controller.clear();
    p6Controller.clear();
    s6Controller.clear();
    dohController.clear();
    dotController.clear();
  }

  void loadProfile(DnsConfiguration p) {
    p4Controller.text = p.primaryDns;
    s4Controller.text = p.secondaryDns;
    p6Controller.text = p.ipv6Primary;
    s6Controller.text = p.ipv6Secondary;
    dohController.text = p.dohUrl;
    dotController.text = p.dotHostname;

    bool hasIp = p.primaryDns.isNotEmpty ||
        p.secondaryDns.isNotEmpty ||
        p.ipv6Primary.isNotEmpty ||
        p.ipv6Secondary.isNotEmpty;
    bool hasLink = p.dohUrl.isNotEmpty || p.dotHostname.isNotEmpty;

    if (activeMode == DnsInputMode.ip && !hasIp && hasLink) {
      activeMode = DnsInputMode.link;
    } else if (activeMode == DnsInputMode.link && !hasLink && hasIp) {
      activeMode = DnsInputMode.ip;
    }

    if (activeMode == DnsInputMode.ip) {
      bool hasV4 = p.primaryDns.isNotEmpty || p.secondaryDns.isNotEmpty;
      bool hasV6 = p.ipv6Primary.isNotEmpty || p.ipv6Secondary.isNotEmpty;
      if (activeIpType == IpType.v4 && !hasV4 && hasV6) {
        activeIpType = IpType.v6;
      } else if (activeIpType == IpType.v6 && !hasV6 && hasV4) {
        activeIpType = IpType.v4;
      }
    } else {
      bool hasDoh = p.dohUrl.isNotEmpty;
      bool hasDot = p.dotHostname.isNotEmpty;
      if (activeSecureType == SecureType.doh && !hasDoh && hasDot) {
        activeSecureType = SecureType.dot;
      } else if (activeSecureType == SecureType.dot && !hasDot && hasDoh) {
        activeSecureType = SecureType.doh;
      }
    }
    notifyListeners();
  }

  bool isInputMatch(DnsConfiguration p) {
    final text = activeMode == DnsInputMode.link
        ? (activeSecureType == SecureType.doh
            ? dohController.text
            : dotController.text)
        : (activeIpType == IpType.v4 ? p4Controller.text : p6Controller.text);

    if (text.isEmpty) {
      return false;
    }

    if (activeMode == DnsInputMode.link) {
      return text ==
          (activeSecureType == SecureType.doh ? p.dohUrl : p.dotHostname);
    } else {
      return text == p.primaryDns;
    }
  }

  // FIX: Complete input validation covering both primary and secondary fields.
  bool get isInputValid {
    if (activeMode == DnsInputMode.link) {
      final text = activeSecureType == SecureType.doh
          ? dohController.text.trim()
          : dotController.text.trim();
      return text.length > 3;
    } else {
      final primary = activeIpType == IpType.v4
          ? p4Controller.text.trim()
          : p6Controller.text.trim();
      final secondary = activeIpType == IpType.v4
          ? s4Controller.text.trim()
          : s6Controller.text.trim();

      final primaryValid = InternetAddress.tryParse(primary) != null;
      final secondaryValid =
          secondary.isEmpty || InternetAddress.tryParse(secondary) != null;

      return primaryValid && secondaryValid;
    }
  }

  @override
  void dispose() {
    p4Controller.dispose();
    s4Controller.dispose();
    p6Controller.dispose();
    s6Controller.dispose();
    dohController.dispose();
    dotController.dispose();
    super.dispose();
  }
}
