# Package naming on pub.dev and TanStack affiliation facts

- **Date:** 2026-09-08
- **Ticket:** https://github.com/KoTTi97/flutter_query/issues/6
- **Scope:** facts only. Which names are free on pub.dev, what pub.dev's rules
  are, what TanStack has said about community ports, how other ports named
  themselves, and what the MIT licence obliges. The naming decision itself is a
  separate ticket.

All pub.dev lookups were made on 2026-09-08 against
`https://pub.dev/api/packages/<name>` (HTTP 200 = taken, 404 = free), plus
`/api/packages/<name>/publisher` and `/api/packages/<name>/score` for the taken
ones. "Publisher: none" means the API returned `{"publisherId": null}`, which
pub.dev renders as "unverified uploader".

## 1. Candidate names on pub.dev

### 1.1 Free names (HTTP 404 on 2026-09-08)

Grouped by what they could plausibly name. 59 names probed came back free.

| Plausible role | Free names |
|---|---|
| core (pure Dart) | `tanstack_query_core`, `flutter_query_core`, `dart_query`, `query_dart`, `dart_query_core`, `query_core_dart`, `tquery`, `tquery_core`, `stack_query`, `query_kit`, `querykit`, `async_query`, `server_state`, `server_state_query`, `query_cache`, `query_manager`, `query_observer`, `query_state`, `remote_query`, `synced_query`, `qry`, `tanstack_core`, `tanstack_core_dart`, `tanstack_dart`, `dart_tanstack`, `tanstack_query_dart`, `dart_tanstack_query`, `tanstack_query_client`, `dart_query_client`, `query_stack_core`, `dart_swr` |
| Flutter binding | `tanstack_query_flutter`, `tanstack_flutter`, `query_flutter`, `flutter_cached_query`, `flutter_data_query`, `flutter_query_kit`, `query_kit_flutter`, `query_flutter_builder`, `fl_tanstack_query`, `flutter_stack_query`, `flutter_query_scope`, `query_scope`, `flutterstack_query`, `dartstack_query`, `flutter_react_query`, `react_query`, `react_query_flutter`, `tanstack_query_builder`, `tanstack_query_kit`, `flutter_swr`, `flux_query`, `vigil` |
| demo / misc | `sensor_demo`, `flutter_query_demo`, `tanstack_demo`, `tanstack`, `tanstack_port` |

Notes on specific free names:

- `tanstack`, `tanstack_core`, `tanstack_flutter`, `tanstack_dart` are free, but
  see §3.1: the "tanstack" name is used as a scope by TanStack on npm, and on
  pub.dev it is already used by unaffiliated third parties (§1.2).
