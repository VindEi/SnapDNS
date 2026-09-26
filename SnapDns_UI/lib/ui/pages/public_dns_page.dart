import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../../models/dns_configuration.dart';
import '../../models/public_dns.dart';
import '../../providers/dns_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/toast_provider.dart';
import '../../services/public_dns_service.dart';
import '../../services/system_utils.dart';

class PublicDnsPage extends StatefulWidget {
  const PublicDnsPage({super.key});

  @override
  State<PublicDnsPage> createState() => _PublicDnsPageState();
}

class _PublicDnsPageState extends State<PublicDnsPage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expandedProviders = {};
  final Map<String, int> _latencies = {};
  PublicDnsCatalog? _catalog;
  bool _isLoading = true;
  bool _isTestingPing = false;
  bool _isDisposed = false;
  String _selectedCategory = "ALL";
  String _selectedSort = "NAME";

  static const List<String> _categories = [
    "ALL",
    "GENERAL",
    "PRIVACY",
    "AD-BLOCKING",
    "SECURITY",
    "FAMILY",
    "REGIONAL",
    "GAMING",
  ];

  static const List<String> _sortOptions = [
    "NAME",
    "PING",
    "COUNTRY",
    "PROFILES",
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _loadData() async {
    final cached = await PublicDnsService.loadCachedCatalog();
    if (cached != null && mounted && !_isDisposed) {
      setState(() {
        _catalog = cached;
        _isLoading = false;
      });
    }

    final fresh = await PublicDnsService.fetchLatestCatalog();
    if (fresh != null && mounted && !_isDisposed) {
      setState(() {
        _catalog = fresh;
        _isLoading = false;
      });
    } else if (_catalog == null && mounted && !_isDisposed) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _testVisiblePings(List<PublicDnsProvider> providers) async {
    if (_isTestingPing || _isDisposed) return;
    setState(() => _isTestingPing = true);

    const int batchSize = 5;
    final List<PublicDnsProvider> activeList =
        providers.where((p) => p.profiles.isNotEmpty).toList();

    for (int i = 0; i < activeList.length; i += batchSize) {
      if (_isDisposed) break;

      final currentBatch = activeList.skip(i).take(batchSize).toList();
      final Map<String, int> batchResults = {};

      await Future.wait(currentBatch.map((provider) async {
        final profile = provider.profiles.first;
        final config = profile.toDnsConfiguration(
          provider.id,
          provider.name,
        );
        final ms = await SystemUtils.checkLatency(config);
        batchResults[provider.id] = ms;
      }));

      if (mounted && !_isDisposed) {
        setState(() {
          _latencies.addAll(batchResults);
        });
      }
    }

    if (mounted && !_isDisposed) {
      setState(() => _isTestingPing = false);
    }
  }

  bool _matchesQuery(
      PublicDnsProvider provider, PublicDnsProfile profile, String query) {
    if (query.isEmpty) return true;

    final countryLower = provider.country.toLowerCase();
    if (countryLower == query || countryLower.startsWith(query)) {
      return true;
    }

    if (profile.primaryDns.toLowerCase().contains(query) ||
        profile.secondaryDns.toLowerCase().contains(query) ||
        profile.dohUrl.toLowerCase().contains(query) ||
        profile.dotHostname.toLowerCase().contains(query)) {
      return true;
    }

    final providerTokens =
        provider.name.toLowerCase().split(RegExp(r'[\s\-_]+'));
    if (providerTokens.any((token) => token.startsWith(query))) return true;

    final profileTokens = profile.name.toLowerCase().split(RegExp(r'[\s\-_]+'));
    if (profileTokens.any((token) => token.startsWith(query))) return true;

    if (profile.tags.any((tag) =>
        tag.toLowerCase() == query || tag.toLowerCase().startsWith(query))) {
      return true;
    }

    return false;
  }

  List<PublicDnsProvider> _getFilteredProviders() {
    if (_catalog == null) return [];

    final query = _searchController.text.trim().toLowerCase();
    final List<PublicDnsProvider> matched = [];

    for (var provider in _catalog!.providers) {
      final matchingProfiles = provider.profiles.where((profile) {
        if (_selectedCategory != "ALL") {
          final cat = profile.primaryCategory.toUpperCase();
          if (cat != _selectedCategory) return false;
        }
        return _matchesQuery(provider, profile, query);
      }).toList();

      if (matchingProfiles.isNotEmpty) {
        matched.add(PublicDnsProvider(
          id: provider.id,
          name: provider.name,
          website: provider.website,
          country: provider.country,
          profiles: matchingProfiles,
        ));
      }
    }

    if (_selectedSort == "NAME") {
      matched
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else if (_selectedSort == "PING") {
      matched.sort((a, b) {
        final rawA = _latencies[a.id];
        final rawB = _latencies[b.id];

        final int pingA = (rawA == null || rawA < 0) ? 99999 : rawA;
        final int pingB = (rawB == null || rawB < 0) ? 99999 : rawB;

        return pingA.compareTo(pingB);
      });
    } else if (_selectedSort == "COUNTRY") {
      matched.sort((a, b) => a.country.compareTo(b.country));
    } else if (_selectedSort == "PROFILES") {
      matched.sort((a, b) => b.profiles.length.compareTo(a.profiles.length));
    }

    return matched;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dns = context.watch<DnsProvider>();
    final providers = _getFilteredProviders();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(40),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            border: Border(
              bottom: BorderSide(
                  color: cs.outline.withValues(alpha: 0.1), width: 0.5),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 8),
              _PrecisionBackButton(onTap: () => Navigator.pop(context)),
              Expanded(
                child: DragToMoveArea(
                  child: Container(
                    color: Colors.transparent,
                    alignment: Alignment.center,
                    child: const Text(
                      "PUBLIC DNS DIRECTORY",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 40),
            ],
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(fontSize: 11),
                          decoration: InputDecoration(
                            hintText:
                                "Search provider, IP, domain, tag, country...",
                            hintStyle: TextStyle(
                                color: cs.onSurface.withValues(alpha: 0.3),
                                fontSize: 11),
                            prefixIcon: Icon(Icons.search_rounded,
                                size: 15,
                                color: cs.onSurface.withValues(alpha: 0.4)),
                            filled: true,
                            isDense: true,
                            fillColor: cs.surface,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: BorderSide(
                                  color: cs.outline.withValues(alpha: 0.12)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: BorderSide(
                                  color: cs.outline.withValues(alpha: 0.12)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: BorderSide(color: cs.primary),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: cs.outline.withValues(alpha: 0.12)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedSort,
                          dropdownColor: cs.surface,
                          icon: Icon(Icons.sort_rounded,
                              size: 14, color: cs.primary),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface.withValues(alpha: 0.8),
                            fontFamily: 'Consolas',
                          ),
                          items: _sortOptions.map((opt) {
                            return DropdownMenuItem(
                                value: opt, child: Text(opt));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedSort = val);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => _testVisiblePings(providers),
                        child: Container(
                          height: 36,
                          width: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: cs.surface,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: cs.outline.withValues(alpha: 0.12)),
                          ),
                          child: _isTestingPing
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 1.5, color: cs.primary),
                                )
                              : Icon(Icons.speed_rounded,
                                  size: 15, color: cs.primary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(4),
                    border:
                        Border.all(color: cs.outline.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 13, color: cs.onSurface.withValues(alpha: 0.4)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Curated index compiled from public datasets and operator documentation by the author with AI assistance. SnapDNS does not operate these third-party servers. Use at your own risk.",
                          style: TextStyle(
                            fontSize: 9,
                            color: cs.onSurface.withValues(alpha: 0.45),
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _categories.map((cat) {
                      final isSelected = _selectedCategory == cat;
                      return MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedCategory = cat),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? cs.primary.withValues(alpha: 0.15)
                                  : cs.surface,
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color: isSelected
                                    ? cs.primary
                                    : cs.outline.withValues(alpha: 0.12),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              cat,
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? cs.primary
                                    : cs.onSurface.withValues(alpha: 0.7),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                            color: cs.primary, strokeWidth: 2))
                    : providers.isEmpty
                        ? Center(
                            child: Text(
                              "NO MATCHING PROVIDERS",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: cs.onSurface.withValues(alpha: 0.3),
                                letterSpacing: 1.0,
                              ),
                            ),
                          )
                        : ListView.builder(
                            clipBehavior: Clip.antiAlias,
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                            itemCount: providers.length,
                            itemBuilder: (context, index) {
                              final provider = providers[index];
                              final bool hasMultiple =
                                  provider.profiles.length > 1;
                              final bool isExpanded =
                                  _expandedProviders.contains(provider.id);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: cs.surface,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: cs.outline.withValues(alpha: 0.1)),
                                ),
                                child: Column(
                                  children: [
                                    MouseRegion(
                                      cursor: hasMultiple
                                          ? SystemMouseCursors.click
                                          : SystemMouseCursors.basic,
                                      child: GestureDetector(
                                        onTap: hasMultiple
                                            ? () {
                                                setState(() {
                                                  if (isExpanded) {
                                                    _expandedProviders
                                                        .remove(provider.id);
                                                  } else {
                                                    _expandedProviders
                                                        .add(provider.id);
                                                  }
                                                });
                                              }
                                            : null,
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Row(
                                                      children: [
                                                        Flexible(
                                                          child: Text(
                                                            provider.name
                                                                .toUpperCase(),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w900,
                                                              color:
                                                                  cs.onSurface,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 6),
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 4,
                                                                  vertical:
                                                                      1.5),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: cs.onSurface
                                                                .withValues(
                                                                    alpha:
                                                                        0.05),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        2),
                                                          ),
                                                          child: Text(
                                                            provider.country,
                                                            style: TextStyle(
                                                              fontSize: 8,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color: cs
                                                                  .onSurface
                                                                  .withValues(
                                                                      alpha:
                                                                          0.5),
                                                            ),
                                                          ),
                                                        ),
                                                        if (hasMultiple) ...[
                                                          const SizedBox(
                                                              width: 6),
                                                          Container(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        5,
                                                                    vertical:
                                                                        1.5),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: cs.primary
                                                                  .withValues(
                                                                      alpha:
                                                                          0.1),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          2),
                                                            ),
                                                            child: Text(
                                                              "${provider.profiles.length} PROFILES",
                                                              style: TextStyle(
                                                                fontSize: 7.5,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w900,
                                                                color:
                                                                    cs.primary,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                  if (_latencies.containsKey(
                                                      provider.id)) ...[
                                                    _buildLatencyBadge(
                                                        _latencies[
                                                            provider.id]!),
                                                    const SizedBox(width: 8),
                                                  ],
                                                  if (hasMultiple)
                                                    Icon(
                                                      isExpanded
                                                          ? Icons
                                                              .keyboard_arrow_up_rounded
                                                          : Icons
                                                              .keyboard_arrow_down_rounded,
                                                      size: 18,
                                                      color: cs.onSurface
                                                          .withValues(
                                                              alpha: 0.4),
                                                    )
                                                  else
                                                    _buildImportButton(
                                                      provider.profiles.first
                                                          .toDnsConfiguration(
                                                        provider.id,
                                                        provider.name,
                                                      ),
                                                      dns,
                                                      cs,
                                                    ),
                                                ],
                                              ),
                                              if (provider
                                                      .profiles.isNotEmpty &&
                                                  provider.profiles.first
                                                          .notes !=
                                                      null) ...[
                                                const SizedBox(height: 6),
                                                Text(
                                                  provider
                                                      .profiles.first.notes!,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 9.5,
                                                    color: cs.onSurface
                                                        .withValues(alpha: 0.5),
                                                    height: 1.3,
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(height: 8),
                                              _buildUnifiedBadges(provider, cs),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (hasMultiple && isExpanded)
                                      Container(
                                        decoration: BoxDecoration(
                                          border: Border(
                                              top: BorderSide(
                                                  color: cs.outline.withValues(
                                                      alpha: 0.08))),
                                        ),
                                        child: Column(
                                          children: [
                                            Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                      12, 10, 12, 6),
                                              child: Row(
                                                children: [
                                                  Text(
                                                    "AVAILABLE PROFILES",
                                                    style: TextStyle(
                                                      fontSize: 8.5,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      color: cs.onSurface
                                                          .withValues(
                                                              alpha: 0.4),
                                                      letterSpacing: 0.8,
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  MouseRegion(
                                                    cursor: SystemMouseCursors
                                                        .click,
                                                    child: GestureDetector(
                                                      onTap: () {
                                                        final List<
                                                                DnsConfiguration>
                                                            toAdd = [];
                                                        for (var p in provider
                                                            .profiles) {
                                                          toAdd.add(p
                                                              .toDnsConfiguration(
                                                            provider.id,
                                                            provider.name,
                                                          ));
                                                        }
                                                        final current = List<
                                                                DnsConfiguration>.from(
                                                            dns.profiles);
                                                        for (var item
                                                            in toAdd) {
                                                          final idx = current
                                                              .indexWhere(
                                                                  (existing) =>
                                                                      existing
                                                                          .id ==
                                                                      item.id);
                                                          if (idx != -1) {
                                                            current[idx] = item;
                                                          } else {
                                                            current.add(item);
                                                          }
                                                        }
                                                        dns.setProfiles(
                                                            current);
                                                        context
                                                            .read<
                                                                ToastProvider>()
                                                            .showToast(
                                                                "ALL PROFILES IMPORTED");
                                                      },
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 10,
                                                                vertical: 4),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: cs.primary
                                                              .withValues(
                                                                  alpha: 0.1),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(3),
                                                          border: Border.all(
                                                              color: cs.primary
                                                                  .withValues(
                                                                      alpha:
                                                                          0.25),
                                                              width: 0.8),
                                                        ),
                                                        child: Text(
                                                          "IMPORT ALL",
                                                          style: TextStyle(
                                                            fontSize: 8.5,
                                                            fontWeight:
                                                                FontWeight.w900,
                                                            color: cs.primary,
                                                            letterSpacing: 0.5,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            ...provider.profiles.map((profile) {
                                              final config =
                                                  profile.toDnsConfiguration(
                                                provider.id,
                                                provider.name,
                                              );
                                              return Container(
                                                padding:
                                                    const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  border: Border(
                                                    bottom: BorderSide(
                                                        color: cs.outline
                                                            .withValues(
                                                                alpha: 0.04)),
                                                  ),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            profile.name,
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color: cs
                                                                  .onSurface
                                                                  .withValues(
                                                                      alpha:
                                                                          0.9),
                                                            ),
                                                          ),
                                                        ),
                                                        _buildImportButton(
                                                            config, dns, cs),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 6),
                                                    _buildProfileDetails(
                                                        profile, cs),
                                                  ],
                                                ),
                                              );
                                            }),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLatencyBadge(int ms) {
    Color color = Colors.greenAccent;
    if (ms > 150) color = Colors.orangeAccent;
    if (ms > 300 || ms < 0) color = Colors.redAccent;

    return Text(
      ms < 0 ? "--" : "${ms}MS",
      style: TextStyle(
        color: color.withValues(alpha: 0.8),
        fontSize: 8.5,
        fontWeight: FontWeight.bold,
        fontFamily: 'Consolas',
      ),
    );
  }

  Widget _buildProfileDetails(PublicDnsProfile profile, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (profile.notes != null && profile.notes!.isNotEmpty) ...[
          Text(
            profile.notes!,
            style: TextStyle(
                fontSize: 9.5,
                color: cs.onSurface.withValues(alpha: 0.5),
                height: 1.3),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 6,
          runSpacing: 5,
          children: [
            if (profile.dohUrl.isNotEmpty) _badge("DoH", cs, highlight: true),
            if (profile.dotHostname.isNotEmpty)
              _badge("DoT", cs, highlight: true),
            if (profile.ipv6Primary.isNotEmpty) _badge("IPv6", cs),
            if (profile.primaryDns.isNotEmpty) _badge("IPv4", cs),
            ...profile.tags.where((t) {
              final lower = t.toLowerCase();
              return lower != "doh" &&
                  lower != "dot" &&
                  lower != "ipv6" &&
                  lower != "ipv4";
            }).map((t) => _badge(t.toUpperCase(), cs, isFeature: true)),
          ],
        ),
      ],
    );
  }

  Widget _buildUnifiedBadges(PublicDnsProvider provider, ColorScheme cs) {
    final allProfiles = provider.profiles;
    final bool hasDoh = allProfiles.any((p) => p.dohUrl.isNotEmpty);
    final bool hasDot = allProfiles.any((p) => p.dotHostname.isNotEmpty);
    final bool hasIpv6 = allProfiles.any((p) => p.ipv6Primary.isNotEmpty);
    final bool hasIpv4 = allProfiles.any((p) => p.primaryDns.isNotEmpty);

    final Set<String> featureTags = {};
    for (var p in allProfiles) {
      featureTags.addAll(p.tags.where((t) {
        final lower = t.toLowerCase();
        return lower != "doh" &&
            lower != "dot" &&
            lower != "ipv6" &&
            lower != "ipv4";
      }));
    }

    return Wrap(
      spacing: 5,
      runSpacing: 4,
      children: [
        if (hasDoh) _badge("DoH", cs, highlight: true),
        if (hasDot) _badge("DoT", cs, highlight: true),
        if (hasIpv6) _badge("IPv6", cs),
        if (hasIpv4) _badge("IPv4", cs),
        ...featureTags
            .take(3)
            .map((t) => _badge(t.toUpperCase(), cs, isFeature: true)),
      ],
    );
  }

  Widget _buildImportButton(
      DnsConfiguration config, DnsProvider dns, ColorScheme cs) {
    final bool isAlreadyImported = dns.profiles.any((p) => p.id == config.id);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          dns.addOrUpdateProfile(config);
          context.read<ToastProvider>().showToast(
              isAlreadyImported ? "PROFILE UPDATED" : "ADDED TO PROFILES");
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isAlreadyImported ? Colors.transparent : cs.primary,
            border: isAlreadyImported
                ? Border.all(color: cs.outline.withValues(alpha: 0.2))
                : null,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            isAlreadyImported ? "SAVED" : "IMPORT",
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: isAlreadyImported
                  ? cs.onSurface.withValues(alpha: 0.4)
                  : cs.primary.contrastColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, ColorScheme cs,
      {bool highlight = false, bool isFeature = false}) {
    Color bg;
    Color border;
    Color textColor;

    if (highlight) {
      bg = cs.primary.withValues(alpha: 0.1);
      border = cs.primary.withValues(alpha: 0.25);
      textColor = cs.primary;
    } else if (isFeature) {
      bg = cs.onSurface.withValues(alpha: 0.05);
      border = cs.outline.withValues(alpha: 0.15);
      textColor = cs.onSurface.withValues(alpha: 0.85);
    } else {
      bg = cs.onSurface.withValues(alpha: 0.02);
      border = cs.outline.withValues(alpha: 0.08);
      textColor = cs.onSurface.withValues(alpha: 0.5);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 8.5,
          fontWeight:
              highlight || isFeature ? FontWeight.bold : FontWeight.normal,
          color: textColor,
        ),
      ),
    );
  }
}

class _PrecisionBackButton extends StatefulWidget {
  final VoidCallback onTap;
  const _PrecisionBackButton({required this.onTap});

  @override
  State<_PrecisionBackButton> createState() => _PrecisionBackButtonState();
}

class _PrecisionBackButtonState extends State<_PrecisionBackButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _isHovered
                ? colorScheme.onSurface.withValues(alpha: 0.05)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 14,
            color: _isHovered
                ? colorScheme.onSurface
                : colorScheme.onSurface.withValues(alpha: 0.2),
          ),
        ),
      ),
    );
  }
}
