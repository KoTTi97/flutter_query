# Funktionale Verbesserungen aus der Wettbewerbsanalyse

## Ziel und Umfang

Die wichtigsten funktionalen Lücken aus [competitor-deep-dive.md](../research/competitor-deep-dive.md), Abschnitt „What to adapt“, schließen und bestehende Query-Abläufe verbessern.

Enthalten sind die Punkte **#3, #4, #5, #6, #7, #8, #9, #13 und der typisierte Cache-Zugriff aus #15**.

Ausgeschlossen bleiben Veröffentlichung, Website, größere Dokumentationsarbeiten, DevTools, Persistence, Hooks-/Bloc-Pakete, CI-/Pre-commit-Ausbau und zusätzliche Duration-Konstruktoren. Bestehende Core-/Flutter-Trennung, Cache-Isolation und Typprüfung bleiben erhalten.

## Prio A: Bestehende Abläufe verbessern

### 1. Sofortige Cache-Rückgabe mit Hintergrund-Revalidierung — #5

Ergänzen:

```dart
client.query(options, revalidateIfStale: true);
client.infiniteQuery(options, revalidateIfStale: true);
```

- Vorhandene Daten sofort zurückgeben; bei Staleness im Hintergrund nachladen. Ohne Daten den Fetch abwarten.
- Default `false` erhält das bisherige Verhalten.
- Vorhandene Deduplication, Cancellation, Retry- und Infinite-Query-Regeln verwenden.
- Gecachtes `null` über `hasData` erkennen.
- Hintergrundfehler im Query-State und über bestehende Cache-Callbacks melden; intern gehaltene Futures absichern.
- `StaleTime.static` löst weiterhin keinen automatischen Hintergrund-Fetch aus.

### 2. Übergreifender Mutationszustand — #9

- `MutationStateObserver<TSelected>` im Core auf `MutationCache.findAll` und Cache-Events aufbauen.
- Bestehende `MutationFilters` und ein verpflichtendes `select` verwenden. Ergebnis ist eine unveränderliche `List<TSelected>` in Cache-Reihenfolge.
- Gleichzeitige Mutationen mit demselben Key bleiben getrennte Einträge.
- Filter-/Select-Änderungen neu auswerten; nur bei veränderter Auswahl benachrichtigen.
- `MutationStateController<TSelected>` als Flutter-`ValueListenable` ergänzen.
- Dispose entfernt alle Subscriptions.

Damit können Widgets laufende Änderungen anderer Widgets beobachten, beispielsweise für Speicheranzeigen und optimistische Listen.

### 3. Listener für Side Effects — #8

- `QueryListener`, `InfiniteQueryListener` und `MutationListener` ergänzen.
- Jeder Listener nimmt einen bestehenden Controller, Callback, optional `listenWhen(previous, next)` und ein `child` entgegen. Ownership verbleibt beim Aufrufer.
- Beim Mount nur den Ausgangszustand übernehmen; keinen Callback ausführen.
- Danach Ergebnisübergänge beobachten. Auch unterdrückte Übergänge aktualisieren den Vergleichszustand.
- Callbacks außerhalb der Build-Phase zustellen. Controller-Wechsel melden sauber um; nach Dispose werden keine Callbacks ausgeführt.
- Listener lösen keine Rebuilds ihres `child` aus. Vorhandene Builder können damit kombiniert werden; separate Consumer-Widgets sind nicht erforderlich.

### 4. Provider mit eigener Client-Verwaltung — #7

```dart
QueryClientProvider.create(
  create: () => QueryClient(),
  child: app,
);
```

- Als statischen Komfort-Einstieg mit internem Stateful-Wrapper umsetzen; dieser verwendet den bestehenden Provider.
- Client genau einmal bei Initialisierung erstellen.
- Ein Rebuild mit einem anderen Callback ersetzt den Client nicht. Eine neue Widget-Identität über einen Key erzeugt eine neue Instanz.
- Beim Abbau nach dem Unmount des inneren Providers den eigenen Client genau einmal mit `clear()` aufräumen.
- Der bestehende `client:`-Konstruktor behält externe Ownership und leert übergebene Clients nicht.

### 5. Kleine Ergänzungen für Pagination und Infinite Queries — #4 und #15

- `const PlaceholderData<T>.keepPrevious()` als benannten Kurzweg ergänzen.
- Verhalten entspricht exakt `.compute((previous, _) => previous)`, einschließlich bisheriger Null-Semantik. Placeholder-Daten werden nicht in den Cache geschrieben.
- `getInfiniteQueryData<TPage, TParam>(key)` als Kurzweg für `getQueryData<InfiniteData<TPage, TParam>>(key)` ergänzen.
- Fehlender Cache liefert `null`; falscher Datentyp erzeugt den bestehenden `QueryDataTypeError`.
- Bestehende imperative Unterstützung für `pages` wiederverwenden; keine zusätzliche Paging-API einführen.

