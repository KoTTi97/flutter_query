# Core-Vertrauensprüfung — Ergebnis vom 12. September 2026

**Entscheidung: Der bestehende Core ist für einen begrenzten Praxiseinsatz
ausreichend abgesichert. Aus dieser begrenzten Prüfung bleibt kein bestätigter
Core-Blocker offen. Es wurde kein Produktionscode geändert.**

Grundlage ist der vor Ausführung festgelegte
[Prüfplan](../plans/core-confidence-acceptance.md). Geprüft wurden die sechs
Garantiegruppen, ausgewählte kombinierte Abläufe und die Integration mit dem
bestehenden Task Manager. Das Ergebnis ist keine Behauptung vollständiger
Fehlerfreiheit oder eine Abnahme des gesamten Flutter-Bindings.

## Geprüfter Stand und Änderungen

- Produktionsbasis: `b1b476e5d99600d9791f0a30720d68a922208056`.
- Core, Flutter-Binding, beide Beispiel-Implementierungen und Dependency-Lock
  sind gegenüber dieser Basis unverändert.
- Ergänzt: [32 Core-Ablaufprüfungen](../../packages/query_kit/test/confidence_sequences_test.dart),
  ein zusammenhängender Browserfall in
  [tasks.spec.ts](../../examples/task_manager/e2e/tests/tasks.spec.ts) und eine
  gezielte Widget-Gegenprobe in
  [acceptance_test.dart](../../examples/task_manager/test/acceptance_test.dart).
- Zum Abschluss der lokalen Prüfung lagen die neuen Tests und dieses Ergebnis
  als Arbeitsbaumänderungen vor; Commit und Push folgen als Integrationsschritt.
  Das Manifest beschreibt diesen lokalen Prüfzeitpunkt. Die Dateistände der
  ausführbaren Nachweise stehen im [Ergebnismanifest](core-confidence-results.json).

## Abgleich von Vertrag und Assertions

Alle folgenden Testdateien liegen, sofern nicht anders genannt, im Core-Testordner.
Die Prüfung bewertet konkrete Assertions; Dateinamen oder grüne Zählwerte allein
sind kein Nachweis. Es wurden nicht alle 409 portierten Fälle erneut einzeln auditiert.

| Garantiegruppe | Bereits vorhandene konkrete Assertions | Zusätzliche ausgewählte Prüfung und Ergebnis |
| --- | --- | --- |
| Fetch-Besitz und Deduplizierung | QER3/QER13 prüfen Transportanzahl, aktiven Fetch-Status, gemeinsamen Nachfolgerwert und Cache nach verspäteter Antwort; QER8 prüft späten Signalzugriff. Übergangstests prüfen Reset aus Sharing. | Drei gestartete Läufe, zwei Ablösungen, sechs Abschlussreihenfolgen, alte Ergebnisse erfolgreich/fehlerhaft, Cancel/Reset: **24 Fälle bestanden**. Nach jedem Abschluss werden Cache, Fetch-Status und erfolgreiche Cache-Hooks geprüft; alle Aufrufer müssen abschließen. |
| Mutation-Serialisierung und Aufrufzuordnung | MU1/MU8 prüfen Startreihenfolge; MU2 prüft Callback-Paare und Attachments; MU12 prüft Warten auf Settled-Callbacks. Der Übergangstest zum entfernten aktiven Besitzer hält den Nachfolger bis zum Callback-Abschluss zurück. | Drei Läufe, zwei Startreihenfolgen, Erfolg/Fehler des entfernten ersten Besitzers, Offline/Online und eigene Callback-Gates: **4 Fälle bestanden**. Startliste, Variablen/Context, Future-Ergebnisse und Cleanup werden geprüft. |
| Observer, Auswahl und aktuelle Aktionen | OI01 prüft Auswahl nach verworfener Vorschau; OI02 das Refetch-Ziel bei wertgleichem Key-Wechsel; OI03/OI06 verschachtelte Notifications; OI13/OI15 Placeholder-Typen und getrennte Selektionen. | **2 Fälle mit je 20 Zyklen bestanden**: Placeholder ohne Cache-Write, Rückwechsel zu gecachten Rohdaten, Collection-Key-Wechsel mit gleichen Werten, getrennte Selektionen und Refetch auf den aktuellen Key. |
| Ressourcen-Lebensdauer | QER1/QER2 prüfen fehlende Timer bzw. Events nach Clear; QER4/QER6 terminale Entfernung; OI05/OI16–OI18 Registrierungsidentität. `port_lifecycle_test.dart` prüft unter anderem Clear während asynchronem onMutate. | Dieselben wiederholten Observer-/Collection-Zyklen prüfen Stoppen der Zustellung, wirkungslose alte Handles, leere Manager-Subscriptions und null interne Timer nach Cleanup. Scope- und Query-Fälle prüfen ebenfalls Cleanup. **Bestanden.** |
| Cache, Staleness, Retry und Netzwerk | `query_client_test.dart` prüft Cache-Lesen und Fetch-Anzahl vor/an Staleness-Grenzen, aktive/inaktive/disabled/static Invalidierung und cancelRefetch. `retryer_test.dart` prüft Versuchsanzahl, Pause und Weiterlaufen. QER9–QER14 und `functional_improvements_test.dart` unterscheiden fehlende Daten und gecachtes null, auch nach Fehlern. | **1 gemeinsamer Ablauf bestanden**: zwei Observer auf gecachtem null, Invalidierung offline, ein gemeinsamer Transport, fehlgeschlagener Versuch, pausierter Retry und Recovery. Beide Observer sehen anschließend denselben frischen Wert; null bleibt zuvor vorhandenes Datum. |
| Infinite Queries | OI09 prüft entgegengesetzte Paging-Aufrufe; OI10 prüft Versuchsfolge `[1,2,3,3,4]` und passende maxPages-Daten/Parameter; OI11 verhindert weitere Seiten nach Cancel. | **1 kombinierter Ablauf bestanden**: Seitenfortschritt, fehlerhafte Seite, offline pausierter Retry, Cancel und neues Load-more. Aufruffolge `[1,2,3]`, Seiten `[20,30]`, Parameter `[2,3]`; kein späterer alter Retry. |

