#!/bin/bash

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

# Force system time to UTC
sudo timedatectl set-timezone UTC

# Update and Upgrade the System
sudo apt-get update
sudo apt-get upgrade -y

# Load configuration file
source wg-easy-config.env

# Ensure the config file is loaded correctly
if [ -z "$HOST" ] || [ -z "$WG_ADMIN_PASSWORD" ]; then
    echo "Error: Configuration parameters are missing. Please check wg-easy-config.env."
    exit 1
fi

# Step 1: Install Docker and Docker Compose
install_docker() {
    echo "Installing Docker and Docker Compose..." | tee -a setup.log

    # Remove any old Docker versions
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
        sudo apt-get remove -y $pkg
    done

    # Install Docker
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Enable Docker service
    sudo systemctl enable docker

    # Check if Docker was installed successfully
    if ! command -v docker &> /dev/null; then
        echo "Docker installation failed. Exiting." | tee -a setup.log
        exit 1
    fi
}

# Step 2: Generate Password Hash
generate_password_hash() {
    echo "Generating password hash..." | tee -a setup.log
    PASSWORD_HASH=$(docker run --rm ghcr.io/wg-easy/wg-easy wgpw "$WG_ADMIN_PASSWORD" | tr -d '\r')
    
    # Check if password hash generation was successful
    if [ -z "$PASSWORD_HASH" ]; then
        echo "Password hash generation failed. Exiting." | tee -a setup.log
        exit 1
    fi

    # Escape dollar signs for YAML compatibility
    PASSWORD_HASH=${PASSWORD_HASH//\$/\$\$}
}

# Step 3: Create docker-compose.yml
generate_docker_compose() {
    echo "Creating docker-compose.yml..." | tee -a setup.log
    cat <<EOF > docker-compose.yml
version: '3'
volumes:
  etc_wireguard:

services:
  wg-easy:
    environment:
      - LANG=en
      - WG_HOST=$HOST
      - PASSWORD_HASH=$PASSWORD_HASH
      $(if [ "$ENABLE_PROMETHEUS_METRICS" = "true" ]; then
        echo "- ENABLE_PROMETHEUS_METRICS=true"
        echo "- PROMETHEUS_METRICS_PASSWORD=$PASSWORD_HASH"
      fi)
    image: ghcr.io/wg-easy/wg-easy
    container_name: wg-easy
    volumes:
      - etc_wireguard:/etc/wireguard
    ports:
      - "51820:51820/udp"
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1

  nginx:
    image: weejewel/nginx-with-certbot
    container_name: nginx
    hostname: nginx
    volumes:
      - ~/.nginx/servers/:/etc/nginx/servers/
      - ./.nginx/letsencrypt/:/etc/letsencrypt/
    ports:
      - "80:80/tcp"
      - "443:443/tcp"
    restart: unless-stopped
EOF
}

# Step 4: Create NGINX Configuration
setup_nginx_config() {
    echo "Setting up NGINX configuration..." | tee -a setup.log
    mkdir -p ~/.nginx/servers/
    cat <<EOF > ~/.nginx/servers/wg-easy.conf
server {
    server_name $HOST;

    location / {
        proxy_pass http://wg-easy:51821/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
    }
}
EOF
}

# Step 5: Start Docker Compose
start_docker_compose() {
    echo "Starting Docker Compose..." | tee -a setup.log
    docker-compose up --detach

    # Verify Docker Compose status
    if ! docker-compose ps | grep -q 'Up'; then
        echo "Docker Compose failed to start the containers. Exiting." | tee -a setup.log
        exit 1
    fi
}

# Step 6: Obtain SSL Certificate using Certbot
setup_ssl_certificate() {
    echo "Setting up SSL certificate..." | tee -a setup.log
    docker exec -it nginx sh -c "cp /etc/nginx/servers/wg-easy.conf /etc/nginx/conf.d/ && \
    certbot --nginx --non-interactive --agree-tos -m webmaster@google.com -d $HOST && \
    nginx -s reload"
}

# Step 7: Configure Firewall
configure_firewall() {
    echo "Configuring firewall..." | tee -a setup.log
    sudo apt update
    sudo apt install -y ufw
    sudo ufw reset
    sudo ufw default deny incoming
    sudo ufw allow 22/tcp
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw allow 51820/udp
    sudo ufw enable
}

# Step 8: Configure Cron Jobs
setup_cron_jobs() {
    echo "Configuring cron jobs..." | tee -a setup.log

    # Reboot cron job
    if [ "$ENABLE_REBOOT_CRON" = "true" ]; then
        sudo crontab -l | { cat; echo "0 ${REBOOT_TIME%:*} * * * /sbin/reboot"; } | sudo crontab -
    fi

    # Update cron job
    if [ "$ENABLE_UPDATE_CRON" = "true" ]; then
        sudo crontab -l | { cat; echo "0 ${UPDATE_TIME%:*} ${UPDATE_DAY_OF_MONTH} * * /bin/bash ~/update-wg-easy.sh"; } | sudo crontab -
    fi
}

# Step 9: Cleanup
cleanup() {
    echo "Cleaning up sensitive information..." | tee -a setup.log

    # Unset WG_ADMIN_PASSWORD variable in the current session
    unset WG_ADMIN_PASSWORD

    # Create a temporary file
    temp_file=$(mktemp)
    trap 'rm -f "$temp_file"' EXIT

    # Copy all lines except WG_ADMIN_PASSWORD from wg-easy-config.env to the temporary file
    while IFS= read -r line; do
        if [[ $line != WG_ADMIN_PASSWORD=* ]]; then
            echo "$line" >> "$temp_file"
        else
            echo "WG_ADMIN_PASSWORD="
        fi
    done < wg-easy-config.env

    # Replace the original configuration file with the temporary file
    mv "$temp_file" wg-easy-config.env

    echo "Admin password has been removed from the configuration file."
}

# Run all setup steps
install_docker
generate_password_hash
generate_docker_compose
setup_nginx_config
start_docker_compose
setup_ssl_certificate
configure_firewall
setup_cron_jobs
cleanup

echo "wg-easy setup is complete!"
