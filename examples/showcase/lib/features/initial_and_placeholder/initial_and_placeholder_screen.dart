/// Data before the first fetch, the two ways: `initialData`, which is written
/// to the cache as if it had been fetched and ages by `staleTime` from
/// `initialDataUpdatedAt`; and `placeholderData`, which is only shown — never
/// cached — and flagged `isPlaceholderData` on the result. Port-specific; it
/// walks upstream's guides `initial-query-data` and `placeholder-query-data`.
///
/// Three cards, all read through `QueryMixin`'s `watchQuery`:
///
/// - **A.** A post's detail seeds itself from the cached posts list with
///   `InitialData.compute` (returning `null` when the list is not there yet,
///   which means "no seed") and dates the seed with the list's own
///   `dataUpdatedAt`. Under a 30 s `staleTime` that costs no request; a
///   switch dates the seed a minute older, and then a fetch follows.
/// - **B.** A fixed `PlaceholderData.value` shows a stand-in title while post
///   4's request is in flight, and the cache stays empty until the answer.
/// - **C.** `PlaceholderData.compute((previous, _) => previous)` — upstream's
///   `keepPreviousData` — keeps the last post on screen while the segmented
///   button switches the key to the next one. The read carries an `id`, which
///   is what makes the mixin's observer follow the key instead of starting a
///   new one (see the binding's `key_change_test.dart`).
/// - **D.** `initialDataUpdatedAtCompute`, the lazy form of
///   `initialDataUpdatedAt`: a callback consulted only when the seed is
///   actually written, so a rebuild — and a mode whose entry already holds
///   data — costs nothing. `computeCalls=` counts it. The consequence is the
///   point: `fresh` returns `null`, which the library reads as "date it
///   `clock.now()`", and the seed is inside `staleTime`, so the mount
///   fetches nothing; `backdated` returns a timestamp older than
///   `staleTime`, and the same mount refetches at once. The two modes seed
///   two different keys, so flipping back to one already seeded shows the
///   callback staying at one call. Supplying `initialDataUpdatedAt` *and*
///   `initialDataUpdatedAtCompute` is an `ArgumentError` when the options are
///   defaulted; the screen supplies only the callback.
///
/// Proofs (widget tests in `test/features/initial_and_placeholder_test.dart`,
/// end-to-end in `e2e/tests/initial_and_placeholder.spec.ts`): a detail
/// opened from a fresh list shows its title from the seed with `fetches=0`
/// and no `GET /api/posts/<id>`; the same seed dated old shows the title and
/// fetches once; the placeholder title shows with `isPlaceholderData=true`
/// while the request is held and `getQueryData` stays null, then the real
/// title with `false`; switching post 5 to 6 keeps 5's title as placeholder
/// until 6 arrives; a detail opened before the list has settled seeds nothing
/// and fetches; card D's callback shows `computeCalls=1` through any number
/// of rebuilds and through a mode selected a second time, `fresh` settles on
/// `isStale=false` with `fetches=0`, and `backdated` shows the seed with
/// `isStale=true` while its one refetch is in flight.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../../shared/api.dart';
import '../../shared/debug_strip.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/models.dart';
import '../../shared/scope.dart';
import '../../shared/theme.dart';

const Feature initialAndPlaceholderFeature = Feature(
  id: 'initial-and-placeholder',
  title: 'Initial and placeholder data',
  summary: 'Data before the first fetch: written to the cache, or shown only.',
);

/// How long a seeded detail counts as fresh. Long enough that a seed dated
/// with the list's timestamp is fresh, short enough that one dated a minute
/// earlier is not.
const Duration seededPostStaleTime = Duration(seconds: 30);

/// The posts list card A seeds its details from.
QueryObserverOptions<List<Post>, List<Post>> postsQuery(ShowcaseApi api) =>
    QueryObserverOptions<List<Post>, List<Post>>(
      queryKey: ShowcaseKeys.posts,
      queryFn: (context) => api.posts(signal: context.signal),
    );

