# Gezielte Test-Ergänzung vor 0.1.0 — 2026-09-13

Basis: `0afa74c5984616c8b32c4dffbf4de57cac95566e`.
Auftrag: konkrete Lücken schließen und den bekannten E2E-Wackler stabilisieren.
Keine neue Gesamtabnahme, keine Coverage-Prozentvorgabe, keine Produktionsänderung.

## Abgleich der ausgewählten Hauptabläufe

| Ablauf | Konkreter vorhandener Nachweis | Entscheidung |
| --- | --- | --- |
| Cache, nullable Daten, Invalidierung und Offline-Retry | `confidence_sequences_test.dart`: zwei Leser, Transportanzahl, Cache-Präsenz von null, Zwischenstatus und Recovery | Beibehalten |
| Cancel/Reset und verspätete Antworten | Dieselbe Datei: 24 Abschlussvarianten mit Status-, Cache- und Callback-Assertions | Beibehalten |
| Mutationen, Scope und Clear | Vier kombinierte Scope-Fälle; `release_transition_regressions_test.dart`: MU-01 prüft, dass Clear keine Mutation startet und den wartenden Aufrufer abbricht | Beibehalten |
| Observer, Key-Wechsel und Cleanup | Zwei Folgen mit je 20 Zyklen; `release_observer_regressions_test.dart`: OB-01 prüft fehlende fremde staleData nach Select-Fehler | Beibehalten |
| Infinite Queries | Abgebrochener Offline-Retry mit anschließendem Load-more: Seiten, Parameter, Aufrufreihenfolge und Cleanup werden geprüft | Beibehalten |
| Mutationen und Refetch bei Fokus-Rückkehr | Der portierte Fokus-Test prüfte nur Query-Requests; Reconnect hatte einen eigenen Mutationsnachweis | Einen gezielten Core-Test ergänzen |
| App-Integration | `acceptance_test.dart`: zweiter Rename samt Rollback und Backend-Zustand; Task-Manager-E2E: Request-Body, optimistischer Zwischenzustand, Rollback und Recovery | Bestehende Assertions erhalten, Fokusaufnahme stabilisieren |

Dies ist eine begrenzte Zuordnung vorhandener Assertions. Die dokumentierten
P3-Punkte und Vertragsfragen des Deep-Dive-Backlogs wurden nicht erneut auditiert.

## Ein neuer Core-Test

`focus resumes a restored mutation before refetching readers` prüft mit zwei
kontrollierten Futures: Fokus-Rückkehr startet eine wiederhergestellte pausierte
Mutation; während des Transports und ihres Erfolgs-Callbacks bleibt der alte
Query-Wert sichtbar und es startet kein Read; anschließend liest die Query
den neuen Serverwert. Nach Cleanup bleiben keine internen Timer.

Eine absichtlich beschädigte temporäre Kopie überspringt im Fokus-Handler das
Fortsetzen der Mutationen. Dort scheitert der Test an `read:0` statt `write:7`.
Der aktuelle Core besteht unverändert. Dies belegt Empfindlichkeit gegen diesen
Fehler, nicht die vollständige Abdeckung aller Fokus-Abläufe.

## E2E-Fokusaufnahme

Die bisherige Wartebedingung prüfte nach einem einmaligen Tab/Shift+Tab nur noch
den Input-Listener. War der Fokuswechsel misslungen, konnte das Warten ihn nicht
reparieren. Die begrenzte Wiederholung umfasst jetzt Klick, Fokuswechsel,
Fokus-Assertion und Listener-Prüfung. `fill`, Submit und sämtliche fachlichen
Assertions bleiben außerhalb. Der Test wiederholt keine Server-Mutation.

Die Abhängigkeit von Chromiums Debugger bleibt wie zuvor bestehen. Der Ablauf
ist keine browserübergreifende Prüfung der Flutter-Eingabeimplementierung.

## Validierung

- Vor Änderung: drei vollständige E2E-Suiten, **30 bestanden**, ohne Test-Retry.
  Der sporadische Fehler trat dabei nicht auf; frühere Ausfälle sind im
  [Backlog](../plans/post-release-backlog.md) dokumentiert.
- Nach Änderung: sieben vollständige E2E-Suiten, **70 bestanden**, ohne Test-Retry.
  In dieser Stichprobe trat kein Fehler auf; sie beweist keine dauerhafte Flake-Freiheit.
- Core VM: **742 bestanden**; kompiliert in Chrome: **738 bestanden**.
- Dart 3.6.2: **33 Ablaufprüfungen bestanden**; keine vollständige erneute Floor-Suite.
- Core-Analyzer, Formatter der geänderten Dart-Tests sowie E2E- und Website-TypeScript-Prüfungen: bestanden.
- Task-Manager-Web-App aus der genannten Produktionsbasis mit E2E-Semantics neu gebaut.

Lokale Logs: `/tmp/query-release-core-vm.log`,
`/tmp/query-release-core-chrome.log`, `/tmp/query-release-core-floor.log`,
`/tmp/query-focus-negative.log`, `/tmp/query-release-e2e-before.log`,
`/tmp/query-release-e2e-after.log`. Diese temporären Logs sind nicht eingecheckt.
Die früheren Ergebnismanifeste bleiben historische Snapshots ihrer Commits.

Zum Wiederholen der E2E-Prüfung im Verzeichnis `examples/task_manager/e2e`:

```bash
npm run build
CI=1 npx playwright test --repeat-each=7 --retries=0 --max-failures=1 --reporter=list
```

VM- und Browser-Suite laufen mit `dart test` bzw.
`dart test --platform chrome` im Core-Paket. Lokal wurden die bereits
aufgelösten Abhängigkeiten und gecachten Runner der jeweiligen SDK-Version
verwendet. Der Integrationscommit durchläuft anschließend die normale CI;
deren Ergebnis ist im zugehörigen GitHub-Actions-Lauf nachprüfbar.
