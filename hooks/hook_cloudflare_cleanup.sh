#!/bin/bash
set -e

CONFIG_FILE="/root/certbot/config/domains.conf"

if [[ -z "$CERTBOT_DOMAIN" ]]; then exit 1; fi

LINE=$(grep "^$CERTBOT_DOMAIN|" "$CONFIG_FILE" | grep -v "|-|" | head -n 1)
IFS='|' read -r _ ZONE_ID API_TOKEN _ _ _ _ <<< "$LINE"
ZONE_ID=$(echo "$ZONE_ID" | xargs)
API_TOKEN=$(echo "$API_TOKEN" | xargs)

RECORD_NAME="_acme-challenge.$CERTBOT_DOMAIN"

# Supprimer TOUS les TXT _acme-challenge
IDS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=TXT&name=$RECORD_NAME" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" | jq -r '.result[].id')

for ID in $IDS; do
    curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$ID" \
      -H "Authorization: Bearer $API_TOKEN" \
      -H "Content-Type: application/json" > /dev/null
done