/// Card A: post [id]'s detail, seeded by [seed] and dated [seededAt].
///
/// `InitialData.compute` is consulted when the entry is created — and again
/// on every options update until the entry has data, as upstream does — so
/// [seed] returning `null` while the list is still loading means "no seed",
/// and the detail fetches like any other query. With a seed, the entry starts
/// in `success` dated [seededAt], and [seededPostStaleTime] decides whether
/// the mount refetches.
QueryObserverOptions<Post, Post> seededPostQuery(
  ShowcaseApi api,
  int id, {
  required Post? Function() seed,
  required DateTime? seededAt,
}) =>
    QueryObserverOptions<Post, Post>(
      queryKey: ShowcaseKeys.post(id),
      queryFn: (context) => api.post(id, signal: context.signal),
      staleTime: const StaleTime.duration(seededPostStaleTime),
      initialData: InitialData<Post>.compute(seed),
      initialDataUpdatedAt: seededAt,
    );

/// Card B: post 4 behind a fixed placeholder. The request is slowed on
/// purpose so the placeholder is on screen long enough to see.
QueryObserverOptions<Post, Post> placeholderPostQuery(ShowcaseApi api) =>
    QueryObserverOptions<Post, Post>(
      queryKey: ShowcaseKeys.post(4),
      queryFn: (context) => api.post(
        4,
        signal: context.signal,
        delay: const Duration(seconds: 1),
      ),
      placeholderData: const PlaceholderData<Post>.value(
        Post(id: 4, title: 'Loading title…', body: ''),
      ),
    );

/// Card D's mode: nothing seeded yet, or one of the two timestamps.
enum LazySeedMode {
  /// No reader, so nothing is seeded and the callback has not run.
  off,

  /// The callback returns `null`; the library dates the seed `clock.now()`.
  fresh,

  /// The callback returns a timestamp older than [seededPostStaleTime].
  backdated,
}

/// Card D's two seeds. A key each, so selecting a mode a second time meets an
/// entry that already holds data — which is where the callback is *not*
/// consulted again, and that is the guarantee the card is about.
const Post freshSeedPost =
    Post(id: 8, title: 'Seed · fresh timestamp', body: '');

/// The seed card D writes under [LazySeedMode.backdated]. Replaced on screen
/// by the real post 9 as soon as the mount's refetch lands.
const Post backdatedSeedPost =
    Post(id: 9, title: 'Seed · backdated timestamp', body: '');

/// Which post [mode] seeds, or `null` while nothing is seeded.
Post? lazySeedFor(LazySeedMode mode) => switch (mode) {
      LazySeedMode.off => null,
      LazySeedMode.fresh => freshSeedPost,
      LazySeedMode.backdated => backdatedSeedPost,
    };

/// Card D: [seed] written to the cache, dated by [seededAt] — the lazy form
/// of `initialDataUpdatedAt`.
///
/// The callback runs exactly once per entry, when the seed is written, and
/// never again: not on a rebuild, and not when the entry is met a second time
/// with data already in it. Returning `null` is "no opinion", and the library
/// falls back to `clock.now()`.
QueryObserverOptions<Post, Post> lazySeededPostQuery(
  ShowcaseApi api, {
  required Post seed,
  required DateTime? Function() seededAt,
}) =>
    QueryObserverOptions<Post, Post>(
      queryKey: ShowcaseKeys.post(seed.id),
      queryFn: (context) => api.post(seed.id, signal: context.signal),
      staleTime: const StaleTime.duration(seededPostStaleTime),
      initialData: InitialData<Post>.value(seed),
      initialDataUpdatedAtCompute: seededAt,
    );

/// Upstream's `keepPreviousData`: whatever this observer showed last stands
/// in for the new key. A tear-off rather than an inline closure, so the
/// options built on every rebuild compare equal.
Post? keepPreviousPost(Post? previousData, Query<Post>? previousQuery) =>
    previousData;

