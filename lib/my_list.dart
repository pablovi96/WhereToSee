import 'package:flutter/material.dart';

import 'library.dart';
import 'main.dart';
import 'open_in.dart';
import 'tmdb.dart';

/// Tipos de acceso que cuentan como "lo puedo ver con lo que tengo".
const _includedCats = ['flatrate', 'free', 'ads'];

/// Plataformas (sin repetir) donde se puede ver en [country] sin pagar aparte.
List<Provider> includedIn(Availability a, String country) {
  final seen = <int>{};
  final out = <Provider>[];
  for (final cat in _includedCats) {
    for (final p in a[country]?.byCategory[cat] ?? const <Provider>[]) {
      if (seen.add(p.id)) out.add(p);
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Mis pelis: Pendientes / Vistas
// ---------------------------------------------------------------------------

class MyListScreen extends StatelessWidget {
  const MyListScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mis pelis'),
          actions: [
            const HomeCountryButton(),
            IconButton(
              tooltip: 'Mis plataformas',
              icon: const Icon(Icons.tune),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const MyPlatformsScreen()),
              ),
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Pendientes'), Tab(text: 'Vistas')]),
        ),
        body: const TabBarView(children: [PendingTab(), WatchedTab()]),
      ),
    );
  }
}

class PendingTab extends StatefulWidget {
  const PendingTab({super.key});

  @override
  State<PendingTab> createState() => _PendingTabState();
}

class _PendingTabState extends State<PendingTab> {
  final Map<String, Availability> _avail = {};
  final Set<String> _loading = {};
  final Set<String> _failed = {};
  bool _onlyAvailable = false;

  void _ensureLoaded(List<SavedItem> items) {
    for (final it in items) {
      final k = it.key;
      if (_avail.containsKey(k) || _loading.contains(k)) continue;
      _loading.add(k);
      _failed.remove(k);
      Tmdb.instance.availability(it.toMediaItem()).then((a) {
        if (!mounted) return;
        setState(() {
          _avail[k] = a;
          _loading.remove(k);
        });
      }).catchError((Object _) {
        if (!mounted) return;
        setState(() {
          _loading.remove(k);
          _failed.add(k);
        });
      });
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _avail.clear();
      _failed.clear();
    });
    _ensureLoaded(Library.instance.pending);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Library.instance, AppState.instance.home, AppState.instance.regions]),
      builder: (context, _) {
        final lib = Library.instance;
        final home = AppState.instance.home.value;
        final mine = lib.myProviders;
        final items = lib.pending;
        _ensureLoaded(items);

        if (items.isEmpty) {
          return const MessageView(
            icon: Icons.bookmark_border,
            text: 'Aún no tienes pendientes. Busca una película y pulsa «Pendiente».',
          );
        }

        // 0 = la puedes ver ya, 1 = comprobando, 2 = no en las tuyas.
        int rank(SavedItem it) {
          final a = _avail[it.key];
          if (a == null) return 1;
          final inc = includedIn(a, home);
          final ok = mine.isEmpty ? inc.isNotEmpty : inc.any((p) => mine.contains(p.id));
          return ok ? 0 : 2;
        }

        var sorted = [...items]..sort((a, b) => rank(a).compareTo(rank(b)));
        if (_onlyAvailable) sorted = sorted.where((it) => rank(it) == 0).toList();
        final availableCount = items.where((it) => rank(it) == 0).length;

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            children: [
              if (mine.isEmpty)
                Card(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Marca las plataformas que tienes y verás qué pendientes puedes ver ya.'),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => const MyPlatformsScreen()),
                          ),
                          icon: const Icon(Icons.tune),
                          label: const Text('Elegir mis plataformas'),
                        ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${flagOf(home)}  $availableCount de ${items.length} '
                        '${mine.isEmpty ? 'disponibles en ${AppState.instance.countryName(home)}' : 'en tus plataformas'}',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                    FilterChip(
                      label: const Text('Solo disponibles'),
                      selected: _onlyAvailable,
                      onSelected: (v) => setState(() => _onlyAvailable = v),
                    ),
                  ],
                ),
              ),
              for (final it in sorted)
                _PendingTile(
                  item: it,
                  availability: _avail[it.key],
                  failed: _failed.contains(it.key),
                  home: home,
                  mine: mine,
                ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

class _PendingTile extends StatelessWidget {
  const _PendingTile({
    required this.item,
    required this.availability,
    required this.failed,
    required this.home,
    required this.mine,
  });

  final SavedItem item;
  final Availability? availability;
  final bool failed;
  final String home;
  final Set<int> mine;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final a = availability;
    Widget status;
    Provider? playOn;

    if (failed) {
      status = Text('No se pudo comprobar. Desliza hacia abajo para reintentar.', style: TextStyle(color: muted));
    } else if (a == null) {
      status = Text('Comprobando…', style: TextStyle(color: muted));
    } else {
      final inc = includedIn(a, home);
      final yours = mine.isEmpty ? inc : inc.where((p) => mine.contains(p.id)).toList();
      if (yours.isNotEmpty) {
        status = Text(
          '✓ ${mine.isEmpty ? 'En' : 'En tus plataformas:'} ${yours.map((p) => p.name).join(', ')}',
          style: const TextStyle(color: Colors.greenAccent),
        );
        playOn = yours.firstWhere(
          (p) => openTargetFor(p.name, item.title) != null,
          orElse: () => yours.first,
        );
      } else if (inc.isNotEmpty) {
        status = Text('No está en las tuyas · Sí en: ${inc.map((p) => p.name).join(', ')}',
            style: TextStyle(color: muted));
      } else {
        status = Text('No disponible en ${AppState.instance.countryName(home)} por ahora',
            style: TextStyle(color: muted));
      }
    }

    final pick = playOn;
    final opener = (pick != null && openTargetFor(pick.name, item.title) != null) ? pick : null;

    return ListTile(
      leading: SizedBox(
        width: 44,
        child: AspectRatio(
          aspectRatio: 2 / 3,
          child: ClipRRect(borderRadius: BorderRadius.circular(6), child: Poster(path: item.posterPath, width: 92)),
        ),
      ),
      title: Text(item.title + (item.year.isEmpty ? '' : ' (${item.year})')),
      subtitle: status,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => DetailScreen(item: item.toMediaItem())),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (opener != null)
            IconButton(
              tooltip: 'Abrir en ${opener.name}',
              icon: const Icon(Icons.play_circle_fill),
              color: Colors.greenAccent,
              onPressed: () => openInProvider(context, opener.name, item.title),
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'seen') Library.instance.toggleWatched(item.toMediaItem());
              if (v == 'remove') Library.instance.remove(item);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'seen', child: Text('Marcar como vista')),
              PopupMenuItem(value: 'remove', child: Text('Quitar de pendientes')),
            ],
          ),
        ],
      ),
    );
  }
}

