#!/usr/bin/env bash
# Génère android/key.properties à partir d'une keystore existante.
#
# Rien n'est codé en dur : l'alias est lu dans la keystore, le chemin est celui
# que tu donnes. Même logique que .github/workflows/release.yml, pour que le
# build local et celui de la CI ne puissent pas diverger.
#
#   ./tool/setup_signing.sh ~/klok-release.p12
#
# Le mot de passe est demandé sans être affiché, et n'est jamais passé en
# argument de ligne de commande (celle-ci est lisible par les autres processus).
set -euo pipefail

KEYSTORE="${1:-}"
if [ -z "$KEYSTORE" ]; then
  echo "Usage : $0 <chemin/vers/keystore.p12>" >&2
  exit 2
fi
if [ ! -f "$KEYSTORE" ]; then
  echo "Keystore introuvable : $KEYSTORE" >&2
  exit 1
fi

# Chemin absolu, avec des barres obliques normales : java.util.Properties
# traite l'antislash comme un caractère d'échappement, y compris sous Windows.
KEYSTORE_ABS=$(cd "$(dirname "$KEYSTORE")" && pwd)/$(basename "$KEYSTORE")
KEYSTORE_ABS=$(printf '%s' "$KEYSTORE_ABS" | sed 's#^/\([a-zA-Z]\)/#\1:/#')

read -r -s -p "Mot de passe de la keystore : " STORE_PASSWORD
echo

ALIAS=$(printf '%s\n' "$STORE_PASSWORD" \
  | keytool -list -keystore "$KEYSTORE_ABS" -storetype PKCS12 \
      -J-Duser.language=en 2>/dev/null \
  | grep -m1 'PrivateKeyEntry' \
  | cut -d',' -f1 \
  | tr -d '[:space:]')

if [ -z "$ALIAS" ]; then
  echo "Aucune clé privée lisible. Mot de passe erroné, ou keystore ne contenant qu'un certificat." >&2
  exit 1
fi

OUT="$(dirname "$0")/../android/key.properties"
{
  printf '# Généré par tool/setup_signing.sh — fichier local, gitignoré.\n'
  printf 'storePassword=%s\n' "$STORE_PASSWORD"
  printf 'keyPassword=%s\n' "$STORE_PASSWORD"
  printf 'keyAlias=%s\n' "$ALIAS"
  printf 'storeFile=%s\n' "$KEYSTORE_ABS"
} > "$OUT"

echo "android/key.properties écrit."
echo "  alias    : $ALIAS"
echo "  keystore : $KEYSTORE_ABS"
echo
echo "Vérifie que git l'ignore bien :  git check-ignore android/key.properties"
echo "Puis :                           flutter build apk --release"