- `flux_query` and `vigil` have GitHub repos that describe themselves as
  TanStack-inspired Flutter libraries but were never published to pub.dev
  (https://github.com/interdev7/flux_query,
  https://github.com/balazsotakomaiya/vigil).

### 1.2 Taken names (HTTP 200 on 2026-09-08)

| Name | Publisher | Latest version (date) | First published | Maintained? | TanStack port? | Source |
|---|---|---|---|---|---|---|
| `flutter_query` | `flutterquery.com` (verified) | 0.11.1 (2026-07-14) | 0.0.1, 2020-09-30; 59 versions | yes: pushed 2026-07-14, 160/160 pub points, 38 likes, 268 downloads/30d | yes, "inspired by TanStack Query"; README offers a "coming from TanStack Query" guide | https://pub.dev/packages/flutter_query, https://github.com/jezsung/query (32 stars, MIT) |
| `query_core` | `flutterquery.com` (verified) | 0.2.1 (2023-07-17) | 0.1.0, 2023-05-31; 3 versions | **discontinued and unlisted**; API returns `"isDiscontinued": true, "replacedBy": "flutter_query"` | it was "The core package flutter_query depends on" (pubspec description) | https://pub.dev/packages/query_core |
| `tanstack_query` | `flutter-tanstack.com` (verified) | 1.2.7 (2026-04-15) | 1.0.0, 2025-12-18; 13 versions | yes: pushed 2026-05-19, 140/160 points, 7 likes, 42 downloads/30d | yes, explicitly a "COPY CAT" of react-query v5 (README line 12), depends on `flutter_hooks` and `provider` | https://pub.dev/packages/tanstack_query, https://github.com/Phenek/flutter_tanstack_query (3 stars, no licence file detected by GitHub) |
| `flutter_tanstack_query` | none | 0.0.1+3 (2025-09-25) | 0.0.1, 2025-07-23; 4 versions | stale: last push 2025-09-25, 3 downloads/30d | "inspired by TanStack Query (React Query)"; depends on dio, hive, connectivity_plus | https://pub.dev/packages/flutter_tanstack_query, https://github.com/Haraprosad/flutter_tanstack_query (9 stars, MIT) |
| `tanquery` | `ottomancoder.com` (verified) | 0.8.0 (2026-05-23) | 0.1.0, 2026-05-23; 9 versions | pushed 2026-08-27, 160/160 points, 6 likes, 38 downloads/30d | "TanStack Query for Dart ... Pure Dart - no Flutter dependency" (pubspec description); README: "TanStack Query-inspired" | https://pub.dev/packages/tanquery, https://github.com/OttomanDeveloper/tanquery (5 stars, licence not SPDX-detected) |
| `fquery` | none | 3.1.0 (2026-06-25) | 1.0.0-beta.1, 2022-07-02; 25 versions | yes: pushed 2026-07-12, 155/160 points, 88 likes, 1,678 downloads/30d | yes: the author opened TanStack discussion #3475 to port react-query (§3.3); depends on `flutter_hooks` | https://pub.dev/packages/fquery, https://github.com/41y08h/fquery (163 stars, MIT) |
| `fquery_core` | none | 3.1.0 (2026-06-25) | 3.0.0, 2025-10-05; 4 versions | same repo as `fquery` | "Core library used by fquery" | https://pub.dev/packages/fquery_core |
| `cached_query` | `cachedquery.dev` (verified) | 3.7.0 (2026-05-17) | 0.0.1, 2022-06-26; 77 versions | yes: pushed 2026-08-17, 160/160 points, 101 likes, 13,526 downloads/30d (largest in this space) | "inspired by tools such as SWR, RTKQuery, React Query, Urql and apollo" (README line 5); not a port | https://pub.dev/packages/cached_query, https://github.com/D-James-GH/cached_query (88 stars, MIT) |
| `cached_query_flutter` | `cachedquery.dev` (verified) | 3.4.0 (2026-05-17) | 0.0.1-dev.1, 2022-06-26; 81 versions | yes, 8,788 downloads/30d | Flutter builders for `cached_query` | https://pub.dev/packages/cached_query_flutter |
| `swrly` | none | 0.3.1 (2026-09-02) | 0.1.0, 2026-08-21; 9 versions | brand new: repo created 2026-08-20, pushed 2026-09-08 | pubspec description literally says "A TanStack Query for Flutter"; README "Inspired by TanStack Query" | https://pub.dev/packages/swrly, https://github.com/redhotsixbull/swrly (1 star, MIT) |
| `flutter_query_client` | none | 4.1.0 (2026-09-08) | 1.0.0, 2026-05-17; 10 versions | active (published today), 39 downloads/30d | "A TanStack Query-inspired server state management library for Flutter"; built on `flutter_bloc` | https://pub.dev/packages/flutter_query_client, https://github.com/ManiacOne/flutter_query_client (0 stars, MIT) |
| `fl_query` | `krtirtho.dev` (verified) | 1.1.0 (2024-06-02) | 0.1.0, 2022-07-07; 12 versions | **GitHub repo archived**; 276 downloads/30d | "Asynchronous data caching, refetching & invalidation library for Flutter"; React-Query-like | https://pub.dev/packages/fl_query, https://github.com/KRTirtho/fl-query (68 stars, Apache-2.0, archived) |
| `get_query` | none | 1.0.0+16 (2025-09-22) | 1.0.0, 2025-08-05; 17 versions | stale since 2025-09-22 | "TanStack Query-inspired ... for Flutter + GetX" | https://pub.dev/packages/get_query |
| `query_stack` | `jc.kodel.com.br` (verified) | 1.0.5 (2023-05-30) | 1.0.0-dev.1, 2023-03-31; 19 versions | **discontinued and unlisted** | mentioned in discussion #3475 as an alternative to fquery | https://pub.dev/packages/query_stack |
| `query_client` | none | 1.2.0 (2024-06-25) | 1.0.0, 2024-05-06; 5 versions | 55/160 points, `has:error` tag | no: "A user-friendly query client for seamless API and UI manipulation" | https://pub.dev/packages/query_client |
| `query` | `agilord.com` (verified) | 2.2.0 (2024-09-23) | 1.0.0, 2018-11-18; 13 versions | maintained (150/160 points) | no: a search-query parser on petitparser | https://pub.dev/packages/query |
| `query_builder` | none | 0.0.2 (2017-06-11) | 0.0.0, 2017-03-29 | dead: `is:dart3-incompatible`, `has:error` | no: SQL query builder | https://pub.dev/packages/query_builder |
| `flutter_query_builder` | none | 1.0.2 (2023-10-13) | 1.0.0, 2023-10-13 | stale | no: sqflite query builder | https://pub.dev/packages/flutter_query_builder |
| `mutation` | none | 0.2.1 (2018-12-22) | 0.1.0, 2018-12-20 | dead: `is:dart3-incompatible` | no: "A state machine written in dart" | https://pub.dev/packages/mutation |
| `swr` | `wasabeef.jp` (verified) | 0.0.0 (2021-10-26) | single version | unlisted placeholder ("A simple command-line application") | no | https://pub.dev/packages/swr |

Two facts from this table matter for the plan as it stands:

1. **`query_core`, the directory and package name used in
   `flutter-port/packages/query_core`, is taken on pub.dev** by the
   `flutter_query` author, marked discontinued with `replacedBy: flutter_query`.
   A discontinued package stays published (§2.2) and its name cannot be reused
   by anyone else unless the current owner transfers it; the name-squatting
   process (§2.3) does not apply because the package had a genuine purpose.
2. **`flutter_query` is an actively maintained, verified-publisher package**
   (0.11.1 on 2026-07-14) that itself is TanStack-inspired, so that name is not
   just taken but occupied by a direct competitor.

Seven of the taken names are Dart libraries that describe themselves as
TanStack/React-Query inspired (`flutter_query`, `tanstack_query`,
`flutter_tanstack_query`, `tanquery`, `fquery`, `swrly`, `flutter_query_client`);
of those, only `tanquery` is Flutter-free ("Pure Dart - no Flutter
dependency"). None of them claims to have ported the upstream test suite.

## 2. pub.dev naming rules and publisher requirements

### 2.1 Name constraints (pubspec)

From https://dart.dev/tools/pub/pubspec#name: "The name should be all
lowercase, with underscores to separate words, `just_like_this`. Use only basic
Latin letters and Arabic digits: `[a-z0-9_]`. Also, make sure the name is a valid
Dart identifier—that it doesn't start with digits and isn't a reserved word."
and "Try to pick a name that is clear, terse, and not already in use." The page
states no maximum length and gives no guidance for or against `dart_`/`flutter_`
prefixes.

### 2.2 Uniqueness, permanence, discontinuation

- https://pub.dev/policy, "Naming policy": "Package names play an important role
  in the pub.dev ecosystem as they are the identifier of a package; as a
  consequence package names must be unique."
- https://dart.dev/tools/pub/publishing: "Keep in mind that a published package
  lasts forever." and the pub.dev policy "disallows unpublishing packages except
  for very few cases." The alternative is to "mark them as discontinued", which
  keeps the package published, hides it from search and shows a DISCONTINUED
  badge; the owner can name a replacement package. Retraction of a version is
  possible within seven days but "Retraction isn't deletion".
- Practical consequence: a name once published on pub.dev is permanently
  unavailable to others unless transferred by its owner (§2.4) or reassigned by
  a moderator under the squatting process (§2.3).

### 2.3 Name squatting and abandoned packages

From https://pub.dev/policy, "Name squatting": "Packages may not be published
solely to reserve a name for future use. A package is considered to be engaged
in 'name squatting' if its code has no objectively and genuinely useful
purpose. We do not scan pub.dev for such packages proactively, but rather rely
on a reactive, manual process where name squatting is determined by a pub.dev
moderator." The transfer request process is: email the publisher (or
`support@pub.dev` if there is no publisher) asking for the package's purpose or
a transfer; if there is no reply within three weeks, forward the thread to
`support@pub.dev` for a moderator decision.

There is no separate policy for abandoned-but-legitimate packages: an
unmaintained package that once had a real purpose is not squatting, so its name
is only obtainable by agreement with the owner. (This is the situation for
`query_core`, `query_stack`, `fl_query`, `query_builder` and `mutation`.)

### 2.4 Verified publishers and ownership

- https://dart.dev/tools/pub/verified-publishers: "pub.dev relies on DNS (domain
  name system) domains as an identification token"; creation "verifies that
  the user creating the verified publisher has admin access to the associated
  Domain Property, based on existing logic in the Google Search Console."
  "Domain name ownership is verified only once when a publisher is created."
  "Acquiring a domain does not grant the new owner any rights to a publisher
  that was previously associated with it. Publisher ownership must be
  explicitly transferred by the current publisher owner."
