# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project vision

**klok** est une application Flutter (Dart) de pointage horaire pour les salariés d'un bar/restaurant, conçue pour tourner sur **une tablette unique** en mode kiosque. Le projet est désormais scaffoldé et fonctionnel : domaine, persistance, UI salarié + admin, export PDF paie, backup/restore.

IDE recommandé : Android Studio (plugins Flutter + Dart).

## Hard constraints (non-négociables)

Ces contraintes dictent presque toutes les décisions d'architecture et doivent être respectées strictement :

- **100% local, 100% offline pour les données.** Aucune base distante, aucun compte cloud, aucune synchronisation. Les données ne quittent jamais la tablette. Tout l'I/O sortant de données passe par le share sheet natif (`share_plus`), déclenché par le patron.
  - **Unique exception, strictement encadrée** : la vérification de mise à jour (`lib/services/update_service.dart`). Un `GET` sur un JSON statique, déclenché *uniquement* par le patron depuis Réglages → Vérifier. Rien n'est envoyé (pas d'identifiant d'appareil, pas de télémétrie), rien ne s'installe automatiquement, et un échec réseau est sans conséquence. C'est ce qui justifie la permission `INTERNET` du manifeste. Toute extension de cet usage réseau doit être discutée : la règle par défaut reste « pas de réseau ».
- **Cible : tablette Android, paysage.** Design tactile, zones de tap larges.
- **Deux personas, un appareil :**
  - *Salarié* : pointage (début/fin activité, début/fin pause). Parcours ultra-simple. Écran par défaut au lancement.
  - *Patron* : espace admin protégé par PIN (consultation horaires, indicateurs, export PDF, backup, réglages).
- **Aucune perte de données.** Chaque transition d'état est persistée immédiatement en DB (pas seulement à la fermeture). Un clock-in survit à un crash/redémarrage.
- **Export PDF paie** : un PDF par salarié sur une plage de dates, listant jours travaillés + heures nettes + total.
- **Backup/restore complet** par le patron dans un fichier unique portable (JSON), copiable sur Drive/USB et réimportable.
- **Distribution privée**, jamais sur le Play Store (voir *Distribution & updates*).

## Commands

```bash
flutter pub get                  # installer les dépendances
flutter run -d <device-id>       # lancer sur la tablette (flutter devices pour lister)
flutter test                     # tous les tests
flutter test test/widget_test.dart            # un fichier de test
flutter test --plain-name "session lifecycle" # un test par nom
flutter analyze                  # lint statique
dart format .                    # formatage
flutter build apk --release      # APK release pour installation tablette
flutter build apk --debug        # APK debug
flutter clean                    # purge build/ + .dart_tool (utile après conflit de cache)
```

**Codegen drift (obligatoire après modif du schéma DB).** Les tables sont déclarées dans `lib/data/db/tables.dart` et génèrent `lib/data/db/app_database.g.dart` (committé). Toute modification de `tables.dart` ou des `@DriftDatabase` exige de régénérer :

```bash
dart run build_runner build --delete-conflicting-outputs
```

## Architecture big-picture

Découpage en couches, du bas vers le haut :

**1. Persistance — `lib/data/`**
- `db/tables.dart` : 4 tables drift — `Employees`, `WorkSessions`, `Breaks` (FK cascade vers session), `AppSettings` (key/value). Une session ouverte = `endedAt == null` ; une pause ouverte = idem.
- `db/app_database.dart` : `AppDatabase` (drift), `schemaVersion = 1`, `PRAGMA foreign_keys = ON` au `beforeOpen`. `AppDatabase.forTesting(executor)` permet d'injecter une DB in-memory dans les tests.
- `repositories/` : `EmployeeRepository`, `SessionRepository`, `SettingsRepository`. **C'est ici que vivent les invariants métier, pas dans l'UI.** Ex. `SessionRepository.startSession` lève `StateError` si une session est déjà ouverte ; `endSession` ferme la pause ouverte dans la même transaction.

