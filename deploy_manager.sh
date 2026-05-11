#!/bin/bash
# Gestionnaire de déploiement de certificats Multi-Cibles
# Usage: ./deploy_manager.sh exemple.com

CONFIG_FILE="/root/certbot/config/domains.conf"
HOOK_SCRIPT="/root/certbot/hooks/hook_cloudflare.sh"
HOOK_SCRIPTCLEANUP="/root/certbot/hooks/hook_cloudflare_cleanup.sh"
DOMAIN="$1"

if [ -z "$DOMAIN" ]; then
    echo "Usage: $0 <domaine>"
    exit 1
fi

if ! grep -q "^$DOMAIN|" "$CONFIG_FILE"; then
    echo "Erreur : Domaine $DOMAIN introuvable dans la configuration."
    exit 1
fi

echo "========================================================"
echo " TRAITEMENT : $DOMAIN"
echo "========================================================"

# ------------------------------------------------------------------------------
# ÉTAPE 1 : Renouvellement du Certificat (Centralisé)
# ------------------------------------------------------------------------------
echo ">>> Vérification / Renouvellement avec Certbot..."

# --keep-until-expiring : Ne renouvelle que si nécessaire (ex: < 30 jours)
# Si le certificat est valide, Certbot ne lancera PAS le hook_cloudflare.sh
certbot certonly \
    --manual \
    --manual-auth-hook "$HOOK_SCRIPT" \
    --manual-cleanup-hook "$HOOK_SCRIPTCLEANUP" \
    --preferred-challenges dns \
    -d "$DOMAIN" -d "*.$DOMAIN" \
    --keep-until-expiring \
    --non-interactive \
    --agree-tos \
    --email "admin@$DOMAIN"

RET_CODE=$?
if [ $RET_CODE -ne 0 ]; then
    echo "ERREUR CRITIQUE : Échec de Certbot."
    exit 1
fi

LOCAL_CERT_PATH="/etc/letsencrypt/live/$DOMAIN"

# Vérification finale de présence
if [[ ! -f "$LOCAL_CERT_PATH/fullchain.pem" ]]; then
    echo "ERREUR : Fichiers de certificat introuvables."
    exit 1
fi

# ------------------------------------------------------------------------------
# ÉTAPE 2 : Déploiement Multi-Cibles (Boucle)
# ------------------------------------------------------------------------------
echo ">>> Démarrage de la séquence de déploiement..."

# On extrait toutes les lignes correspondant au domaine
grep "^$DOMAIN|" "$CONFIG_FILE" | while IFS='|' read -r _ _ _ SSH_TARGET SSH_KEY_PATH REMOTE_CERT_DIR REMOTE_CMD; do

    # Nettoyage des variables (trim)
    SSH_TARGET=$(echo "$SSH_TARGET" | xargs)
    REMOTE_CERT_DIR=$(echo "$REMOTE_CERT_DIR" | xargs)
    REMOTE_CMD=$(echo "$REMOTE_CMD" | xargs)
    SSH_KEY_PATH=$(echo "$SSH_KEY_PATH" | xargs)

    if [ -z "$SSH_TARGET" ]; then continue; fi

    echo " -> Cible : $SSH_TARGET"

    # Construction des arguments SSH
    SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -q"
    if [ -n "$SSH_KEY_PATH" ] && [ "$SSH_KEY_PATH" != "-" ]; then
        if [ ! -f "$SSH_KEY_PATH" ]; then
            echo "    [!] Clé SSH introuvable : $SSH_KEY_PATH. Saut de la cible."
            continue
        fi
        SSH_OPTS="$SSH_OPTS -i $SSH_KEY_PATH"
    fi

    # 1. Création répertoire distant
    # Utilisation de ssh -n pour éviter de casser la boucle while
    ssh -n $SSH_OPTS "$SSH_TARGET" "mkdir -p $REMOTE_CERT_DIR"
    if [ $? -ne 0 ]; then
        echo "    [ERREUR] Connexion impossible ou échec mkdir sur $SSH_TARGET"
        continue
    fi

    # 2. Transfert SCP
    scp $SSH_OPTS "$LOCAL_CERT_PATH/fullchain.pem" "$SSH_TARGET:$REMOTE_CERT_DIR/fullchain.pem"
    scp $SSH_OPTS "$LOCAL_CERT_PATH/privkey.pem" "$SSH_TARGET:$REMOTE_CERT_DIR/privkey.pem"

    if [ $? -eq 0 ]; then
        echo "    [OK] Fichiers transférés."
    else
        echo "    [ERREUR] Echec du transfert SCP."
        continue
    fi

    # 3. Exécution commande Post-Déploiement
    if [ -n "$REMOTE_CMD" ] && [ "$REMOTE_CMD" != "-" ]; then
        echo "    [CMD] Exécution : $REMOTE_CMD"
        # On se place dans le dossier avant d'exécuter
        ssh -n $SSH_OPTS "$SSH_TARGET" "cd $REMOTE_CERT_DIR && $REMOTE_CMD"
        if [ $? -eq 0 ]; then
             echo "    [OK] Commande exécutée avec succès."
        else
             echo "    [WARN] La commande distante a retourné une erreur."
        fi
    fi

done

echo ">>> Opérations terminées pour $DOMAIN."