Die Herkunft der Verträge bleibt unterscheidbar: Cache/Staleness/Retry/Paging
stammen überwiegend aus dem Upstream-Port; nullable Präsenz, Laufzeittypen und
Listener-Registrierungen sind Dart-Anpassungen bzw. bewusste API-Entscheidungen.
Operationseigentum, Scope-Besitz und zusätzliche Cleanup-Regeln folgen den
stärkeren, bereits bestehenden Verträgen in [ADR-0003](../adr/0003-core-operation-lifetimes.md).
Die Prüfung hat diese Zusagen nicht erweitert.

## Gegenprobe: Erkennen die neuen Tests überhaupt Fehler?

Die 32 neuen Core-Fälle wurden zusätzlich mit den 30 Core-Quelldateien aus
`d7ef2d3` ausgeführt, also dem Stand vor der letzten Ownership-Reparatur.
Dafür wurde eine isolierte temporäre Kopie mit eigener Package-Zuordnung
verwendet; der Arbeitsbaum blieb unverändert.

**11 Fälle scheiterten dort an Verhaltens-Assertions, 21 bestanden.** Acht
Cancel-Reihenfolgen erkennen den verlorenen Fetch-Status, zwei Scope-Fälle die
falsche Serialisierung, ein Collection-Fall das alte Refetch-Ziel. Auf der
aktuellen Implementierung bestehen alle 32. Diese Negativkontrolle belegt
Empfindlichkeit für diese bekannten Fehlerklassen, keine Vollständigkeit.

## Fehlgeschlagene Testentwürfe und ihre Einordnung

1. Der erste Entwurf erwartete auch nach Reset stets `CancelledError` für alte
   Aufrufer. Zwölf Fälle scheiterten ausschließlich an dieser Erwartung; die
   Cache-/Status-Assertions bestanden. Reset cancelt jedoch still und reicht
   Aufrufer bei unmittelbarem Nachfolger an dessen Ergebnis weiter. Das ist
   durch bestehende Handoff-Tests abgesichert und wurde direkt im gepinnten
   Upstream reproduziert. Die neue Assertion wurde entsprechend präzisiert.
2. Der erste zusammenhängende Browserfall setzte beim zweiten Rename mit
   Playwright `fill` den semantischen Eingabewert, sendete aber den vorherigen
   Namen. Warten auf den bestehenden Feldwert behob dies nicht. Mit
   Tastaturereignissen wird der neue Name gesendet; der Test prüft ausdrücklich
   den Request-Body, die optimistische Anzeige und den Rollback. Eine zusätzliche
   Widget-Gegenprobe bestätigt den zweiten Rename unabhängig. Damit ist dieser
   Auslöser dem Browser-Eingabeweg der Testautomation zugeordnet; die exakte
   Flutter-Engine-Ursache wurde nicht untersucht. Kein Core- oder Consumer-Fix.