/// Card C: post [id], with the previous post as its placeholder. Slowed a
/// little for the same reason as card B.
QueryObserverOptions<Post, Post> previousPostQuery(ShowcaseApi api, int id) =>
    QueryObserverOptions<Post, Post>(
      queryKey: ShowcaseKeys.post(id),
      queryFn: (context) => api.post(
        id,
        signal: context.signal,
        delay: const Duration(milliseconds: 750),
      ),
      placeholderData: const PlaceholderData<Post>.compute(keepPreviousPost),
    );

class InitialAndPlaceholderScreen extends StatefulWidget {
  const InitialAndPlaceholderScreen({super.key});

  @override
  State<InitialAndPlaceholderScreen> createState() =>
      _InitialAndPlaceholderScreenState();
}

class _InitialAndPlaceholderScreenState
    extends State<InitialAndPlaceholderScreen> with QueryMixin {
  /// Card A's open post, if any.
  int? _openId;
  bool _treatAsOld = false;

  /// Where the open detail's seed came from. Preset to `unused` on every
  /// open; the seed callback overwrites it when the library consults it,
  /// which it does not for an entry that already holds data.
  String _seedSource = 'unused';

  /// Card C's selected post.
  int _previousId = 5;

  /// Card D's mode, and how often its timestamp callback has run per mode.
  /// Counted rather than logged: the number is the assertion, and it must
  /// stay at one however often the card rebuilds.
  LazySeedMode _lazySeedMode = LazySeedMode.off;
  final Map<LazySeedMode, int> _lazySeedCalls = <LazySeedMode, int>{};

  void _openPost(int id) {
    setState(() {
      _openId = id;
      _seedSource = 'unused';
    });
  }

  Post? _seedFor(int id) {
    final post = queryClient
        .getQueryData<List<Post>>(ShowcaseKeys.posts)
        ?.where((post) => post.id == id)
        .firstOrNull;
    // Called inside `watchQuery`, from this build: the text below reads the
    // field after the call, so no `setState` is needed or allowed here.
    _seedSource = post == null ? 'none' : 'list';
    return post;
  }

  /// When the seed counts as fetched: the list's own timestamp, or a minute
  /// before it when the switch is on. Derived from the list rather than from
  /// a wall clock, so it is right under a test's fake clock too.
  DateTime? _seededAt() {
    final listUpdatedAt = queryClient
        .getQueryState<List<Post>>(ShowcaseKeys.posts)
        ?.dataUpdatedAt;
    if (listUpdatedAt == null) {
      return null;
    }
    return _treatAsOld
        ? listUpdatedAt.subtract(const Duration(minutes: 1))
        : listUpdatedAt;
  }

  /// Card D's `initialDataUpdatedAtCompute`. A tear-off of this method rather
  /// than a closure built in `build`, so the options a rebuild produces carry
  /// the same callback and the observer sees no change; it reads
  /// [_lazySeedMode] instead of taking it as an argument for the same reason.
  ///
  /// `null` means "no opinion": the library dates the seed `clock.now()`, so
  /// it is inside [seededPostStaleTime] and the mount fetches nothing. The
  /// backdated timestamp is derived from the posts list's own `dataUpdatedAt`
  /// rather than from a wall clock, the way card A's is — right under a
  /// test's fake clock too. With no list yet there is nothing to backdate
  /// from, and the seed is dated `clock.now()` like the fresh one.
  DateTime? _lazySeededAt() {
    final mode = _lazySeedMode;
    _lazySeedCalls.update(mode, (count) => count + 1, ifAbsent: () => 1);
    if (mode != LazySeedMode.backdated) {
      return null;
    }
    return queryClient
        .getQueryState<List<Post>>(ShowcaseKeys.posts)
        ?.dataUpdatedAt
        ?.subtract(seededPostStaleTime * 2);
  }

  @override
  Widget build(BuildContext context) {
    final api = ShowcaseScope.apiOf(context);
    final posts = watchQuery(postsQuery(api));
    final openId = _openId;
    final open = openId == null
        ? null
        : watchQuery(seededPostQuery(
            api,
            openId,
            seed: () => _seedFor(openId),
            seededAt: _seededAt(),
          ));
    final placeholder = watchQuery(placeholderPostQuery(api));
    // The `id` is what lets the observer follow the key: without it a new
    // key is a new observer, and a fresh observer has no previous data to
    // hand to `PlaceholderData.compute`.
    final previous = watchQuery(
      previousPostQuery(api, _previousId),
      id: 'previous',
    );
    final lazySeed = lazySeedFor(_lazySeedMode);
    final lazy = lazySeed == null
        ? null
        : watchQuery(lazySeededPostQuery(
            api,
            seed: lazySeed,
            seededAt: _lazySeededAt,
          ));
    // Seeding is not fetching: `dataUpdateCount` stays at zero for an entry
    // that only ever held its seed, so it says whether the mount refetched
    // without anyone reading a clock.
    final lazyState = lazySeed == null
        ? null
        : queryClient.getQueryState<Post>(ShowcaseKeys.post(lazySeed.id));
    // Read from the cache, not from the result: a placeholder is only ever
    // in the result, and this is what shows it.
    final cached = queryClient.getQueryData<Post>(ShowcaseKeys.post(4));

    return FeatureScaffold(
      feature: initialAndPlaceholderFeature,
      children: <Widget>[
        SectionCard(
          title: 'A. Initial data from another entry',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _PostsList(posts),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: <Widget>[
                  for (final id in const <int>[1, 2, 3])
                    OutlinedButton(
                      onPressed: () => _openPost(id),
                      child: Text('Open post $id'),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Treat initial data as old'),
                subtitle: const Text(
                  'Dates the seed a minute before the list arrived — older '
                  'than staleTime, so a fetch follows.',
                ),
                value: _treatAsOld,
                onChanged: (value) => setState(() => _treatAsOld = value),
              ),
              if (open == null)
                const Text('Open a post: its detail seeds itself from the '
                    'list above.')
              else
                _PostDetail(
                  open,
                  card: 'A',
                  facts: <String>['initialData source=$_seedSource'],
                ),
            ],
          ),
        ),
        if (openId != null)
          QueryDebugStrip(
            queryKey: ShowcaseKeys.post(openId),
            label: 'post-$openId',
          ),
        SectionCard(
          title: 'B. Placeholder value',
          trailing: IconButton(
            tooltip: 'Refetch',
            onPressed: placeholder.isFetching ? null : placeholder.refetch,
            icon: const Icon(Icons.refresh),
          ),
          child: _PostDetail(
            placeholder,
            card: 'B',
            facts: <String>[
              'isPlaceholderData=${placeholder.isPlaceholderData}',
              'cache=${cached == null ? 'empty' : 'post'}',
            ],
          ),
        ),
        QueryDebugStrip(queryKey: ShowcaseKeys.post(4), label: 'post-4'),
        SectionCard(
          title: 'C. Placeholder from the previous query',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SegmentedButton<int>(
                segments: <ButtonSegment<int>>[
                  for (final id in const <int>[5, 6, 7])
                    ButtonSegment<int>(value: id, label: Text('Post $id')),
                ],
                selected: <int>{_previousId},
                onSelectionChanged: (selection) =>
                    setState(() => _previousId = selection.first),
              ),
              const SizedBox(height: 12),
              _PostDetail(
                previous,
                card: 'C',
                facts: <String>[
                  'isPlaceholderData=${previous.isPlaceholderData}',
                ],
              ),
            ],
          ),
        ),
        QueryDebugStrip(
          queryKey: ShowcaseKeys.post(_previousId),
          label: 'post-$_previousId',
        ),
        SectionCard(
          title: 'D. A seed timestamp computed lazily',
          trailing: IconButton(
            tooltip: 'Rebuild card D',
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'initialDataUpdatedAtCompute is the lazy form of '
                'initialDataUpdatedAt: it runs only when the seed is actually '
                'written. fresh returns null, which the library reads as '
                'clock.now(), so the seed is inside the 30 s staleTime and '
                'the mount fetches nothing. backdated returns a minute '
                'earlier, so the same mount refetches at once. Picking a mode '
                'again meets an entry that already holds data, and the '
                'callback is not consulted a second time.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              // Explicit child nodes: without them the three segments fold
              // into one label and `fresh` is not a text a test can read.
              Semantics(
                container: true,
                explicitChildNodes: true,
                label: 'lazy-seed mode',
                child: SegmentedButton<LazySeedMode>(
                  key: const ValueKey<String>('lazy-seed-mode'),
                  showSelectedIcon: false,
                  segments: const <ButtonSegment<LazySeedMode>>[
                    ButtonSegment<LazySeedMode>(
                      value: LazySeedMode.off,
                      label: Text('off'),
                    ),
                    ButtonSegment<LazySeedMode>(
                      value: LazySeedMode.fresh,
                      label: Text('fresh'),
                    ),
                    ButtonSegment<LazySeedMode>(
                      value: LazySeedMode.backdated,
                      label: Text('backdated'),
                    ),
                  ],
                  selected: <LazySeedMode>{_lazySeedMode},
                  onSelectionChanged: (selection) =>
                      setState(() => _lazySeedMode = selection.first),
                ),
              ),
              const SizedBox(height: 12),
              if (lazy == null)
                const Text('Nothing seeded: pick a timestamp above.')
              else
                _PostDetail(
                  lazy,
                  card: 'D',
                  facts: <String>[
                    'mode=${_lazySeedMode.name}',
                    'computeCalls=${_lazySeedCalls[_lazySeedMode] ?? 0}',
                    'refetched=${(lazyState?.dataUpdateCount ?? 0) > 0}',
                  ],
                ),
            ],
          ),
        ),
        if (lazySeed != null)
          QueryDebugStrip(
            queryKey: ShowcaseKeys.post(lazySeed.id),
            label: 'lazy-seed',
          ),
      ],
    );
  }
}

