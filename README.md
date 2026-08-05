# klok

Pointage horaire pour bars & restaurants — 100 % local, hors-ligne, sans compte. 🍸

Klok tourne sur **une tablette Android unique**, posée en mode kiosque sur le
comptoir. Les salariés pointent leurs arrivées, pauses et départs ; le patron
consulte les heures, exporte des fiches de paie PDF et sauvegarde les données —
le tout sans qu'aucune donnée ne quitte la tablette.

## Deux usages, un appareil

| | Salarié | Patron |
|---|---|---|
| Accès | écran d'accueil, aucun code | espace admin protégé par PIN à 8 chiffres |
| Actions | début/fin d'activité, début/fin de pause | horaires, indicateurs, export PDF, sauvegarde, réglages |

## Principes non négociables

- **Aucun réseau pour les données.** Pas de base distante, pas de compte cloud,
  pas de synchronisation. Les fichiers sortent uniquement via le partage natif
  Android, à la demande du patron.
- **Aucune perte de données.** Chaque transition d'état est écrite en base
  immédiatement : un pointage survit à un crash ou à une coupure de courant.
- **Les heures se recalculent toujours** depuis les horodatages bruts, jamais
  depuis un total mis en cache.
- **Distribution privée.** Jamais publiée sur un store public.

## Démarrer

```bash
flutter pub get
flutter devices                  # repérer l'identifiant de la tablette
flutter run -d <device-id>
```

## Développement

```bash
flutter test                     # suite complète
flutter analyze                  # lint statique
dart format .                    # formatage
```

Après toute modification du schéma de base (`lib/data/db/tables.dart`), il faut
régénérer le code drift, qui est committé :

```bash
dart run build_runner build --delete-conflicting-outputs
```

## Compiler une version distribuable

L'APK de production doit être signé avec une **keystore stable**. Android refuse
d'installer une mise à jour dont la signature diffère de celle déjà en place :
perdre cette keystore, c'est condamner le patron à désinstaller l'app — et donc
à perdre ses données — pour passer à la version suivante.

1. Générer la keystore, **une seule fois**, au format PKCS12 :

   ```bash
   keytool -genkeypair -v -keystore ~/klok-release.p12 \
     -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 -alias klok
   ```

   PKCS12 et non JKS : ce dernier est un format propriétaire déprécié, sur
   lequel `keytool` émet un avertissement. Si une keystore JKS existe déjà, la
   **migrer** plutôt qu'en recréer une — l'app doit conserver la même clé de
   signature pour rester mettable à jour :

   ```bash
   keytool -importkeystore -srckeystore klok-release.jks \
     -destkeystore klok-release.p12 -deststoretype pkcs12
   ```

2. La sauvegarder hors du dépôt (gestionnaire de mots de passe ou disque
   chiffré).

3. Copier `android/key.properties.example` en `android/key.properties` et le
   remplir. Ce fichier est ignoré par git et ne doit jamais être committé.

4. Compiler :

   ```bash
   flutter build apk --release
   ```

Sans `key.properties`, la compilation retombe sur les clés de debug et affiche
un avertissement : pratique en local, **à ne pas distribuer**.

## Versionner une livraison

`pubspec.yaml` (`version: X.Y.Z+build`) et `lib/core/version.dart` doivent être
bumpés ensemble — un test échoue s'ils divergent, car la version est estampillée
dans chaque fichier de sauvegarde.

## Sauvegarde & restauration

Le patron exporte un fichier JSON unique contenant l'intégralité des données,
protégé par une somme de contrôle SHA-256. La restauration remplace la totalité
de la base, en une transaction, après un aperçu du contenu. Les identifiants
sont préservés et l'opération est rejouable sans effet de bord.

Toute évolution du schéma ou du format doit s'accompagner d'une migration
testée : un fichier de sauvegarde ancien doit rester restaurable.

## Architecture

```
lib/
├── core/        calculs de durées, rappel de sauvegarde, version
├── data/        tables drift + dépôts (les invariants métier vivent ici)
├── state/       providers Riverpod adossés aux streams drift
├── design/      thème et jetons visuels
├── features/    écrans salarié, admin et intégration initiale
└── services/    sauvegarde, génération PDF
```

Les horodatages sont écrits en UTC et convertis à l'affichage seulement. Les
règles métier — pas de double session ouverte, fermeture de la pause en cours
avec la session — sont appliquées dans les dépôts, jamais dans l'interface.

Voir [CLAUDE.md](CLAUDE.md) pour le détail des conventions.

## Licence

Voir [LICENSE](LICENSE).