## Prio B: Neue Möglichkeiten und gezielte Verfeinerungen

### 6. Dynamische Listen paralleler Queries — #13

- Homogenen `QueriesObserver<TQueryData, TData>` mit einer Optionsliste und `setQueries(...)` ergänzen.
- Flutter erhält `QueriesController` und `QueriesBuilder`.
- Ergebnisreihenfolge folgt der Eingabe; eine leere Liste liefert ein leeres Ergebnis.
- Observer anhand von Query-Key und Vorkommen wiederverwenden. Neue Einträge abonnieren, entfernte abmelden; reines Umsortieren startet keine Requests.
- Doppelte Keys teilen den Cache, behalten aber eigene Observer-Optionen.
- Einzelne Fehler bleiben beim jeweiligen Query-Ergebnis; andere Queries laufen unabhängig weiter.
- Heterogene Records und eine zusätzliche `combine`-API gehören nicht zur ersten Ausführung.

### 7. Mindestdauer für Resume-Refetch — #3

- `AppFocusManager(refetchMinBackgroundDuration: …)` ergänzen; Default `Duration.zero`.
- Dauer über `clock` ab dem ersten Wechsel zu „unfokussiert“ messen.
- Bei Rückkehr unterhalb des Schwellwerts neue Fokus-Refetches unterdrücken.
- Fokus sofort wiederherstellen und pausierte Queries beziehungsweise Mutationen weiterhin fortsetzen.
- Diese Trennung durch Client, QueryCache und Query-Fokusbehandlung weiterreichen.
- Bestehendes Mapping beibehalten: `inactive` zählt bereits als fokussiert.

### 8. Lazy Initialdaten-Zeitstempel — #6

- `initialDataUpdatedAtCompute` als zusätzlichen Callback für normale und Infinite Queries aufnehmen. Bestehenden `DateTime?`-Parameter erhalten.
- Beide Formen gleichzeitig anzugeben ist ein Argumentfehler.
- Callback ausschließlich beim tatsächlichen Seeding auswerten; bei vorhandenen Cache-Einträgen nicht erneut ausführen.
- Rückgabe `null` verwendet wie bisher `clock.now()`.
- Optionsauflösung, Defaulted-Optionen und `copyWith` durchgängig ergänzen.

## Umsetzung und Prüfung

**Reihenfolge:** 1 → 4 → 5 → 2 → 3 → 6 → 7 → 8. Jeder Punkt wird als getrennt prüfbarer Änderungssatz umgesetzt.

Gezielte Tests:

| Bereich | Wesentliche Fälle |
|---|---|
| Revalidierung | Frische/veraltete/fehlende Daten, nullable Daten, parallele Aufrufe, Hintergrundfehler, Infinite Queries |
| Mutationszustand | Gleichzeitige Mutationen, Filter-/Select-Wechsel, unveränderte Auswahl, entfernte Einträge, Client-Isolation |
| Listener | Keine initialen Aufrufe, `listenWhen`, Controller-Wechsel, sichere Ausführung nach Build, Dispose |
| Provider | Einmalige Erstellung, Rebuilds, neue Widget-Identität, korrektes Clear, externe Ownership, keine verbleibenden Timer |
| Pagination-Komfort | Vorherige Daten bei Key-Wechsel, Null-Semantik, kein Cache-Write durch Placeholder, typisierte Infinite-Reads |
| Query-Listen | Hinzufügen, Entfernen, Umsortieren, doppelte Keys, Optionsänderungen, Teilfehler, vollständige Abmeldung |
| Resume | Unterhalb/genau am/oberhalb des Schwellwerts, `inactive`, Offline-Rückkehr, pausierte Queries und Mutationen |
| Initialdaten | Einmalige Auswertung, vorhandener Cache, fehlende Seed-Daten, Argumentkonflikt, korrekte Staleness |

Passende Upstream-Testfälle vom vorhandenen Pin übernehmen und Flutter-spezifische Regressionen ergänzen. Bestehende Core-Tests auf VM und Chrome, Binding-Tests, Analyzer und Formatprüfung ausführen.

Begleitend ausschließlich notwendige API-Kommentare, betroffene Aufrufstellen und Verhaltensnotizen aktualisieren. Vorhandene Änderungen im Arbeitsverzeichnis bleiben erhalten.
