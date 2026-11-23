import 'package:flutter/material.dart';

import 'library.dart';
import 'main.dart';
import 'my_list.dart';
import 'recommender.dart';
import 'tmdb.dart';

class RecommendScreen extends StatefulWidget {
  const RecommendScreen({super.key});

  @override
  State<RecommendScreen> createState() => _RecommendScreenState();
}

class _RecommendScreenState extends State<RecommendScreen> {
  final Map<String, Future<Map<int, String>>> _genreCache = {};

  String _type = 'movie';
  final Set<int> _genres = {};
  MediaItem? _similar;
  Person? _person;
  bool _asDirector = false;
  bool _onlyMine = false;

  bool _loading = false;
  String? _error;
  RecResult? _result;
  final Set<String> _dismissed = {};
  int _requestId = 0;

  Future<Map<int, String>> _genresFor(String type) =>
      _genreCache.putIfAbsent(type, () {
        final f = Tmdb.instance.genres(type);
        f.catchError((Object _) {
          _genreCache.remove(type);
          return <int, String>{};
        });
        return f;
      });

  RecQuery get _query => RecQuery(
        type: _type,
        genres: {..._genres},
        similar: _similar,
        person: _person,
        asDirector: _asDirector,
        onlyMine: _onlyMine,
      );

  void _setType(String t) {
    if (t == _type) return;
    setState(() {
      _type = t;
      _genres.clear(); // los géneros de películas y series son distintos
      _similar = null;
      _result = null;
      _error = null;
    });
  }

