# Begrenzte Vertrauensprüfung des Core

Stand: 2026-09-12. Ausgangspunkt: `b1b476e5d99600d9791f0a30720d68a922208056`.
Status: **Begrenzte Prüfung abgeschlossen**. Entscheidung, Nachweise und Grenzen
stehen im [Ergebnisbericht](../research/core-confidence-assessment.md).

## Ziel und Grenze

Entscheiden, ob der vorhandene Pure-Dart-Core für einen begrenzten Praxiseinsatz
ausreichend abgesichert ist. Maßstab sind seine bestehenden öffentlichen
Verträge, nicht die Zahl der Findings eines weiteren allgemeinen Reviews.

Im Umfang: Cache-Identität und nullable Daten, Staleness und Invalidierung,
Fetch-Deduplizierung, Cancellation und Reset, Retry und Netzwerkwechsel,
Mutationen einschließlich Scope und Callbacks, Observer einschließlich Select,
Placeholder und Collections, Infinite Queries sowie Ressourcen-Lebensdauer.
Die bestehenden Entscheidungen in [ADR-0003](../adr/0003-core-operation-lifetimes.md)
und die dokumentierten Dart-Abweichungen bleiben die Ausgangsbasis.

Diese Prüfung führt keine neuen Funktionen, stärkeren Garantien oder
allgemeinen Refactorings ein. Sie zertifiziert weder das gesamte Flutter-Binding
noch sämtliche Beispiele und veröffentlicht kein Package. Bestehende Consumer
werden als Integrationsnachweis verwendet. Neue erhebliche Fehler im vereinbarten
Verhalten werden auch dann behoben, wenn ihr Auslöser selten ist.

## Vorhandene Nachweise

Die folgende Zuordnung hält den Ausgangspunkt vor der Prüfung fest. Die
abgeschlossene Bewertung der Assertions steht im Ergebnisbericht.
Testnamen mit historischen Fehlerbeschreibungen sind keine offenen Findings.
Die Dateien liegen unter [packages/query_kit/test](../../packages/query_kit/test/).

| Garantie | Vorhandene Nachweise | Noch zu bewerten |
| --- | --- | --- |
| Ein Fetch-Nachfolger behält Status, Daten und Signalnutzung; weitere Aufrufe deduplizieren | `release_query_regressions_test.dart`: QER3, QER8, QER13, QER15; Sharing-/Reset-Fälle in `release_transition_regressions_test.dart` | Abdeckung unterschiedlicher Abschlussreihenfolgen und wiederholter Wechsel |
| Gleicher Mutation-Scope serialisiert Transporte durch Abschluss-Callbacks; Aufrufzuordnung bleibt korrekt | `release_mutation_regressions_test.dart`: MU1, MU2, MU8, MU12; Scope-Fälle in `release_transition_regressions_test.dart` | Startreihenfolgen, Fehler, Pause/Resume und Entfernung in Kombination |
| Observer melden gültige Zustände und behalten aktuelle Aktionen; Select/Placeholder verändern keine fremden Daten | `release_observer_regressions_test.dart`: OI01–OI07, OI13–OI15; Preview-Fälle in `release_transition_regressions_test.dart` | Key-Wechsel, gleiche Werte, wiederholte Abonnements und Cache-Daten gemeinsam prüfen |
| Cancel, Unsubscribe und Clear erfüllen ihren jeweiligen Lebensdauervertrag | QER1, QER2, QER4, QER6, QER18; OI04, OI05, OI16–OI18; `port_lifecycle_test.dart` | Wiederholte Zyklen; keine verlorenen Registrierungen, internen Timer oder unzulässigen späteren Writes |
| Cache, Staleness, Retry und Netzwerkverhalten bleiben konsistent | Portierte Query-/Client-/Retryer-/Manager-Suiten; QER7, QER9–QER12, QER14, QER16, QER17; MU3, MU6, MU9 | Kernzusagen gegen konkrete Assertions zuordnen; nullable Daten und Options-Lebensdauer berücksichtigen |
| Infinite Queries behalten Seiten, Parameter und Fetch-Richtung bei Retry und Cancel | Portierte Infinite-Suiten; OI09–OI12 | Seitenfolge und Cache-Inhalt über die ausgewählten kombinierten Abläufe |

Weitere Ausgangsnachweise:

