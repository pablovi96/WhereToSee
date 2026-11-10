import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'open_in.dart';
import 'tmdb.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppState.instance.init();
  runApp(const DondeVerApp());
}

// ---------------------------------------------------------------------------
// Estado compartido: país del usuario y nombres de países.
// ---------------------------------------------------------------------------

class AppState {
  AppState._();
  static final AppState instance = AppState._();

  final ValueNotifier<String> home = ValueNotifier<String>('ES');
  final ValueNotifier<Map<String, String>> regions = ValueNotifier<Map<String, String>>(fallbackRegions);

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      home.value = prefs.getString('home') ?? 'ES';
    } catch (_) {}
    try {
      final r = await Tmdb.instance.regions();
      if (r.isNotEmpty) regions.value = r;
    } catch (_) {}
  }

  Future<void> setHome(String cc) async {
    home.value = cc;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('home', cc);
    } catch (_) {}
  }

  String countryName(String cc) => regions.value[cc] ?? cc;
}

const Map<String, String> fallbackRegions = {
  'ES': 'España', 'MX': 'México', 'AR': 'Argentina', 'CO': 'Colombia', 'CL': 'Chile',
  'PE': 'Perú', 'US': 'Estados Unidos', 'GB': 'Reino Unido', 'FR': 'Francia',
  'DE': 'Alemania', 'IT': 'Italia', 'PT': 'Portugal', 'AD': 'Andorra',
};

String flagOf(String cc) {
  if (cc.length != 2) return '🏳️';
  return String.fromCharCodes(cc.toUpperCase().codeUnits.map((c) => c + 127397));
}

/// Para ordenar alfabéticamente sin que las tildes manden al final.
String sortKey(String s) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñç';
  const to = 'aaaaeeeeiiiioooouuuunc';
  final lower = s.toLowerCase();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}

Future<void> openLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  var ok = false;
  if (uri != null) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo abrir el enlace.')),
    );
  }
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

class DondeVerApp extends StatelessWidget {
  const DondeVerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFF5C518),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'Where to See',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0F1115),
      ),
      home: const SearchScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Pantalla de búsqueda
// ---------------------------------------------------------------------------

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  List<MediaItem>? _results;
  bool _loading = false;
  String? _error;
  int _searchId = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    final id = ++_searchId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Tmdb.instance.search(q);
      if (!mounted || id != _searchId) return;
      setState(() => _results = r);
    } on TmdbException catch (e) {
      if (!mounted || id != _searchId) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted && id == _searchId) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Where to See'),
        actions: [
          const HomeCountryButton(),
          IconButton(
            tooltip: 'Acerca de',
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Película o serie (p. ej. El padrino)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _search,
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) return MessageView(icon: Icons.error_outline, text: _error!);
    final results = _results;
    if (results == null) {
      return const MessageView(
        icon: Icons.movie_filter_outlined,
        text: 'Busca una película o serie y te digo en qué plataformas y países está disponible.',
      );
    }
    if (results.isEmpty && !_loading) {
      return const MessageView(icon: Icons.search_off, text: 'Sin resultados. Prueba con otro título.');
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        childAspectRatio: 0.52,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: results.length,
      itemBuilder: (context, i) => ResultCard(item: results[i]),
    );
  }
}

class ResultCard extends StatelessWidget {
  const ResultCard({super.key, required this.item});
  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => DetailScreen(item: item)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Poster(path: item.posterPath, width: 185),
            ),
          ),
          const SizedBox(height: 6),
          Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          Text(
            '${item.year.isEmpty ? '—' : item.year} · ${item.isTv ? 'Serie' : 'Película'}',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class Poster extends StatelessWidget {
  const Poster({super.key, required this.path, this.width = 185});
  final String? path;
  final int width;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: const Color(0xFF2A2F3A),
      alignment: Alignment.center,
      child: const Icon(Icons.local_movies_outlined, color: Colors.white38),
    );
    final p = path;
    if (p == null) return placeholder;
    return Image.network(
      '${imgBase}w$width$p',
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => placeholder,
      loadingBuilder: (context, child, progress) => progress == null ? child : placeholder,
    );
  }
}