Diese beiden Testentwurfsprobleme wurden nicht als neue Produktbugs gezählt.
Bestehende Test-Assertions wurden nicht geändert.

## Ausgeführte Gates und Consumer-Nachweis

| Prüfung | Ergebnis |
| --- | --- |
| Gesamte Core-Suite, Dart 3.10.7 VM | **680 bestanden** |
| Gesamte Core-Suite, Dart 3.6.2 VM | **680 bestanden** |
| Gesamte Core-Suite, Dart 3.10.7 → JavaScript in Chrome | **677 bestanden**; drei bestehende Barrel-Tests sind VM-exklusiv |
| Analyzer für packages/examples/tool, fatal infos, finaler Dart-Teststand | Keine Befunde |
| Formatter der beiden geänderten Dart-Testdateien | Keine Änderungen erforderlich |
| TypeScript-Prüfung der finalen Task-Manager-E2E-Tests | Bestanden |
| Task-Manager-Web-Build mit E2E-Semantics | Bestanden; Build meldete zusätzlich einen Font-Family-Hinweis |
| Task-Manager-Widget- und Fake-/Real-Backend-Vertragstests | **46 bestanden**, keine Serverfälle übersprungen; eigener Server auf Port 5177 |
| Neun bestehende Task-Manager-Browserfälle | Alle im ersten Lauf bestanden |
| Neuer zusammenhängender Browserfall, korrigierter Eingabeweg | Separater gezielter Lauf bestanden, ohne Retry |
| Core-Publish-Dry-Run mit zusätzlicher Core-Testdatei | **0 Warnungen**, kein Upload |

Der neue Browserfall belegt in einem Ablauf: gemeinsames Cache-Lesen ohne
Detailrequest, optimistischen Rename vor Backend-Antwort, Bestätigung auf dem
Server, zweiten abgelehnten Rename mit Rollback, Übereinstimmung von Detail und
Liste, simulierte Verbindungsfehler beim Lesen mit genau einem Retry und
anschließende Recovery gegen den echten Backend-Prozess. Netzwerkmanager-
Pause/Resume wird separat im Core geprüft; der Browserfall simuliert
Transportfehler durch Request-Abbruch.

API-Docs, weitere SDK-/Binding-/Showcase-Kompatibilitätsprüfungen aus der
vorherigen Abnahme wurden nicht pauschal wiederholt. Vor den eigenen
Dokumentationsergänzungen stimmten alle 65 Dateien ihres lokalen Manifests
per SHA-256 überein. Die ausführbaren Bestandsquellen und Abhängigkeiten sind
weiter unverändert; die neu ergänzten Tests wurden wie oben geprüft.
Die lokalen Rohlogs sind in `core-confidence-results.json` mit Pfad und Hash
verzeichnet, aber nicht Teil des Repositorys. Committed werden können die
Tests, das Ergebnis und das Manifest; normale CI benötigt die Rohlogs nicht.

## Abschluss und verbleibende Grenzen

Die sechs vereinbarten Garantiegruppen sind bewertet, die ausgewählten
Ablaufprüfungen und der Consumer-Ablauf bestehen. Kein bestätigter erheblicher
Vertragsfehler blieb aus dieser Prüfung offen. Ein erneuter unspezifischer
Komplettreview ist daraus nicht begründet.

Nicht belegt sind exhaustive Ablaufabdeckung, Langzeit-/Heap-/Lastverhalten,
vollständige native Plattform- oder Wasm-Abdeckung und Fehlerfreiheit beliebiger
Nutzer-Callbacks. Die untere SDK-Linie wurde mit 3.6.2, nicht exakt 3.6.0 geprüft.
Bestehende Eingabegrenzen wie azyklische Keys und stabile Objektgleichheit gelten
weiter. Es wurde keine Remote-CI für diese Arbeitsbaumänderungen ausgeführt.

Der nächste Schritt ist die Integration dieser Tests mit CI am finalen Commit.
Der bestehende Real-Backend-E2E-Ablauf erbringt den geplanten Consumer-Nachweis;
zusätzlicher Praxiseinsatz kann weitere Datenmodelle und längere Nutzung
ergänzen, ist aber kein weiterer Pflichtschritt dieser Core-Abnahme.
Veröffentlichung und eine umfassende Abnahme des Flutter-Bindings bleiben
separate Entscheidungen. Neue konkrete Fehler
öffnen die betroffene Garantiegruppe erneut, nicht automatisch das ganze Projekt.