- [PORTING_NOTES](../../packages/query_kit/test/PORTING_NOTES.md): 409 portierte
  bzw. angepasste Fälle aus 535 Fällen der erfassten Upstream-Suiten, mit
  begründeten Auslassungen. Das ist keine vollständige Verhaltensgleichheit.
- In dieser Untersuchung bestanden 648 Core-Tests auf der VM am Ausgangsstand.
- Der vorhandene lokale Bericht unter
  `docs/reviews/2026-09-12-core/repair/ACCEPTANCE.md` dokumentiert weitere
  SDK-, Browser-, Consumer- und Verpackungsprüfungen. Diese sind historische
  Nachweise, keine in dieser Untersuchung erneut ausgeführten Checks. Das
  Verzeichnis ist gitignored; dauerhafte Nachweise müssen auf committed Tests
  oder CI-Ergebnisse zurückführbar sein.

## Vier Arbeitspakete, in dieser Reihenfolge

### 1. Vertrag und Testlücken abgleichen

Die sechs Tabellenzeilen gegen öffentliche Dokumentation und vorhandene
Assertions prüfen. Pro Zeile festhalten: vorhandener Nachweis, konkret fehlender
Nachweis oder widersprüchliche Zusage. Abweichungen vom Upstream als notwendige
Dart-Anpassung, bewusste Verhaltensänderung oder übernommenes Problem einordnen.
Kein Anspruch, jede historische Review-Notiz neu zu bewerten.

**Ergebnis:** eine endliche Liste ausgewählter Prüffälle mit vorab formulierter
Erwartung. Ein noch nicht bewerteter Nachweis ist nicht automatisch ein Bug.

### 2. Nur die ausgewählten Ablauf-Lücken prüfen

Bestehenden Test-Harness, kontrollierte Futures und virtuelle Zeit verwenden.
Fehlende Reihenfolgevarianten bevorzugt als kleine parametrisierte Tests ergänzen:
Query-Start/Cancel/Reset/Nachfolger/Settlement, Mutation-Start/Scope/Pause/Settlement
sowie Subscribe/Key-Wechsel/Unsubscribe/Clear. Nach Zwischenschritten prüfen,
nicht ausschließlich das Endergebnis. Wiederholte Zyklen auf Ressourcen prüfen.

Keine neue allgemeine Fuzzing-Infrastruktur. Falls generierte Reihenfolgen
helfen, bleiben sie begrenzt, deterministisch und mit ausgebbarer Aktionsfolge.
Die Erwartung stammt aus dem Vertrag, nicht aus dem aktuellen Implementationsergebnis.
Upstream-Vergleiche nur bei unklarer Herkunft oder zugesagter Gleichheit; bekannte
Upstream-Fehler sind kein Sollwert für unsere stärkeren bestehenden Garantien.

**Ergebnis:** reproduzierbare Tests und eine nach Ursache gebündelte Fehlerliste.
Jeder Fix braucht eine vorher fehlschlagende Reproduktion und eine gezielte
Gegenprüfung der betroffenen Übergänge. Bestehende Erwartungen werden nicht
nachträglich an die Implementierung angepasst.

### 3. Bestehenden Consumer als Integration prüfen

Die Task-Manager-Akzeptanztests und ihre Backend-/E2E-Prüfungen auf gemeinsame
Queries, optimistische Änderungen, Fehler/Rollback und Offline-/Online-Wechsel
zuordnen. Infinite/Pagination bei Bedarf aus dem vorhandenen Showcase belegen.
Einen zusammenhängenden Ablauf auswählen, der öffentliche APIs verwendet und
die fehlende Integrationsaussage tatsächlich prüft; vorhandene geeignete Fälle
wiederverwenden. Eine übersprungene Serverprüfung ist kein Real-Backend-Nachweis.

**Ergebnis:** ausgeführter Consumer-Ablauf mit Erwartungen und Resultaten;
verbleibende Plattform-/Integrationsgrenzen ausdrücklich benennen.

### 4. Einen finalen Stand abnehmen

Für den finalen Core-Stand die passenden Gates aus
[CI](../../.github/workflows/ci.yml) und ADR-0003 belegen: VM, kompiliertes
JavaScript, unterstützte SDK-Linie, Analyse, Format, Docs, Packaging und
Consumer-Kompatibilität. Bereits passende Nachweise wiederverwenden, wenn ihre
Quellen und der geprüfte Stand unverändert sind; nach relevanten Änderungen
betroffene Gates erneut ausführen. Remote-CI bleibt Teil des Releaseprozesses.