class MessageView extends StatelessWidget {
  const MessageView({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Selector de "mi país"
// ---------------------------------------------------------------------------

class HomeCountryButton extends StatelessWidget {
  const HomeCountryButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppState.instance.home,
      builder: (context, home, _) => TextButton(
        onPressed: () => showCountryPicker(context),
        child: Text(flagOf(home), style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}

Future<void> showCountryPicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const FractionallySizedBox(heightFactor: 0.85, child: CountryPicker()),
  );
}

class CountryPicker extends StatefulWidget {
  const CountryPicker({super.key});

  @override
  State<CountryPicker> createState() => _CountryPickerState();
}

class _CountryPickerState extends State<CountryPicker> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final entries = state.regions.value.entries
        .where((e) => _filter.isEmpty || sortKey(e.value).contains(sortKey(_filter)))
        .toList()
      ..sort((a, b) => sortKey(a.value).compareTo(sortKey(b.value)));
    return Column(
      children: [
        const Text('Mi país', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            autofocus: false,
            onChanged: (v) => setState(() => _filter = v.trim()),
            decoration: InputDecoration(
              hintText: 'Buscar país',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final e = entries[i];
              final selected = e.key == state.home.value;
              return ListTile(
                leading: Text(flagOf(e.key), style: const TextStyle(fontSize: 24)),
                title: Text(e.value),
                trailing: selected ? const Icon(Icons.check) : null,
                onTap: () {
                  state.setHome(e.key);
                  Navigator.of(context).pop();
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Detalle: dónde está disponible
// ---------------------------------------------------------------------------

class ProviderGroup {
  ProviderGroup(this.provider, this.countries);
  final Provider provider;
  final List<String> countries;
}

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.item});
  final MediaItem item;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  Availability? _data;
  String? _error;
  String _category = 'flatrate';
  bool _byCountry = false;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_error != null) setState(() => _error = null);
    try {
      final d = await Tmdb.instance.availability(widget.item);
      if (!mounted) return;
      // Abre la primera categoría que tenga datos.
      var first = 'flatrate';
      for (final (cat, _) in categories) {
        if (d.values.any((c) => c.byCategory.containsKey(cat))) {
          first = cat;
          break;
        }
      }
      setState(() {
        _data = d;
        _category = first;
      });
    } on TmdbException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  List<ProviderGroup> _groups(String cat) {
    final data = _data ?? {};
    final map = <int, ProviderGroup>{};
    data.forEach((cc, avail) {
      for (final p in avail.byCategory[cat] ?? const <Provider>[]) {
        map.putIfAbsent(p.id, () => ProviderGroup(p, [])).countries.add(cc);
      }
    });
    final state = AppState.instance;
    final groups = map.values.toList();
    for (final g in groups) {
      g.countries.sort((a, b) => sortKey(state.countryName(a)).compareTo(sortKey(state.countryName(b))));
    }
    groups.sort((a, b) {
      final c = b.countries.length.compareTo(a.countries.length);
      return c != 0 ? c : sortKey(a.provider.name).compareTo(sortKey(b.provider.name));
    });
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Scaffold(
      appBar: AppBar(
        title: Text(item.title, overflow: TextOverflow.ellipsis),
        actions: [
          const HomeCountryButton(),
          IconButton(
            tooltip: _byCountry ? 'Ver por plataforma' : 'Ver por país',
            icon: Icon(_byCountry ? Icons.subscriptions_outlined : Icons.public),
            onPressed: () => setState(() => _byCountry = !_byCountry),
          ),
        ],
      ),
      body: ValueListenableBuilder<String>(
        valueListenable: AppState.instance.home,
        builder: (context, home, _) => ValueListenableBuilder<Map<String, String>>(
          valueListenable: AppState.instance.regions,
          builder: (context, _, __) => _buildBody(context, home),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, String home) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final item = widget.item;
    final state = AppState.instance;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Poster(path: item.posterPath, width: 185),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: theme.textTheme.titleLarge),
                if (item.originalTitle.isNotEmpty && item.originalTitle != item.title)
                  Text(item.originalTitle, style: TextStyle(color: muted)),
                Text(
                  '${item.year.isEmpty ? '' : '${item.year} · '}${item.isTv ? 'Serie' : 'Película'}',
                  style: TextStyle(color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (_error != null) {
      return ListView(children: [
        header,
        MessageView(icon: Icons.error_outline, text: _error!),
        Center(child: FilledButton(onPressed: _load, child: const Text('Reintentar'))),
      ]);
    }
    final data = _data;
    if (data == null) {
      return ListView(children: [
        header,
        const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
      ]);
    }
    if (data.isEmpty) {
      return ListView(children: [
        header,
        const MessageView(
          icon: Icons.tv_off_outlined,
          text: 'No hay datos de disponibilidad para este título en ningún país.',
        ),
      ]);
    }

    final counts = {for (final (cat, _) in categories) cat: _groups(cat).length};
    var groups = _groups(_category);
    final f = sortKey(_filter);
    if (f.isNotEmpty) groups = groups.where((g) => sortKey(g.provider.name).contains(f)).toList();

    final homeProviderList = data[home]?.byCategory[_category] ?? const <Provider>[];
    final homeProviders = homeProviderList.map((p) => p.name).toList();
    final openable = homeProviderList.where((p) => openTargetFor(p.name, item.title) != null).toList();
    final catLabel = categories.firstWhere((c) => c.$1 == _category).$2.toLowerCase();

    final children = <Widget>[
      header,
      SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (final (cat, label) in categories)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text('$label ${counts[cat]}'),
                  selected: _category == cat,
                  onSelected: (_) => setState(() => _category = cat),
                ),
              ),
          ],
        ),
      ),
      Card(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: '${flagOf(home)}  En ${state.countryName(home)} ($catLabel): '),
                TextSpan(
                  text: homeProviders.isEmpty ? 'no disponible' : homeProviders.join(', '),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ])),
              if (openable.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in openable)
                      FilledButton.tonalIcon(
                        onPressed: () => openInProvider(context, p.name, item.title),
                        icon: const Icon(Icons.play_arrow),
                        label: Text('Abrir en ${p.name}'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: TextField(
          onChanged: (v) => setState(() => _filter = v.trim()),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Filtrar plataforma (p. ej. Netflix)',
            prefixIcon: const Icon(Icons.filter_list),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Text('Datos de ${data.length} países', style: TextStyle(color: muted, fontSize: 12)),
      ),
    ];

    if (groups.isEmpty) {
      children.add(const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Nada que mostrar en esta categoría.')),
      ));
    } else if (!_byCountry) {
      for (final g in groups) {
        children.add(_ProviderTile(
          group: g,
          home: home,
          links: data,
          initiallyExpanded: groups.length == 1 || f.isNotEmpty,
        ));
      }
    } else {
      final allowed = groups.map((g) => g.provider.id).toSet();
      final rows = data.entries
          .map((e) => MapEntry(
                e.key,
                (e.value.byCategory[_category] ?? const <Provider>[])
                    .where((p) => allowed.contains(p.id))
                    .toList(),
              ))
          .where((e) => e.value.isNotEmpty)
          .toList()
        ..sort((a, b) {
          if (a.key == home) return -1;
          if (b.key == home) return 1;
          return sortKey(state.countryName(a.key)).compareTo(sortKey(state.countryName(b.key)));
        });
      for (final r in rows) {
        children.add(ListTile(
          leading: Text(flagOf(r.key), style: const TextStyle(fontSize: 26)),
          title: Text(state.countryName(r.key) + (r.key == home ? '  · tu país' : '')),
          subtitle: Text(r.value.map((p) => p.name).join(', ')),
          onTap: () => openLink(context, data[r.key]?.link ?? ''),
        ));
      }
    }

    children.add(Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Text(
        'Datos de disponibilidad: JustWatch (vía TMDB). Toca un país para abrir la ficha en JustWatch.',
        style: TextStyle(color: muted, fontSize: 12),
      ),
    ));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(children: children),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.group,
    required this.home,
    required this.links,
    required this.initiallyExpanded,
  });

