import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../providers/dns_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/toast_provider.dart';
import '../../../models/dns_configuration.dart';
import '../../../utils/dns_intelligence.dart';

class ProfileEditor extends StatefulWidget {
  final DnsConfiguration? profile;
  const ProfileEditor({super.key, this.profile});

  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  late TextEditingController _name, _group, _p4, _s4, _p6, _s6, _doh, _dot;
  int _activeTab = 0;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile?.name ?? "");
    _group = TextEditingController(text: widget.profile?.group ?? "");
    _p4 = TextEditingController(text: widget.profile?.primaryDns ?? "");
    _s4 = TextEditingController(text: widget.profile?.secondaryDns ?? "");
    _p6 = TextEditingController(text: widget.profile?.ipv6Primary ?? "");
    _s6 = TextEditingController(text: widget.profile?.ipv6Secondary ?? "");
    _doh = TextEditingController(text: widget.profile?.dohUrl ?? "");
    _dot = TextEditingController(text: widget.profile?.dotHostname ?? "");

    if (_doh.text.isNotEmpty || _dot.text.isNotEmpty) {
      _activeTab = 1;
    } else {
      _activeTab = 0;
    }
  }

  void _autofill() async {
    ClipboardData? data;

    try {
      data = await Clipboard.getData(Clipboard.kTextPlain);
    } catch (_) {
      return;
    }

    if (!mounted) return;

    final text = data?.text;
    if (text != null && text.trim().isNotEmpty) {
      final config = DnsIntelligence.parseHumanText(text);
      if (config != null) {
        setState(() {
          if (config.primaryDns.isNotEmpty) _p4.text = config.primaryDns;
          if (config.secondaryDns.isNotEmpty) _s4.text = config.secondaryDns;
          if (config.ipv6Primary.isNotEmpty) _p6.text = config.ipv6Primary;
          if (config.ipv6Secondary.isNotEmpty) _s6.text = config.ipv6Secondary;
          if (config.dohUrl.isNotEmpty) _doh.text = config.dohUrl;
          if (config.dotHostname.isNotEmpty) _dot.text = config.dotHostname;

          if (config.dohUrl.isNotEmpty || config.dotHostname.isNotEmpty) {
            _activeTab = 1;
          } else if (config.primaryDns.isNotEmpty ||
              config.ipv6Primary.isNotEmpty) {
            _activeTab = 0;
          }
        });
      } else {
        context.read<ToastProvider>().showToast("NO VALID DNS IN CLIPBOARD");
      }
    } else {
      context.read<ToastProvider>().showToast("CLIPBOARD IS EMPTY");
    }
  }

  bool _validateInputs() {
    final toast = context.read<ToastProvider>();
    final name = _name.text.trim();

    if (name.isEmpty) {
      toast.showToast("PLEASE ENTER AN IDENTIFIER");
      return false;
    }

    if (_activeTab == 0) {
      final p4 = _p4.text.trim();
      final s4 = _s4.text.trim();
      final p6 = _p6.text.trim();
      final s6 = _s6.text.trim();

      if (p4.isEmpty && p6.isEmpty) {
        toast.showToast("ENTER AT LEAST ONE PRIMARY IP");
        return false;
      }

      if (p4.isNotEmpty) {
        final ip = InternetAddress.tryParse(p4);
        if (ip == null || ip.type != InternetAddressType.IPv4) {
          toast.showToast("INVALID PRIMARY IPV4 ADDRESS");
          return false;
        }
      }

      if (s4.isNotEmpty) {
        final ip = InternetAddress.tryParse(s4);
        if (ip == null || ip.type != InternetAddressType.IPv4) {
          toast.showToast("INVALID BACKUP IPV4 ADDRESS");
          return false;
        }
      }

      if (p6.isNotEmpty) {
        final ip = InternetAddress.tryParse(p6);
        if (ip == null || ip.type != InternetAddressType.IPv6) {
          toast.showToast("INVALID PRIMARY IPV6 ADDRESS");
          return false;
        }
      }

      if (s6.isNotEmpty) {
        final ip = InternetAddress.tryParse(s6);
        if (ip == null || ip.type != InternetAddressType.IPv6) {
          toast.showToast("INVALID BACKUP IPV6 ADDRESS");
          return false;
        }
      }
    } else {
      final doh = _doh.text.trim();
      final dot = _dot.text.trim();

      if (doh.isEmpty && dot.isEmpty) {
        toast.showToast("ENTER A DOH URL OR DOT HOSTNAME");
        return false;
      }

      if (doh.isNotEmpty) {
        final uri = Uri.tryParse(doh);
        final isValidUri = uri != null &&
            (uri.scheme == 'https' || uri.scheme == 'http') &&
            uri.host.isNotEmpty;
        if (!isValidUri) {
          toast.showToast("INVALID DOH URL (MUST START WITH HTTPS://)");
          return false;
        }
      }

      if (dot.isNotEmpty) {
        if (dot.length < 3 || dot.contains(' ') || dot.contains('://')) {
          toast.showToast("INVALID DOT HOSTNAME (E.G. DNS.EXAMPLE.COM)");
          return false;
        }
      }
    }

    return true;
  }

  void _save() {
    if (!_validateInputs()) return;

    final String finalP4 = _activeTab == 0 ? _p4.text.trim() : "";
    final String finalS4 = _activeTab == 0 ? _s4.text.trim() : "";
    final String finalP6 = _activeTab == 0 ? _p6.text.trim() : "";
    final String finalS6 = _activeTab == 0 ? _s6.text.trim() : "";
    final String finalDoh = _activeTab == 1 ? _doh.text.trim() : "";
    final String finalDot = _activeTab == 1 ? _dot.text.trim() : "";

    context.read<DnsProvider>().addOrUpdateProfile(
          DnsConfiguration(
            id: widget.profile?.id,
            name: _name.text.trim(),
            group: _group.text.trim(),
            primaryDns: finalP4,
            secondaryDns: finalS4,
            ipv6Primary: finalP6,
            ipv6Secondary: finalS6,
            dohUrl: finalDoh,
            dotHostname: finalDot,
          ),
        );
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _name.dispose();
    _group.dispose();
    _p4.dispose();
    _s4.dispose();
    _p6.dispose();
    _s6.dispose();
    _doh.dispose();
    _dot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: cs.outline.withValues(alpha: 0.1)),
      ),
      title: Row(
        children: [
          const Text(
            "PROFILE EDITOR",
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          _topBtn("AUTO-FILL", _autofill, cs),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label("IDENTIFIER"),
              _field("e.g. Standard, Family Protection...", _name, false, cs),
              const SizedBox(height: 14),
              _label("GROUP / PROVIDER (OPTIONAL)"),
              _field("e.g. Cloudflare, AdGuard...", _group, false, cs),
              const SizedBox(height: 20),
              _label("PROTOCOL"),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    _tabBtn("STANDARD (IP)", 0, cs),
                    _tabBtn("SECURE (LINK)", 1, cs),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (_activeTab == 0) ...[
                _label("IPv4"),
                Row(
                  children: [
                    Expanded(child: _field("Primary v4", _p4, true, cs)),
                    const SizedBox(width: 8),
                    Expanded(child: _field("Backup v4", _s4, true, cs)),
                  ],
                ),
                const SizedBox(height: 16),
                _label("IPv6"),
                Row(
                  children: [
                    Expanded(child: _field("Primary v6", _p6, true, cs)),
                    const SizedBox(width: 8),
                    Expanded(child: _field("Backup v6", _s6, true, cs)),
                  ],
                ),
              ],
              if (_activeTab == 1) ...[
                _label("DNS-OVER-HTTPS (DoH)"),
                _field("DoH URL (https://...)", _doh, true, cs),
                const SizedBox(height: 16),
                _label("DNS-OVER-TLS (DoT)"),
                _field("DoT Hostname (dns.example.com)", _dot, true, cs),
              ],
            ],
          ),
        ),
      ),
      actions: [
        _topBtn("CANCEL", () => Navigator.pop(context), cs, isSecondary: true),
        const SizedBox(width: 8),
        InkWell(
          onTap: _save,
          mouseCursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              "SAVE",
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: cs.primary.contrastColor,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tabBtn(String l, int i, ColorScheme cs) {
    final bool active = _activeTab == i;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeTab = i),
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(2),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? cs.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
          ),
          alignment: Alignment.center,
          child: Text(
            l,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: active ? cs.primary.contrastColor : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBtn(
    String l,
    VoidCallback onTap,
    ColorScheme cs, {
    bool isSecondary = false,
  }) =>
      InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            l,
            style: TextStyle(
              fontSize: 9,
              color: isSecondary
                  ? cs.onSurface.withValues(alpha: 0.3)
                  : cs.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          t,
          style: const TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w900,
            color: Colors.grey,
          ),
        ),
      );

  Widget _field(String h, TextEditingController c, bool m, ColorScheme cs) =>
      TextField(
        controller: c,
        style: TextStyle(fontSize: 12, fontFamily: m ? 'Consolas' : null),
        decoration: InputDecoration(
          hintText: h,
          isDense: true,
          filled: true,
          fillColor: cs.onSurface.withValues(alpha: 0.02),
          contentPadding: const EdgeInsets.all(12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(2),
            borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(2),
            borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.4)),
          ),
        ),
      );
}
