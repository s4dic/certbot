#!/bin/bash
# Hook pour validation DNS-01 Cloudflare via Certbot
set -e

CONFIG_FILE="/root/certbot/config/domains.conf"

if [[ -z "$CERTBOT_DOMAIN" || -z "$CERTBOT_VALIDATION" ]]; then
    echo "Erreur : Ce script doit être exécuté par Certbot."
    exit 1
fi

LINE=$(grep "^$CERTBOT_DOMAIN|" "$CONFIG_FILE" | grep -v "|-|" | head -n 1)

if [ -z "$LINE" ]; then
    echo "Erreur : Aucune configuration valide trouvée pour $CERTBOT_DOMAIN"
    exit 1
fi

IFS='|' read -r _ ZONE_ID API_TOKEN _ _ _ _ <<< "$LINE"
ZONE_ID=$(echo "$ZONE_ID" | xargs)
API_TOKEN=$(echo "$API_TOKEN" | xargs)

RECORD_NAME="_acme-challenge.$CERTBOT_DOMAIN"

# NE PAS supprimer les records existants — on AJOUTE directement
RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
     -H "Authorization: Bearer $API_TOKEN" \
     -H "Content-Type: application/json" \
     --data '{"type":"TXT","name":"'"$RECORD_NAME"'","content":"'"$CERTBOT_VALIDATION"'","ttl":120,"proxied":false}')

if echo "$RESPONSE" | grep -q '"success":true'; then
    echo "Challenge DNS ajouté pour $CERTBOT_DOMAIN."
    sleep 25
else
    echo "Erreur API Cloudflare : $RESPONSE"
    exit 1
fi