  final ProviderGroup group;
  final String home;
  final Availability links;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = AppState.instance;
    final p = group.provider;
    final n = group.countries.length;
    final atHome = group.countries.contains(home);
    final logo = p.logoPath;
    return ExpansionTile(
      key: PageStorageKey<String>('prov-${p.id}-$initiallyExpanded'),
      initiallyExpanded: initiallyExpanded,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: logo == null
            ? const SizedBox(width: 40, height: 40, child: Icon(Icons.live_tv))
            : Image.network('${imgBase}w92$logo', width: 40, height: 40, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(width: 40, height: 40, child: Icon(Icons.live_tv))),
      ),
      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '$n ${n == 1 ? 'país' : 'países'}${atHome ? '  ·  ✓ en tu país' : ''}',
        style: TextStyle(color: atHome ? Colors.greenAccent : theme.colorScheme.onSurfaceVariant),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedAlignment: Alignment.centerLeft,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final cc in group.countries)
              ActionChip(
                avatar: Text(flagOf(cc)),
                label: Text(state.countryName(cc)),
                side: cc == home ? const BorderSide(color: Colors.greenAccent) : null,
                onPressed: () => openLink(context, links[cc]?.link ?? ''),
              ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Acerca de / créditos (exigidos por TMDB y JustWatch)
// ---------------------------------------------------------------------------

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Acerca de')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Where to See', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Busca una película o serie y descubre en qué plataformas de streaming '
              'y en qué países está disponible.'),
          const SizedBox(height: 24),
          const Text('Créditos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('Los datos de disponibilidad por plataforma y país proceden de JustWatch.'),
          TextButton(
            onPressed: () => openLink(context, 'https://www.justwatch.com'),
            child: const Text('justwatch.com'),
          ),
          const Text('Títulos, pósters y logotipos proceden de The Movie Database (TMDB). '
              'Este producto usa la API de TMDB pero no está avalado ni certificado por TMDB.'),
          TextButton(
            onPressed: () => openLink(context, 'https://www.themoviedb.org'),
            child: const Text('themoviedb.org'),
          ),
          const SizedBox(height: 16),
          const Text('Privacidad', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('La app no tiene cuentas ni recoge datos personales. Lo que buscas se envía a TMDB '
              'para obtener resultados, y tu país elegido se guarda solo en este teléfono.'),
        ],
      ),
    );
  }
}