**2. State — `lib/state/`**
- `providers.dart` : tous les providers Riverpod (DB, repos, streams). Pattern central : les écrans `watch` des `StreamProvider` adossés aux requêtes drift `.watch()`, donc l'UI est réactive à la DB sans état dupliqué. `teamStatusProvider` agrège *2* streams (sessions ouvertes + pauses ouvertes) plutôt que N souscriptions par salarié.
- `admin_session.dart` : `adminUnlockedProvider` (bool) — état de déverrouillage admin en mémoire (re-verrouillé au redémarrage).
- `clockStateProvider` est un `StreamProvider.family<EmployeeClockState, int>` : l'état idle/working/onBreak d'un salarié donné.

**3. Routing — `lib/router.dart`**
- `go_router` avec un `redirect` qui sépare l'espace salarié (public) de l'espace admin (PIN). Si aucun PIN n'est défini → `/onboarding`. Tout `/admin/*` (sauf `/admin`, la gate) exige `adminUnlockedProvider == true`. Le routeur est rafraîchi via `ref.listen` sur `hasAdminPinProvider` et `adminUnlockedProvider` (sans recréer le `GoRouter`, pour préserver la pile).

**4. UI — `lib/features/`**
- `employee/` : `employee_select_screen` (accueil) → `clock_screen` → `confirm_screen`.
- `admin/` : `admin_gate_screen` (PIN) → `admin_home_screen` (tabs : `dashboard`, `team`, `export`, `backup`, `settings`).
- `onboarding/` : première install (création du PIN patron, nom établissement/patron).

**5. Services — `lib/services/`**
- `backup_service.dart` : `buildPayloadBytes()` sérialise tout (employees/sessions/breaks/settings) en JSON avec `checksum` SHA-256 et `formatVersion` — sans I/O, donc testable ; `exportAll()` l'écrit sur disque. `restore()` est un **remplacement total** transactionnel (delete-all puis réinsertion en préservant les IDs). Les FK restent **actives** : `PRAGMA foreign_keys` est un no-op à l'intérieur d'une transaction SQLite, donc l'intégrité repose sur l'ordre des opérations (suppression des feuilles vers la racine, réinsertion en sens inverse) et les FK servent de filet contre un backup incohérent. `inspect()` valide le checksum et renvoie un aperçu avant confirmation.
- `payroll_pdf_service.dart` : **le** service PDF paie actif (`PayrollData` / `generateAndShare`), utilisé par `export_tab`.

**6. Core — `lib/core/`**
- `time_math.dart` : calculs de durées. `SessionWithBreaks` expose `grossDuration`, `breakDuration`, `netDuration` (clampée à zéro si négative) et les anomalies (`hasNegativeDuration`, `isImplausiblyLong`, `isStaleOpenSession`, `hasBreakOverflow`, agrégées par `hasTimeAnomaly` et résumées par `anomalyLabel`). `groupByLocalDay` regroupe par jour **local** de début — une session à cheval sur minuit compte entièrement sur son jour de début (convention de paie, verrouillée par un test). Toujours calculer depuis les timestamps bruts, jamais depuis un cache.
- `backup_reminder.dart` : `BackupReminderFreq` (none/weekly/monthly) et `backupReminderStatus()` — alimente le bandeau d'alerte de la coquille admin.
- `version.dart` : `kAppVersion`, `kBackupFormatVersion`. **`kAppVersion` doit rester égal au `version:` de `pubspec.yaml`** — `test/version_test.dart` échoue sinon, parce que cette valeur est estampillée dans chaque backup.

**Fuseau horaire** : on **écrit** en UTC (`DateTime.now().toUtc()`), et on convertit en local à l'affichage. Attention : drift **relit** les `DateTime` en heure locale. L'instant absolu est préservé — donc durées et groupement par jour sont justes — mais le flag `isUtc` ne survit pas à un aller-retour en base. Dans les tests, comparer avec `.toUtc()` : `DateTime.==` compare aussi ce flag.

## Domain invariants (à faire respecter par le code, pas l'UI)