- https://dart.dev/tools/pub/publishing: packages are published either under a
  verified publisher or by individual uploaders; without a publisher the page
  displays "unverified uploader". Transferring a package to a verified
  publisher is one-way ("You can't reverse this process").
- pub.dev has **no package scopes or namespaces**; a verified publisher is a
  badge on the package page, not part of the package name. This is why
  `tanstack_query` can be owned by the verified publisher `flutter-tanstack.com`
  (https://pub.dev/publishers/flutter-tanstack.com) with no relation to TanStack.

### 2.5 Trademark

From https://pub.dev/policy, "Trademark infringement": "Publishers are solely
responsible for the packages and package names they use." pub.dev "may
informally investigate valid trademark complaints submitted by trademark owners
or their authorized agents" but is "not in a position to mediate third party
disputes"; complaints go via the package page's "report package" link.

## 3. TanStack's stance on community ports

### 3.1 Trademark and brand guidance

- TanStack publishes a brand-assets page, https://tanstack.com/brand-guide. It
  contains logo lockups, social avatars, favicons and three usage lines ("Keep
  the original proportions", "Leave clear space around the mark", "Use dark
  marks on light surfaces and light marks on dark surfaces"). It has **no
  trademark statement, no naming rules for third-party projects and no
  restriction on use of the word "TanStack"**.
- No trademark policy exists in the repository either: `grep -ri trademark` over
  `query/docs`, `README.md` and `CONTRIBUTING.md` in the local clone
  (`/Users/kotti/Coding/eltako/flutter_query/query`, `refs/heads/main` at
  `50680b98c`, `@tanstack/query-core` 5.102.8) returns nothing relevant.
- A web search for a registered "TanStack" trademark returned no registration
  record; this research did not query the USPTO database directly, so
  registration status is **unverified**.
- On npm every official package lives under the `@tanstack/` scope
  (`query/packages/query-core/package.json`: `"name": "@tanstack/query-core"`,
  `"author": "tannerlinsley"`, `"homepage": "https://tanstack.com/query"`). The
  scope is what separates official from community packages in the JS
  ecosystem; pub.dev has no equivalent mechanism (§2.4).

### 3.2 How community projects appear in the docs

- The docs navigation (`query/docs/config.json`) has one community entry, the
  section labelled `"Community Resources"` (line 10), backed by
  `query/docs/community-resources.md`
  (https://github.com/TanStack/query/blob/main/docs/community-resources.md).
  Its front matter has four lists: `articles`, `media`, `utilities` and
  `others`. Every entry is a JS/TS tool built *on top of* TanStack Query
  (codegens, tRPC, wagmi, devtools, blog posts). **No entry is an alternative
  adapter or a port to another language.**
- The framework list in `config.json` contains only adapters that live in the
  monorepo: react, solid, vue, svelte, lit, angular, preact (labels at lines
  19–197). There is no "community adapters" list.
- `grep -ri 'dart\|flutter\|swift\|kotlin\|blazor\|rust'` over `query/docs`
  (excluding generated `reference/` pages) returns nothing: the docs never
  mention any non-JS port.
- The path from community adapter to official adapter is a PR into the
  monorepo. Angular Query started as a community effort (discussion #6293,
  https://github.com/TanStack/query/discussions/6293, opened 2023-11-02 by
  arnoud-dv, pointing at PR #6195) and is now
  `@tanstack/angular-query-experimental` in `query/packages/`. The monorepo is
  a pnpm/TypeScript workspace (`query/pnpm-workspace.yaml`, `nx.json`), so this
  route is not available to a Dart package.

### 3.3 Maintainer statements about a Dart/Flutter port

- **Discussion #3475 "React Query for flutter"**
  (https://github.com/TanStack/query/discussions/3475, category Ideas, opened
  2022-04-07 by 41y08h, the later author of `fquery`). The opener says "I want
  to port react-query to a dart package to be used in flutter". The accepted
  answer by maintainer TkDodo (2022-04-09,
  https://github.com/TanStack/query/discussions/3475#discussioncomment-2536063):
  "skip the `react` directory and have a look at the `core`. I can help if you
  have specific questions." This is the "start with query-core" statement.
  Follow-ups in the same thread, also by TkDodo (2022-06-19 and 2022-06-20):
  `useQuery` creates a `QueryObserver`, "the class that lets you subscribe to a
  cache key"; the `QueryClient` "is just a 'vessel' that contains the
  `QueryCache` and the `MutationCache`"; and "the Provider is react specific.
  You don't need it in other languages probably." The thread ends with 41y08h
  announcing `fquery` on pub.dev (2022-07-03) and JCKodel adding `query_stack`
  (2023-04-04). Nobody from TanStack objected to either name or asked for a
  disclaimer.
- **Discussion #776 "Create framework independent client"**
  (https://github.com/TanStack/query/discussions/776, 2020-07-17). Tanner
  Linsley: "The groundwork for this is already being laid. You can see the
  separation of concerns in the source code with folders like `core` and
  `react`." This is the origin of the core/adapter split that makes porting
  `query-core` the sanctioned entry point.
- Searches of TanStack/query discussions for "dart", "flutter", "port" +
  "swift"/"kotlin"/"python" (GitHub GraphQL search, 2026-09-08) return only
  #3475; issue search for "flutter"/"dart" returns only incidental hits
  (dependency bumps, unrelated PRs). **There is no issue, discussion or docs
  page in which TanStack endorses, lists, or objects to any non-JS port.**

### 3.4 How other non-JS ports named themselves

Repository metadata via the GitHub API on 2026-09-08. "Attribution" is the
wording found in each README; none of these READMEs reproduces TanStack's
copyright notice.

| Language | Project | Name uses "TanStack"? | Attribution wording | Explicit non-affiliation disclaimer? | Licence, stars, last push |
|---|---|---|---|---|---|
| Swift | sqwery, https://github.com/laptou/sqwery | no | "React Query for Swift"; "inspired by TanStack Query" | no | MIT, 22, 2025-10-21 |
| Swift | Pigeon, https://github.com/fmo91/Pigeon | no | "heavily inspired by React Query" | no | MIT, 432, 2021-08-01 |
| Swift | SwiftQuery, https://github.com/Kajatin/SwiftQuery | no | "Brings TanStack Query (sort of) to Swift" | no | MIT, 10, 2025-03-08 |
| Swift | swift-query, https://github.com/horita-yuya/swift-query | no | "brings TanStack Query's powerful data fetching and caching patterns to SwiftUI" | no | Apache-2.0, 4, 2025-11-19 |
| Swift | Vista, https://github.com/ras0q/vista | no | "inspired by TanStack Query" | no | none, 4, 2026-05-17 |
| Kotlin (Compose MP) | Soil / soil-query, https://github.com/soil-kt/soil | no | docs Acknowledgments: "heavily inspired by the best practices and tools from the React community", listing TanStack Query, SWR, RTK Query (https://docs.soil-kt.com/guide/what-is-soil) | no | Apache-2.0, 186, 2026-04-20 |
| Kotlin/JS | kotlin-tanstack-react-query, https://github.com/JetBrains/kotlin-wrappers/tree/master/kotlin-tanstack-react-query | yes, but it is a *wrapper* around the JS package, not a port | JetBrains-maintained binding | n/a | Apache-2.0 |
| .NET (Blazor) | Phetch, https://github.com/Jcparkyn/Phetch | no | "in the style of React Query, SWR, or RTK Query" | no | MIT, 60, 2024-07-13 |
| .NET | dotnet-query, https://github.com/psachmann/dotnet-query | no | "A TanStack Query-inspired async data fetching and state management library for .NET and Blazor" | no | MIT, 3, 2026-09-05 |
| .NET | DotNetQuery, https://github.com/msynk/dotnet-query | no | "the native, idiomatic counterpart to TanStack Query" | no | MIT, 0, 2026-07-13 |
| Rust (Leptos) | leptos_query, https://github.com/gaucho-labs/leptos_query | no | "Heavily inspired by Tanstack Query" | no | MIT, 183, 2024-04-14 |
| Rust (Dioxus) | dioxus-query, https://github.com/marc2332/dioxus-query | no | "Inspired by TanStack Query" | no | MIT, 140, 2025-12-17 |
| Python | PyStackQuery, https://github.com/rahulgurujala/PyStackQuery | partially ("Stack") | "inspired by TanStack Query" | no | none, 5, 2026-02-20 |
| Dart | fquery, https://github.com/41y08h/fquery | no | pub description: "Simple yet powerful async state management solution with in-built caching" | no | MIT, 163, 2026-07-12 |
| Dart | flutter_query, https://github.com/jezsung/query | no | "A Flutter package inspired by TanStack Query" | no | MIT, 32, 2026-07-14 |
| Dart | tanstack_query, https://github.com/Phenek/flutter_tanstack_query | **yes** | "maintained by independent Flutter developers and is not affiliated with the official TanStack team. This librairy and documentation is a COPY CAT as it closely follows TanStack Query's API architecture and design" (README line 12) | **yes** | no licence file detected, 3, 2026-05-19 |
| Dart | flutter_tanstack_query, https://github.com/Haraprosad/flutter_tanstack_query | **yes** | "Inspired by TanStack Query (React Query)" | no | MIT, 9, 2025-09-25 |
| Dart | tanquery, https://github.com/OttomanDeveloper/tanquery | **yes** ("tan") | "TanStack Query for Dart & Flutter" (repo description); "TanStack Query-inspired" (README) | no | not SPDX-detected, 5, 2026-08-27 |
| Dart | swrly, https://github.com/redhotsixbull/swrly | no | pub description: "A TanStack Query for Flutter" | no | MIT, 1, 2026-09-08 |

Pattern: outside Dart, every port chose a framework-flavoured name
(`<framework>_query`, `<Framework>Query`, or an unrelated word) and credits
TanStack with an "inspired by" line. Only the Dart ecosystem has packages that
carry "tanstack" in the package name, and only one of them (`tanstack_query`,
Phenek) states non-affiliation explicitly.

## 4. Licence and attribution obligations

- TanStack Query is licensed under the **MIT License**, "Copyright (c)
  2021-present Tanner Linsley" (`query/LICENSE`,
  https://github.com/TanStack/query/blob/main/LICENSE). `@tanstack/query-core`'s
  `package.json` also declares `"license": "MIT"`.
- The MIT condition (from that file): "The above copyright notice and this
  permission notice shall be included in all copies or substantial portions of
  the Software." A port that translates `query-core` and its test suite line by
  line, which is what this repo's fidelity strategy does, is a copy of
  "substantial portions" and so must carry Tanner Linsley's copyright line plus
  the MIT permission notice alongside the port's own licence; MIT has no
  further requirements (no NOTICE file, no attribution in docs, no
  restriction on relicensing the port's own additions).
- MIT grants no trademark or name rights; the licence text is silent on the
  name "TanStack", so nothing in the licence either permits or forbids using it
  in a package name. The only published TanStack guidance is the logo page in
  §3.1.
- pub.dev tags every package with the licence detected from its `LICENSE` file
  (`license:mit` on all the Dart packages in §1.2); a combined licence file
  should therefore keep the MIT text intact.

## 5. Sources

- pub.dev API: `https://pub.dev/api/packages/<name>`,
  `.../<name>/publisher`, `.../<name>/score` (all fetched 2026-09-08)
- https://pub.dev/policy
- https://dart.dev/tools/pub/pubspec#name
- https://dart.dev/tools/pub/publishing
- https://dart.dev/tools/pub/verified-publishers
- https://pub.dev/help/publishing
- https://tanstack.com/brand-guide
- Local clone `/Users/kotti/Coding/eltako/flutter_query/query` (read-only;
  `refs/heads/main` = `50680b98c`): `LICENSE`, `docs/config.json`,
  `docs/community-resources.md`, `packages/query-core/package.json`,
  `pnpm-workspace.yaml`
- https://github.com/TanStack/query/discussions/3475
- https://github.com/TanStack/query/discussions/776
- https://github.com/TanStack/query/discussions/6293
- GitHub REST/GraphQL API: repository metadata and README contents for every
  project in §3.4; discussion/issue/repository search (2026-09-08)
- https://docs.soil-kt.com/guide/what-is-soil
