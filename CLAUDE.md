# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project vision

**klok** est une application Flutter de pointage horaire pour les salariés d'un bar/restaurant. Le repo est actuellement vide (greenfield) — seuls `LICENSE` et `README.md` existent. Toute contribution initiale implique donc de scaffolder le projet Flutter.

**Langage & IDE** : Flutter ⇒ code en **Dart**. IDE recommandé : **Android Studio** avec les plugins officiels *Flutter* et *Dart* (même workflow que pour une app Android native, mais tout le code applicatif est en Dart — pas de Kotlin/Java à écrire sauf extension plateforme ponctuelle).

## Hard constraints (non-négociables)

Ces contraintes dictent presque toutes les décisions d'architecture et doivent être respectées strictement :

- **100% local, 100% offline.** Aucune base de données distante, aucune API externe, aucun compte utilisateur cloud. Les données ne quittent jamais la tablette.
- **Cible principale : tablette** (probablement Android, format paysage). Le design doit être tactile, avec des zones de tap larges — un salarié en service ne doit pas galérer.
- **Deux personas sur le même appareil :**
  - *Salarié* : écran de pointage (début/fin d'activité, début/fin de pause). Parcours ultra-simple, sans formation.
  - *Patron* : écran admin protégé (PIN/mot de passe local) pour consulter les horaires, voir des indicateurs, et exporter en PDF.
- **Export PDF paie.** Le patron doit pouvoir générer un PDF par salarié sur une plage de dates (typiquement début-fin de mois) listant les jours travaillés, les heures par jour, et le total mensuel. Ce PDF part à la comptabilité/RH.
- **Aucune perte de données.** Un salarié qui clock-in doit pouvoir clock-out même après un redémarrage, une batterie vide, ou un crash de l'app. Les sessions en cours doivent être persistées à chaque transition d'état, pas seulement à la fermeture.
- **Backup/restore complet par le patron.** À tout moment, le patron doit pouvoir exporter *toutes* les données (salariés + sessions + pauses + réglages) dans un fichier unique (ex. ZIP ou JSON signé) qu'il peut copier sur Drive/clé USB. Le même fichier doit pouvoir être réimporté sur la même tablette ou une nouvelle pour restaurer l'état intégralement. C'est le seul filet de sécurité en cas de casse matérielle.
- **Distribution privée, jamais publiée sur le Play Store.** L'app est dédiée à un seul client ; elle ne doit pas apparaître dans un store public. Les mises à jour passent par un canal privé (voir section *Distribution & updates*).

## Suggested stack (à valider à la première implémentation)

Rien n'est encore figé. Ces choix sont cohérents avec les contraintes ci-dessus — si tu diverges, justifie pourquoi :

- **Persistance locale** : `drift` (SQLite typé) ou `isar` pour les données structurées (salariés, sessions, pauses). `shared_preferences` uniquement pour les réglages légers (PIN patron, préférences UI).
- **State management** : `riverpod` ou `bloc`. Éviter les solutions qui rendent difficile la persistance d'état (la reprise après crash est critique).
- **PDF** : package `pdf` + `printing` pour la prévisualisation/partage. Générer le PDF à partir des données locales, pas depuis un template externe.
- **Navigation** : `go_router` pour séparer clairement les routes salarié (publiques sur l'appareil) des routes patron (protégées par PIN).

## Architecture big-picture à prévoir

- **Domain model central** : `Employee`, `WorkSession` (start/end), `Break` (start/end, rattaché à une session). Une session ouverte = `endedAt == null`. Une pause ouverte = idem.
- **Invariants à faire respecter par le code, pas par l'UI** :
  - Un salarié ne peut pas avoir deux sessions ouvertes en même temps.
  - Une pause ne peut exister que dans une session ouverte.
  - Les heures exportées doivent être calculées à partir des timestamps bruts, pas d'un cache — la source de vérité reste la DB.
- **Séparation salarié/patron** : deux "shells" d'UI distincts. Le shell salarié est l'écran par défaut au lancement (mode kiosque souhaitable). L'accès patron est un geste/bouton discret + PIN.
- **Horaires & fuseau** : tout stocker en UTC en DB, afficher en local. La tablette peut être débranchée ou changer d'heure — utiliser un horodatage monotone si possible pour détecter les incohérences.

## Backup & restore

Fonctionnalité patron, critique — c'est le seul moyen de ne pas perdre plusieurs mois de pointage si la tablette casse.

- **Format** : un fichier unique portable. Options raisonnables : JSON pur (lisible, facile à differ), ou ZIP contenant JSON + éventuels assets. Inclure un champ `schemaVersion` en tête pour permettre les migrations au restore.
- **Contenu** : tous les `Employee`, `WorkSession`, `Break`, les réglages (PIN patron hashé, préférences), plus un `exportedAt` et la version de l'app. Ne pas inclure de données dérivées (totaux calculés) — elles seront recalculées.
- **Intégrité** : ajouter un checksum (SHA-256) du payload pour détecter les fichiers corrompus à l'import.
- **Partage** : utiliser `share_plus` pour déléguer le fichier à Drive, Gmail, clé USB, etc. — pas de upload direct depuis l'app (rappel : zéro réseau).
- **Restore** : doit être idempotent et prévisualisé. Afficher au patron ce qui va être écrasé/fusionné *avant* de confirmer. Stratégie par défaut : **remplacement total** (plus simple que merge) ; documenter clairement.
- **Backup régulier** : proposer un rappel périodique (hebdo/mensuel) au patron dans l'UI. Pas d'automatisation silencieuse — le patron doit explicitement faire l'action et choisir où déposer le fichier.

## Distribution & updates

App privée, pas de store public. L'objectif : que le patron (non-dev) puisse mettre à jour la tablette en quelques taps, sans que le dev ait à se déplacer.

- **Build** : APK signé avec une keystore stable (à générer une fois, à sauvegarder précieusement — perdre la keystore = ne plus pouvoir publier de mise à jour compatible). `flutter build apk --release`.
- **Canal de distribution privé** : options simples, par ordre de préférence :
  1. **Firebase App Distribution** (gratuit, privé par invitation, notif dans l'app compagnon) — recommandé si connexion Wi-Fi disponible ponctuellement pour installer la MAJ.
  2. **Lien direct vers APK** hébergé sur un stockage privé (Drive partagé, S3, serveur perso) + petit écran "Vérifier les mises à jour" côté patron qui télécharge et déclenche l'install.
  3. **APK transféré manuellement** (clé USB, mail) — fallback ultime, toujours supporté.
- **Pas d'auto-update silencieuse.** Android bloque de toute façon les install APK sans interaction utilisateur hors Play Store. Concevoir un flux "une MAJ est disponible — installer ?" déclenché par le patron.
- **Compatibilité des données entre versions** : à chaque bump de `schemaVersion` (DB ou fichier de backup), écrire une **migration** testée. Un patron qui met à jour après 6 mois doit retrouver toutes ses données — c'est non-négociable. Garder les migrations additives tant que possible.
- **Versionning** : `pubspec.yaml` ⇒ `version: X.Y.Z+buildNumber`. Afficher la version dans l'écran patron (utile pour le support).

## Commands (une fois le projet Flutter scaffoldé)

```bash
flutter create .                 # scaffold initial dans ce dossier (à faire 1 fois)
flutter pub get                  # installer les dépendances
flutter run -d <device-id>       # lancer sur la tablette connectée
flutter test                     # lancer tous les tests
flutter test test/foo_test.dart  # un seul fichier de test
flutter analyze                  # lint statique (dart analyzer)
dart format .                    # formater le code
flutter build apk --release      # build APK pour installation tablette
```

Pour lister les devices : `flutter devices`.

## Things to avoid

- **Ne pas ajouter d'auth cloud, de sync, ou de backup distant** — même "au cas où". La contrainte offline est explicite et le patron ne veut pas que les données sortent de la tablette.
- **Ne pas surcharger l'UI salarié.** L'écran de pointage doit faire *une* chose bien. Pas de stats, pas d'historique, pas de paramètres — ça c'est côté patron.
- **Ne pas stocker les timestamps en string formatée.** Toujours en `DateTime`/ISO-8601 en DB, formatage uniquement à l'affichage.
- **Ne pas dépendre de l'heure système sans garde-fou.** Si l'horloge recule ou avance brutalement entre un start et un end, flagger l'anomalie au patron plutôt que de calculer une durée négative.
- **Ne pas casser la compat d'un backup existant.** Toute évolution de schéma (DB ou fichier exporté) doit livrer une migration testée. Un patron doit pouvoir restaurer un backup vieux de plusieurs versions sans perdre ses données.
- **Ne pas publier l'app sur un store public.** Distribution privée uniquement (voir *Distribution & updates*).