- Un salarié ne peut pas avoir deux sessions ouvertes simultanément (enforced dans `SessionRepository.startSession`).
- Une pause ne peut exister que dans une session ouverte ; fermer une session ferme la pause ouverte.
- Les heures exportées se calculent depuis les timestamps bruts (`time_math.dart`), jamais depuis un cache.
- Si l'horloge recule (durée brute négative), flagger l'anomalie (`hasTimeAnomaly`) plutôt que d'afficher une durée négative.
- Une session dépassant `kMaxPlausibleSessionDuration` (12 h) est signalée, jamais corrigée d'office : corriger sans trace fausserait la paie. L'historique salarié (`team_tab`) affiche un pictogramme d'alerte ; le patron tranche.
- Le PIN admin est dérivé en **PBKDF2-HMAC-SHA256** avec un sel `Random.secure()` (`SettingsKeys.pinAlgo` marque le schéma). Les installations créées avant ce changement utilisent `sha256(salt:pin)` et sont migrées de façon transparente au premier déverrouillage réussi — ne pas casser ce chemin de compatibilité. Une temporisation croissante et persistée s'active au-delà de `kPinFreeAttempts` échecs.

## Backup & restore

- **Format** : JSON unique avec `app`, `appVersion`, `schemaVersion`, `formatVersion`, `exportedAt`, `checksum: sha256:...`, et `data`. Le checksum couvre le sous-objet `data` sérialisé.
- **Restore** : remplacement total, prévisualisé (`inspect()` avant `restore()`), idempotent. Préserve les IDs.
- À chaque évolution de schéma DB **ou** de format de backup : bumper la version concernée et livrer une migration testée. Ne jamais casser la restauration d'un backup ancien.

## Distribution & updates

App privée, jamais sur store public. APK signé avec une keystore stable (à sauvegarder précieusement — sa perte interdit toute MAJ d'une installation existante). Pas d'auto-update silencieuse : le patron déclenche, télécharge et installe.

**Chaîne de livraison en place :**
1. Bumper `pubspec.yaml` *et* `lib/core/version.dart` (un test échoue s'ils divergent).
2. Mettre à jour `updates.json` à la racine (c'est lui que l'app interroge).
3. Taguer `vX.Y.Z` → le workflow `.github/workflows/release.yml` compile un APK signé (keystore dans les secrets GitHub) et publie une release. Le workflow refuse de tourner si le tag ne correspond pas au pubspec, ou si la keystore manque.
4. Le patron voit la MAJ via Réglages → Vérifier, et installe l'APK par-dessus (les données sont conservées).

**Secrets GitHub requis** : `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_PASSWORD`, `KEY_ALIAS`.

## Gotchas connus

- **`share_plus` est épinglé à `^12.0.2`** et ne peut **pas** monter en `13.x` : `share_plus 13.x` exige `win32 ^6.0.1`, incompatible avec `file_picker 11.x` (qui veut `win32 ^5.9.0`). Tant que `file_picker` ne lève pas cette contrainte, garder `share_plus 12.x`. Si le pub cache de `share_plus` se corrompt (erreurs Kotlin "Unresolved reference" sur des classes pourtant présentes du package), purger : `flutter clean` + supprimer `%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\share_plus-12.0.2\` + `flutter pub get`.
- **Un seul système de thème** : `lib/design/` (`buildKlokTheme()` + `KlokTokens` dans `tokens.dart`). L'ancien `lib/theme/` (`buildAppTheme()`, `AppColors`), jamais référencé, a été supprimé — de même que `lib/services/pdf_export_service.dart`. Ne pas les réintroduire.
- **`app_database.g.dart` est committé** — toujours régénérer après modif du schéma (voir *Commands*), sinon le code généré diverge des tables.
- **`android/key.properties` n'est pas versionné.** Sans lui, `flutter build apk --release` retombe sur les clés debug avec un avertissement Gradle : l'APK se construit mais ne doit pas être distribué. Voir le README.
- **`windows/` est conservé** comme cible de développement rapide (itérer sur l'UI sans tablette). Ce n'est pas une cible de production : seul Android est distribué.

## Things to avoid

- Pas d'auth cloud, de sync, ni de backup distant — même "au cas où". La contrainte offline est explicite.
- Ne pas surcharger l'UI salarié (pas de stats/historique/réglages côté salarié).
- Ne pas stocker les timestamps en string formatée — toujours `DateTime`/UTC en DB, formatage à l'affichage seulement.
- Ne pas dépendre de l'heure système sans garde-fou (flagger les anomalies).
- Ne pas casser la compat d'un backup existant (migration testée à chaque bump de schéma/format).
- Ne pas publier l'app sur un store public.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