**Ergebnis:** eine Entscheidung mit geprüftem Commit/Dateistand, Ergebnissen,
offenen Risiken und verbleibenden Blockern. Lokale Abnahme ist keine Veröffentlichung.

## Umgang mit Findings und Abschluss

### Ausgewählte zusätzliche Ablaufprüfungen (vor Ausführung festgelegt)

1. Drei Query-Läufe desselben Keys, zwei Ablösungen durch Cancel oder Reset:
   alle sechs Abschlussreihenfolgen, alte Transporte jeweils erfolgreich oder
   fehlerhaft (24 Fälle). Nach jedem Abschluss muss allein der aktuelle Lauf
   Cache und Fetch-Status bestimmen; zusätzliche Aufrufer deduplizieren.
2. Drei Mutationen desselben Scopes in zwei Startreihenfolgen, mit Erfolg oder
   Fehler des ersten Besitzers (4 Fälle). Entfernung des aktiven Besitzers,
   Offline-Wechsel und verzögerte Settled-Callbacks dürfen die Wartenden weder
   parallel starten noch verlieren; Variablen und Context bleiben zugeordnet.
3. Wiederholte Placeholder-/Select-/Key-Wechsel und wiederholte Collection-
   Subscriptions mit gleichen Werten (2 Fälle, je 20 Zyklen). Rohdaten bleiben
   unverändert, Aktionen treffen den aktuellen Key, alte Unsubscribe-Handles
   stören keine neuen Registrierungen, Aufräumen lässt keine internen Timer.
4. Zwei Observer auf nullable Cache-Daten: Invalidierung offline, gemeinsamer
   Fetch, fehlgeschlagener Versuch und pausierter Retry, anschließend Recovery
   (1 Fall). Gecachtes null bleibt vorhandenes Datum; kein doppelter Transport.
5. Infinite-Refetch mit Seitenfortschritt, fehlgeschlagener Seite und offline
   pausiertem Retry; Cancel und anschließendes Load-more mit maxPages (1 Fall).
   Seiten und Parameter bleiben gepaart; der alte Retry wird nicht fortgesetzt.
6. Ein zusätzlicher zusammenhängender Task-Manager-Browserfall: gemeinsamer
   Cache, optimistischer Rename, abgelehnter Rename mit Rollback, nicht
   erreichbarer Backend-Lesezugriff und Recovery. Bestehende Helfer verwenden.

Das sind 32 zusätzliche Core-Fälle und ein Consumer-Fall. Zählwerte beschreiben
den gewählten Umfang, keine Fehlerfreiheitsquote. Neue Varianten kommen nur
hinzu, wenn ein konkreter Fehlschlag dies für seine Ursachenprüfung begründet.

Zur Einordnung des fehlgeschlagenen Browser-Eingabewegs kam eine gezielte
Widget-Gegenprobe zum zweiten Rename hinzu. Ergebnisse und die zwei korrigierten
Testentwürfe sind im Ergebnisbericht dokumentiert.

- Reproduzierbare Vertragsverletzung: Fehler mit Auslöser, Auswirkung und
  Regression erfassen. Falsche Daten, verlorene Operationen, Hänger oder
  erhebliche Ressourcenfehler verhindern die Abnahme.
- Unklare Zusage: vor einer Änderung entscheiden; keine stillschweigende
  Erweiterung des Funktionsumfangs. Ergebnis und Begründung dokumentieren.
- Funktionswunsch oder strukturelle Präferenz: separat festhalten, nicht in
  diese Abnahme aufnehmen.
- Jeder andere bestätigte Restfehler braucht eine ausdrückliche Bewertung
  seiner Auswirkung; Schweigen oder Zeitablauf sind keine Risikoakzeptanz.

Die Prüfung endet, wenn die sechs Garantiegruppen begründet bewertet, die
ausgewählten Ablauf- und Consumer-Prüfungen bestanden, die relevanten Gates
belegt und keine erheblichen Vertragsverletzungen offen sind. Eine rote
Prüfung öffnet das betroffene Arbeitspaket erneut, nicht automatisch ein
vollständiges Review des Repositorys. Der Real-Backend-E2E-Ablauf liefert den
geplanten Consumer-Nachweis. Zusätzlicher Praxiseinsatz ist optional und eröffnet
keine weitere Abnahmeschleife; die Abnahme behauptet keine Fehlerfreiheit.
