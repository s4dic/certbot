#!/bin/bash
# Hook pour validation DNS-01 Cloudflare via Certbot
set -e

CONFIG_FILE="/root/certbot/config/domains.conf"

# Vérification des variables Certbot
if [[ -z "$CERTBOT_DOMAIN" || -z "$CERTBOT_VALIDATION" ]]; then
    echo "Erreur : Ce script doit être exécuté par Certbot."
    exit 1
fi

# 1. Extraction de la ligne de configuration contenant les Secrets
# On cherche le domaine, et on exclut les lignes où le token est "-" ou vide
LINE=$(grep "^$CERTBOT_DOMAIN|" "$CONFIG_FILE" | grep -v "|-|" | head -n 1)

if [ -z "$LINE" ]; then
    echo "Erreur : Aucune configuration valide (avec Token) trouvée pour $CERTBOT_DOMAIN dans $CONFIG_FILE"
    exit 1
fi

IFS='|' read -r _ ZONE_ID API_TOKEN _ _ _ _ <<< "$LINE"

# Nettoyage variables
ZONE_ID=$(echo "$ZONE_ID" | xargs)
API_TOKEN=$(echo "$API_TOKEN" | xargs)

RECORD_NAME="_acme-challenge.$CERTBOT_DOMAIN"

# 2. Nettoyage préventif (suppression ancien record TXT)
EXISTING_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=TXT&name=$RECORD_NAME" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" | jq -r '.result[0].id')

if [ "$EXISTING_ID" != "null" ] && [ -n "$EXISTING_ID" ]; then
  curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$EXISTING_ID" \
    -H "Authorization: Bearer $API_TOKEN" \
    -H "Content-Type: application/json" > /dev/null
fi

# 3. Ajout du challenge DNS
RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
     -H "Authorization: Bearer $API_TOKEN" \
     -H "Content-Type: application/json" \
     --data '{"type":"TXT","name":"'"$RECORD_NAME"'","content":"'"$CERTBOT_VALIDATION"'","ttl":120,"proxied":false}')

if echo "$RESPONSE" | grep -q '"success":true'; then
    echo "Challenge DNS ajouté pour $CERTBOT_DOMAIN."
    # Petit délai de propagation de sécurité
    sleep 20
else
    echo "Erreur API Cloudflare : $RESPONSE"
    exit 1
fi
