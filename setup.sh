#!/bin/bash

touch logs.txt
touch .env
exec > >(tee -a logs.txt) 2>&1

XRAY_MAJOR_VERSION=24

function outline_processing {
    CLOAK_SERVER_PORT=8443
    OUTLINE_API_PORT=8453
    OUTLINE_KEYS_PORT=8454
    CLOAK_SECRET=$(echo `head /dev/urandom | tr -dc A-Za-z0-9 | head -c40`)

    wget -O - https://raw.githubusercontent.com/Jigsaw-Code/outline-apps/master/server_manager/install_scripts/install_server.sh | sudo bash -s -- --hostname 127.0.0.1 --api-port $OUTLINE_API_PORT --keys-port $OUTLINE_KEYS_PORT

    docker ps --format "{{.Names}}" | sort | xargs --verbose --max-args=1 -- docker stop
    docker ps -a --format "{{.Names}}" | sort | xargs --verbose --max-args=1 -- docker rm

    # It extracts API_PREFIX from outline url string. It needs for starting shadowbox 
    OUTLINE_API_PREFIX=$(tac /opt/outline/access.txt | rev | grep '/' | cut -d'/' -f1 | rev)

    # It is needed for Cloak configuration and getting credentials
    docker run --rm -v $(pwd)/.env:/app/.env ghcr.io/dobbyvpn/dobbyvpn-server/cloak-server:v2 sh -c "
KEYPAIRS=\$(/app/ck-server -key)
cat << EOF >> /app/.env
CLOAK_PRIVATE_KEY=\$(echo \$KEYPAIRS | cut -d' ' -f13)
CLOAK_PUBLIC_KEY=\$(echo \$KEYPAIRS | cut -d' ' -f5)
CLOAK_USER_UID=\$(/app/ck-server -uid | cut -d' ' -f4)
CLOAK_ADMIN_UID=\$(/app/ck-server -uid | cut -d' ' -f4)
EOF"

# writing credentials to .env
cat << EOF >> ".env"
OUTLINE_API_PORT=${OUTLINE_API_PORT}
OUTLINE_KEYS_PORT=${OUTLINE_KEYS_PORT}
OUTLINE_API_PREFIX=${OUTLINE_API_PREFIX}
CLOAK_SERVER_PORT=${CLOAK_SERVER_PORT}
DOMAIN_NAME=${DOMAIN_NAME}
CLOAK_SECRET=${CLOAK_SECRET}
EOF

    set -a
    source .env
    set +a

    envsubst < cloak/cloak-server.conf > cloak/cloak-server.conf.tmp
    mv cloak/cloak-server.conf.tmp cloak/cloak-server.conf
}

function awg_config {
    touch awg/wg0.conf
cat << EOF >> ".env"
DOMAIN_NAME=${DOMAIN_NAME}
EOF

}


function xray_processing {
    XRAY_CLIENT_UUID=$(echo `uuidgen`)

    # It receives the latest version of 24.x.x
    XRAY_IMAGE_TAG=$(curl -s https://hub.docker.com/v2/repositories/teddysun/xray/tags | \
jq -r '.results[].name' | grep '^${XRAY_MAJOR_VERSION}\.' | sort -Vr | head -n 1)
	
    # certificate generation 
    wget -O -  https://get.acme.sh | sh
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    ~/.acme.sh/acme.sh --issue --server letsencrypt -d ${DOMAIN_NAME} --standalone --keylength ec-256

    cat << EOF >> ".env"
DOMAIN_NAME=${DOMAIN_NAME}
CERT_DIR=/root/.acme.sh/${DOMAIN_NAME}_ecc
XRAY_CLIENT_UUID=${XRAY_CLIENT_UUID}
XRAY_IMAGE_TAG=${XRAY_IMAGE_TAG}
EOF

    # it is needed for envsubst
    set -a
    source .env
    set +a

    envsubst < xray/config.json > xray/config.json.tmp
    mv xray/config.json.tmp xray/config.json

}

# Start main flow


echo "Disabling IPv6, as we don't use it"
cat <<EOF >> /etc/sysctl.d/99-no_ipv6.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
service procps force-reload

# Checking domain resolution
while true; do
    read -p "Enter a domain name: " DOMAIN_NAME

    if host "$DOMAIN_NAME" > /dev/null 2>&1; then
        echo "Domain name is valid."
        break
    else
        echo "Error: invalid or non-existent domain name! Please try again." >&2
    fi
done

echo "Choose VPN server to be installed:"
echo "1 - outline"
echo "2 - awg"
echo "3 - xray"
read -p "Your choice (1, 2 or 3): " user_choice

case "$user_choice" in
1)
    choice_number=1
    choice_name="outline"
    ;;
2)
    choice_number=2
    choice_name="awg"
    ;;
3)
    choice_number=3
    choice_name="xray"
    ;;
*)
    echo "ERROR: Wrong input. Try again!."
    get_choice # Recursion if wrong choice
    ;;
esac

mkdir caddy/config caddy/data

# acme.sh dependancy
apt install -y socat

# envsubst dependancy
apt install -y gettext

# for Json working
apt install -y jq

wget -O - https://get.docker.com | sudo bash 

if [ "$choice_number" -eq 1 ]; then
    outline_processing
elif [ "$choice_number" -eq 2 ]; then
    awg_config
elif [ "$choice_number" -eq 3 ]; then
    xray_processing
fi

echo "Starting docker compose..."
docker compose -f docker-compose.yaml --profile $choice_name up -d

echo "All logs have been saved in logs.txt"