class WatchedTab extends StatelessWidget {
  const WatchedTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Library.instance,
      builder: (context, _) {
        final items = Library.instance.watched;
        if (items.isEmpty) {
          return const MessageView(
            icon: Icons.check_circle_outline,
            text: 'Aún no has marcado ninguna como vista.',
          );
        }
        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                '${items.length} ${items.length == 1 ? 'vista' : 'vistas'}',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            for (final it in items)
              ListTile(
                leading: SizedBox(
                  width: 44,
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Poster(path: it.posterPath, width: 92),
                    ),
                  ),
                ),
                title: Text(it.title),
                subtitle: Text(
                  '${it.year.isEmpty ? '' : '${it.year} · '}${it.mediaType == 'tv' ? 'Serie' : 'Película'}',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => DetailScreen(item: it.toMediaItem())),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'pending') Library.instance.togglePending(it.toMediaItem());
                    if (v == 'remove') Library.instance.remove(it);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'pending', child: Text('Pasar a pendientes')),
                    PopupMenuItem(value: 'remove', child: Text('Quitar de vistas')),
                  ],
                ),
              ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Mis plataformas
// ---------------------------------------------------------------------------

class MyPlatformsScreen extends StatefulWidget {
  const MyPlatformsScreen({super.key});

  @override
  State<MyPlatformsScreen> createState() => _MyPlatformsScreenState();
}

class _MyPlatformsScreenState extends State<MyPlatformsScreen> {
  List<Provider>? _providers;
  String? _error;
  String _loadedFor = '';
  String _filter = '';

  @override
  void initState() {
    super.initState();
    AppState.instance.home.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AppState.instance.home.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final home = AppState.instance.home.value;
    if (home == _loadedFor && _providers != null) return;
    _loadedFor = home;
    if (_providers != null || _error != null) {
      setState(() {
        _providers = null;
        _error = null;
      });
    }
    try {
      final list = await Tmdb.instance.regionProviders(home);
      if (!mounted || home != AppState.instance.home.value) return;
      setState(() => _providers = list);
    } on TmdbException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final home = AppState.instance.home.value;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis plataformas'),
        actions: const [HomeCountryButton()],
      ),
      body: ListenableBuilder(
        listenable: Library.instance,
        builder: (context, _) {
          final lib = Library.instance;
          if (_error != null) {
            return MessageView(icon: Icons.error_outline, text: _error!);
          }
          final all = _providers;
          if (all == null) return const Center(child: CircularProgressIndicator());

          final f = sortKey(_filter);
          final shown = all.where((p) => f.isEmpty || sortKey(p.name).contains(f)).toList()
            // Las que ya tienes, arriba.
            ..sort((a, b) {
              final am = lib.hasProvider(a.id) ? 0 : 1;
              final bm = lib.hasProvider(b.id) ? 0 : 1;
              return am != bm ? am.compareTo(bm) : all.indexOf(a).compareTo(all.indexOf(b));
            });

          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Marca las que tienes contratadas en ${flagOf(home)} ${AppState.instance.countryName(home)}. '
                  'Se guarda solo en este teléfono.',
                  style: TextStyle(color: muted),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  onChanged: (v) => setState(() => _filter = v.trim()),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Buscar plataforma',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              for (final p in shown)
                CheckboxListTile(
                  value: lib.hasProvider(p.id),
                  onChanged: (v) => lib.setProvider(p.id, v ?? false),
                  title: Text(p.name),
                  secondary: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: p.logoPath == null
                        ? const SizedBox(width: 36, height: 36, child: Icon(Icons.live_tv))
                        : Image.network('${imgBase}w92${p.logoPath}', width: 36, height: 36,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox(width: 36, height: 36, child: Icon(Icons.live_tv))),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}