  Future<void> _run() async {
    final q = _query;
    if (q.isEmpty) return;
    final id = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
      _dismissed.clear();
    });
    try {
      final lib = Library.instance;
      final r = await recommend(
        q,
        isWatched: lib.isWatched,
        region: AppState.instance.home.value,
        myProviders: lib.myProviders,
      );
      if (!mounted || id != _requestId) return;
      setState(() => _result = r);
    } on TmdbException catch (e) {
      if (mounted && id == _requestId) setState(() => _error = e.message);
    } finally {
      if (mounted && id == _requestId) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final hasProviders = Library.instance.myProviders.isNotEmpty;
    final isTv = _type == 'tv';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recomiéndame'),
        actions: const [HomeCountryButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Center(
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'movie', label: Text('Película'), icon: Icon(Icons.movie_outlined)),
                ButtonSegment(value: 'tv', label: Text('Serie'), icon: Icon(Icons.tv)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => _setType(s.first),
            ),
          ),
          const SizedBox(height: 18),

          // --- Géneros
          _SectionTitle('Géneros', trailing: _genres.isEmpty ? null : 'Uno o varios'),
          FutureBuilder<Map<int, String>>(
            future: _genresFor(_type),
            builder: (context, snap) {
              final g = snap.data;
              if (g == null) {
                return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
              }
              final entries = g.entries.toList()..sort((a, b) => sortKey(a.value).compareTo(sortKey(b.value)));
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in entries)
                    FilterChip(
                      label: Text(e.value),
                      selected: _genres.contains(e.key),
                      onSelected: (v) => setState(() => v ? _genres.add(e.key) : _genres.remove(e.key)),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),

          // --- Similar a
          _SectionTitle(isTv ? 'Serie similar a' : 'Película similar a'),
          if (_similar != null)
            Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                avatar: const Icon(Icons.movie_filter_outlined, size: 18),
                label: Text('${_similar!.title}${_similar!.year.isEmpty ? '' : ' (${_similar!.year})'}'),
                onDeleted: () => setState(() => _similar = null),
              ),
            )
          else
            SearchPicker<MediaItem>(
              key: ValueKey('similar-$_type'),
              hint: isTv ? 'Busca una serie' : 'Busca una película',
              search: (q) => Tmdb.instance.searchTitles(q, _type),
              title: (m) => m.title,
              subtitle: (m) => m.year.isEmpty ? '' : m.year,
              imagePath: (m) => m.posterPath,
              onPicked: (m) => setState(() => _similar = m),
            ),
          const SizedBox(height: 18),

          // --- Actor o director
          const _SectionTitle('Actor o director'),
          if (_person != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                avatar: const Icon(Icons.person_outline, size: 18),
                label: Text(_person!.name),
                onDeleted: () => setState(() => _person = null),
              ),
            ),
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              segments: [
                const ButtonSegment(value: false, label: Text('Como actor/actriz')),
                ButtonSegment(value: true, label: Text(isTv ? 'Como director/creador' : 'Como director/a')),
              ],
              selected: {_asDirector},
              onSelectionChanged: (s) => setState(() => _asDirector = s.first),
            ),
          ] else
            SearchPicker<Person>(
              hint: 'Busca un actor, actriz o director',
              search: Tmdb.instance.searchPeople,
              title: (p) => p.name,
              subtitle: (p) => p.isDirector ? 'Director/a' : (p.department == 'Acting' ? 'Actor/actriz' : p.department),
              imagePath: (p) => p.profilePath,
              onPicked: (p) => setState(() {
                _person = p;
                _asDirector = p.isDirector;
              }),
            ),
          const SizedBox(height: 12),

          // --- Solo en mis plataformas
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _onlyMine && hasProviders,
            onChanged: hasProviders ? (v) => setState(() => _onlyMine = v) : null,
            title: const Text('Solo en mis plataformas'),
            subtitle: Text(
              hasProviders
                  ? 'Lo que puedes ver ya en ${AppState.instance.countryName(AppState.instance.home.value)}'
                  : 'Primero marca tus plataformas en Mis pelis',
              style: TextStyle(color: muted),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _query.isEmpty || _loading ? null : _run,
            icon: const Icon(Icons.auto_awesome),
            label: Text(isTv ? 'Recomiéndame una serie' : 'Recomiéndame una película'),
          ),
          if (_query.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Elige al menos un género, un título o una persona.',
                  textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 12)),
            ),
          const SizedBox(height: 20),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null) MessageView(icon: Icons.error_outline, text: _error!),
          if (!_loading && _result != null) _buildResults(context),
        ],
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    final result = _result!;
    return ListenableBuilder(
      listenable: Library.instance,
      builder: (context, _) {
        final lib = Library.instance;
        final visible = result.items
            .where((r) => !lib.isWatched(r.candidate.item) && !_dismissed.contains(keyOf(r.candidate.item)))
            .toList();
        if (visible.isEmpty) {
          return const MessageView(
            icon: Icons.sentiment_neutral,
            text: 'No he encontrado nada que no hayas visto con esos criterios. Prueba a quitar alguno.',
          );
        }
        return FutureBuilder<Map<int, String>>(
          future: _genresFor(_type),
          builder: (context, snap) {
            final names = snap.data ?? const <int, String>{};
            final top = visible.first;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopPick(
                  rec: top,
                  genreNames: names,
                  requiredCount: result.requiredGenres.length,
                  person: _person,
                  onNext: visible.length > 1
                      ? () => setState(() => _dismissed.add(keyOf(top.candidate.item)))
                      : null,
                ),
                if (visible.length > 1) ...[
                  const SizedBox(height: 16),
                  Text('Otras opciones', style: Theme.of(context).textTheme.titleMedium),
                  for (final r in visible.skip(1).take(4))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: SizedBox(
                        width: 44,
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Poster(path: r.candidate.item.posterPath, width: 92),
                          ),
                        ),
                      ),
                      title: Text(r.candidate.item.title),
                      subtitle: Text('${r.candidate.item.year} · ★ ${r.candidate.vote.toStringAsFixed(1)}'
                          '${lib.isPending(r.candidate.item) ? ' · en pendientes' : ''}'),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => DetailScreen(item: r.candidate.item)),
                      ),
                    ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(trailing!, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

String _compactVotes(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k' : '$n';

class _TopPick extends StatelessWidget {
  const _TopPick({
    required this.rec,
    required this.genreNames,
    required this.requiredCount,
    required this.person,
    required this.onNext,
  });

  final Recommendation rec;
  final Map<int, String> genreNames;
  final int requiredCount;
  final Person? person;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final c = rec.candidate;
    final item = c.item;
    final lib = Library.instance;
    final allGenres = c.genreIds.map((g) => genreNames[g]).whereType<String>().join(', ');

    final reasons = <String>[
      if (requiredCount > 0)
        rec.matchedGenres.length == requiredCount
            ? 'Tiene ${requiredCount == 1 ? 'el género' : 'todos los géneros'} que buscas'
            : 'Comparte ${rec.matchedGenres.map((g) => genreNames[g] ?? '').where((s) => s.isNotEmpty).join(', ')}',
      if (person != null) 'Con ${person!.name}',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Te recomiendo', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 100,
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Poster(path: item.posterPath)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title, style: theme.textTheme.titleLarge),
                      Text(
                        '${item.year.isEmpty ? '' : '${item.year} · '}★ ${c.vote.toStringAsFixed(1)} (${_compactVotes(c.votes)} votos)',
                        style: TextStyle(color: muted),
                      ),
                      if (allGenres.isNotEmpty) Text(allGenres, style: TextStyle(color: muted, fontSize: 12)),
                      if (reasons.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(reasons.join(' · '), style: const TextStyle(color: Colors.greenAccent, fontSize: 13)),
                      ],
                      if (lib.isPending(item))
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('🔖 Ya está en tus pendientes', style: TextStyle(color: muted, fontSize: 12)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => DetailScreen(item: item)),
                  ),
                  icon: const Icon(Icons.public),
                  label: const Text('Dónde verla'),
                ),
                OutlinedButton.icon(
                  onPressed: () => lib.togglePending(item),
                  icon: Icon(lib.isPending(item) ? Icons.bookmark : Icons.bookmark_border),
                  label: const Text('Pendiente'),
                ),
                OutlinedButton.icon(
                  onPressed: () => lib.toggleWatched(item),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Ya la vi'),
                ),
                if (onNext != null)
                  TextButton.icon(
                    onPressed: onNext,
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Otra'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Campo de búsqueda que muestra hasta 5 resultados para elegir uno.
class SearchPicker<T> extends StatefulWidget {
  const SearchPicker({
    super.key,
    required this.hint,
    required this.search,
    required this.title,
    required this.subtitle,
    required this.imagePath,
    required this.onPicked,
  });

  final String hint;
  final Future<List<T>> Function(String query) search;
  final String Function(T) title;
  final String Function(T) subtitle;
  final String? Function(T) imagePath;
  final void Function(T) onPicked;

  @override
  State<SearchPicker<T>> createState() => _SearchPickerState<T>();
}

class _SearchPickerState<T> extends State<SearchPicker<T>> {
  final TextEditingController _controller = TextEditingController();
  List<T>? _results;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.search(q);
      if (mounted) setState(() => _results = r.take(5).toList());
    } on TmdbException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hint,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ),
        if (results != null && results.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 6), child: Text('Sin resultados.')),
        if (results != null)
          for (final r in results)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: SizedBox(
                width: 34,
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Poster(path: widget.imagePath(r), width: 92),
                  ),
                ),
              ),
              title: Text(widget.title(r)),
              subtitle: widget.subtitle(r).isEmpty ? null : Text(widget.subtitle(r)),
              onTap: () {
                widget.onPicked(r);
                setState(() {
                  _results = null;
                  _controller.clear();
                });
              },
            ),
      ],
    );
  }
}