/// The first few posts of the list — the ones the cards below use — each as
/// `#id · title`, so a title on its own is always a detail's.
class _PostsList extends StatelessWidget {
  const _PostsList(this.posts);

  final QueryResult<List<Post>> posts;

  static const int _shown = 7;

  @override
  Widget build(BuildContext context) => switch (posts) {
        QueryPending() => const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SkeletonBox(),
              SizedBox(height: 4),
              SkeletonBox(),
              SizedBox(height: 4),
              SkeletonBox(),
            ],
          ),
        QueryError(:final error, staleData: null) =>
          Notice('$error', error: true),
        QuerySuccess(:final data) ||
        QueryError(staleData: final data!) =>
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('posts=${data.length}',
                  style: Theme.of(context).textTheme.labelLarge),
              for (final post in data.take(_shown))
                Text('#${post.id} · ${post.title}'),
              if (data.length > _shown)
                Text('… and ${data.length - _shown} more',
                    style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
      };
}

/// One post's title and the facts a test reads, or a skeleton while it has
/// nothing to show.
///
/// A semantics group named `detail <card>` (widget key `detail-<card>`), the
/// way the debug strip is one: two cards show `isPlaceholderData=false` at
/// once, and a test has to say which one it means.
class _PostDetail extends StatelessWidget {
  const _PostDetail(this.post, {required this.card, required this.facts});

  final QueryResult<Post> post;
  final String card;
  final List<String> facts;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'detail $card',
        child: Column(
          key: ValueKey<String>('detail-$card'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            switch (post) {
              QueryPending() => const SkeletonBox(height: 20, width: 240),
              QueryError(:final error, staleData: null) =>
                Notice('$error', error: true),
              QuerySuccess(:final data) ||
              QueryError(staleData: final data!) =>
                Text(
                  data.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
            },
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              children: <Widget>[
                for (final fact in facts)
                  Text(
                    fact,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                if (post.isFetching) const Pill('fetching'),
              ],
            ),
          ],
        ),
      );
}
