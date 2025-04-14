#!/bin/bash
clear

RED="\033[0;31m"
GREEN="\033[0;32m"
CYAN="\033[0;36m"
YELLOW="\033[1;33m"
BOLD="\033[1m"
RESET="\033[0m"

STATE_FILE="/tmp/dezerx_install_state.json"

check_root() {
  if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}Error: This script must be run as root${RESET}"
    exit 1
  fi
}

check_command() {
  if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Command failed: $1${RESET}"
    return 1
  fi
  return 0
}

run_quietly() {
  "$@" > /dev/null 2>&1
  local status=$?
  if [ $status -ne 0 ]; then
    echo -e "${YELLOW}⚠️ Command had non-zero exit: $1${RESET}"
    return $status
  fi
  return 0
}

run_with_retry() {
  local cmd="$1"
  local max_attempts=${2:-3}
  local attempts=0
  local status=1
  
  while [ $attempts -lt $max_attempts ] && [ $status -ne 0 ]; do
    ((attempts++))
    echo -e "${CYAN}⚙️ Running command (attempt $attempts/$max_attempts): $cmd${RESET}"
    eval "$cmd" > /dev/null 2>&1
    status=$?
    
    if [ $status -ne 0 ] && [ $attempts -lt $max_attempts ]; then
      echo -e "${YELLOW}⚠️ Command failed, retrying in 3 seconds...${RESET}"
      sleep 3
    fi
  done
  
  if [ $status -ne 0 ]; then
    echo -e "${RED}❌ Command failed after $max_attempts attempts: $cmd${RESET}"
    return $status
  fi
  
  return 0
}

step_completed() {
  local step=$1
  
  if [ -f "$STATE_FILE" ]; then
    grep -q "\"$step\":true" "$STATE_FILE" && return 0
  fi
  
  return 1
}

mark_step_completed() {
  local step=$1
  
  if [ ! -f "$STATE_FILE" ]; then
    echo "{}" > "$STATE_FILE"
  fi
  
  local TEMP_FILE=$(mktemp)
  if command -v jq &> /dev/null; then
    jq ".$step = true" "$STATE_FILE" > "$TEMP_FILE"
  else
    grep -q "{}" "$STATE_FILE" && sed -i "s/{}/{\"$step\":true}/g" "$STATE_FILE" > "$TEMP_FILE" || \
    sed -i "s/{/{\"$step\":true,/g" "$STATE_FILE" > "$TEMP_FILE"
  fi
  
  if [ -s "$TEMP_FILE" ]; then
    mv "$TEMP_FILE" "$STATE_FILE"
  else
    echo -e "${YELLOW}⚠️ Warning: Failed to update state file. Continuing anyway.${RESET}"
    rm -f "$TEMP_FILE"
  fi
}

display_logo() {
  echo -e "${CYAN}"
  cat <<'EOF'
  ██████╗ ███████╗███████╗███████╗██████╗ ██╗  ██╗
  ██╔══██╗██╔════╝╚══███╔╝██╔════╝██╔══██╗╚██╗██╔╝
  ██║  ██║█████╗    ███╔╝ █████╗  ██████╔╝ ╚███╔╝ 
  ██║  ██║██╔══╝   ███╔╝  ██╔══╝  ██╔══██╗ ██╔██╗ 
  ██████╔╝███████╗███████╗███████╗██║  ██║██╔╝ ██╗
  ╚═════╝ ╚══════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝
EOF
 echo -e "${RESET}"
 echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
 echo -e "${BOLD}${MAGENTA}🚀 Welcome to the DezerX Installer${RESET} ${YELLOW}v1.0.1e-alpha${RESET}"
 echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

 echo -e "${BOLD}${BLUE}🔗 Discord:${RESET} ${WHITE}https://discord.gg/UN4VVc2hWJ${RESET}"
 echo -e "${BOLD}${BLUE}🌐 Website:${RESET} ${WHITE}https://dezerx.com${RESET}"
 echo -e "${BOLD}${RED}🐞 Version:${RESET} ${WHITE}v1.0.1e-alpha — Please report any bugs you encounter!${RESET}"

}

check_prerequisites() {
  echo -e "\n${BOLD}${YELLOW}==========[ Checking Prerequisites ]==========${RESET}"
  
  for cmd in curl apt-get; do
    if ! command -v $cmd &> /dev/null; then
      echo -e "${RED}❌ $cmd is required but not installed.${RESET}"
      exit 1
    fi
  done
  
  echo -e "${GREEN}✅ Prerequisites satisfied.${RESET}"
}

check_existing_installation() {
  if [ -f "$STATE_FILE" ]; then
    cat "$STATE_FILE"
    rm -f "$STATE_FILE"
  fi
}

verify_license() {
  echo -e "\n${BOLD}${YELLOW}==========[ License Verification ]==========${RESET}"

  read -p "Enter your license key: " LICENSE_KEY
  read -p "Enter your domain (must point to this server): " DOMAIN
  
  CLEAN_DOMAIN=$(echo "$DOMAIN" | sed -e 's|^https\?://||' -e 's|/.*$||')
  export CLEAN_DOMAIN

  echo -e "\n${CYAN}🔍 Verifying license...${RESET}"
  
  if ! curl -s --head https://license-check.dezerx.com > /dev/null; then
    echo -e "${RED}❌ Cannot reach license verification server.${RESET}"
    exit 1
  fi
  
  VERIFY_RESPONSE=$(curl -s -X POST "https://license-check.dezerx.com/api/verify-license" \
    -H "Content-Type: application/json" \
    -d "{\"domain_or_subdomain\":\"$DOMAIN\", \"license_key\":\"$LICENSE_KEY\"}")

  if command -v jq &> /dev/null; then
    if [[ "$VERIFY_RESPONSE" == *'"verify":false'* ]]; then
      echo -e "${RED}❌ License verification failed: $(echo $VERIFY_RESPONSE | jq -r '.message')${RESET}"
      exit 1
    fi
  else
    if [[ "$VERIFY_RESPONSE" == *'"verify":false'* ]]; then
      echo -e "${RED}❌ License verification failed. Please check your license key and domain.${RESET}"
      exit 1
    fi
  fi
  
  echo -e "${GREEN}✅ License verified successfully.${RESET}"
  export LICENSE_KEY
  mark_step_completed "license_verified"
}

install_dependencies() {
  echo -e "\n${BOLD}${YELLOW}==========[ Installing Dependencies ]==========${RESET}"
  
  if step_completed "dependencies_installed"; then
    echo -e "${GREEN}✅ Dependencies already installed. Skipping...${RESET}"
    return 0
  fi

  echo -e "${CYAN}⚙️ Installing system packages...${RESET}"

  apt-get update -qq || {
    echo -e "${YELLOW}⚠️ Warning: apt-get update had issues but continuing...${RESET}"
  }

  echo -e "${CYAN}⚙️ Installing essential packages...${RESET}"
  apt-get install -y -qq software-properties-common curl apt-transport-https ca-certificates gnupg || {
    echo -e "${RED}❌ Failed to install essential packages. Trying individual installation...${RESET}"
    for pkg in software-properties-common curl apt-transport-https ca-certificates gnupg; do
      echo -e "${CYAN}⚙️ Installing $pkg...${RESET}"
      apt-get install -y -qq "$pkg" || echo -e "${YELLOW}⚠️ Failed to install $pkg, continuing anyway...${RESET}"
    done
  }

  apt-get install -y -qq jq || echo -e "${YELLOW}⚠️ Failed to install jq, continuing anyway...${RESET}"

  echo -e "${CYAN}⚙️ Setting up repositories...${RESET}"
  
  echo -e "${CYAN}⚙️ Adding PHP repository...${RESET}"
  LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php > /dev/null 2>&1 || {
    echo -e "${YELLOW}⚠️ Failed to add PHP repository. Trying alternative method...${RESET}"
    echo "deb http://ppa.launchpad.net/ondrej/php/ubuntu $(lsb_release -cs) main" > /etc/apt/sources.list.d/ondrej-php.list
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 4F4EA0AAE5267A6C > /dev/null 2>&1
  }

  echo -e "${CYAN}⚙️ Adding Redis repository...${RESET}"
  rm -f /usr/share/keyrings/redis-archive-keyring.gpg
  curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg || {
    echo -e "${YELLOW}⚠️ Failed to add Redis repository key. Trying alternative method...${RESET}"
    curl -fsSL https://packages.redis.io/gpg | apt-key add - > /dev/null 2>&1
  }
  echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" > /etc/apt/sources.list.d/redis.list

  echo -e "${CYAN}⚙️ Adding MariaDB repository...${RESET}"
  apt-key adv --fetch-keys 'https://mariadb.org/mariadb_release_signing_key.asc' > /dev/null 2>&1 || {
    echo -e "${YELLOW}⚠️ Failed to add MariaDB key. Trying alternative method...${RESET}"
    curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash
  }

  DISTRO_CODENAME=$(lsb_release -cs)
  echo "deb [arch=amd64] https://mirror.rackspace.com/mariadb/repo/10.6/ubuntu $DISTRO_CODENAME main" > /etc/apt/sources.list.d/mariadb.list

  echo -e "${CYAN}⚙️ Adding NodeJS repository...${RESET}"
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1 || {
    echo -e "${YELLOW}⚠️ Failed to set up NodeJS repository. Trying alternative method...${RESET}"
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add - > /dev/null 2>&1
    echo "deb https://deb.nodesource.com/node_20.x $(lsb_release -cs) main" > /etc/apt/sources.list.d/nodesource.list
  }

  echo -e "${CYAN}⚙️ Updating package lists...${RESET}"
  apt-get update -qq || {
    echo -e "${YELLOW}⚠️ Warning: apt-get update had issues but continuing...${RESET}"
  }

  echo -e "${CYAN}⚙️ Installing PHP packages...${RESET}"
  apt-get install -y -qq php8.3 php8.3-common php8.3-cli php8.3-gd php8.3-mysql php8.3-mbstring || {
    echo -e "${YELLOW}⚠️ Some PHP packages failed. Trying individually...${RESET}"
    for pkg in php8.3 php8.3-common php8.3-cli php8.3-gd php8.3-mysql php8.3-mbstring; do
      apt-get install -y -qq "$pkg" || echo -e "${YELLOW}⚠️ Failed to install $pkg, continuing...${RESET}"
    done
  }

  apt-get install -y -qq php8.3-bcmath php8.3-xml php8.3-fpm php8.3-curl php8.3-zip || {
    echo -e "${YELLOW}⚠️ Some PHP packages failed. Trying individually...${RESET}"
    for pkg in php8.3-bcmath php8.3-xml php8.3-fpm php8.3-curl php8.3-zip; do
      apt-get install -y -qq "$pkg" || echo -e "${YELLOW}⚠️ Failed to install $pkg, continuing...${RESET}"
    done
  }

  echo -e "${CYAN}⚙️ Installing MariaDB...${RESET}"
  apt-get install -y -qq mariadb-server || {
    echo -e "${RED}❌ Failed to install MariaDB. Critical for application.${RESET}"
    read -p "Continue anyway? (y/n): " CONTINUE && [[ "$CONTINUE" != "y" ]] && exit 1
  }

  echo -e "${CYAN}⚙️ Installing Nginx...${RESET}"
  apt-get install -y -qq nginx || {
    echo -e "${RED}❌ Failed to install Nginx. Critical for application.${RESET}"
    read -p "Continue anyway? (y/n): " CONTINUE && [[ "$CONTINUE" != "y" ]] && exit 1
  }

  echo -e "${CYAN}⚙️ Installing Redis...${RESET}"
  apt-get install -y -qq redis-server || echo -e "${YELLOW}⚠️ Redis install failed, continuing...${RESET}"

  echo -e "${CYAN}⚙️ Installing NodeJS...${RESET}"
  apt-get install -y -qq nodejs || echo -e "${YELLOW}⚠️ NodeJS install failed, continuing...${RESET}"

  echo -e "${CYAN}⚙️ Installing utilities...${RESET}"
  apt-get install -y -qq tar unzip git || {
    echo -e "${YELLOW}⚠️ Utilities failed. Trying individually...${RESET}"
    for pkg in tar unzip git; do
      apt-get install -y -qq "$pkg" || echo -e "${YELLOW}⚠️ Failed to install $pkg, continuing...${RESET}"
    done
  }

  if ! command -v composer > /dev/null; then
    echo -e "${CYAN}⚙️ Installing Composer...${RESET}"
    if ! curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer; then
      echo -e "${YELLOW}⚠️ Composer failed via curl. Trying fallback...${RESET}"
      wget -q -O composer-setup.php https://getcomposer.org/installer
      php composer-setup.php --install-dir=/usr/local/bin --filename=composer
      rm -f composer-setup.php

      if ! command -v composer > /dev/null; then
        echo -e "${RED}❌ Composer installation failed. Required for Laravel.${RESET}"
        read -p "Continue anyway? (y/n): " CONTINUE && [[ "$CONTINUE" != "y" ]] && exit 1
      fi
    fi
  fi

  echo -e "${GREEN}✅ All dependencies installed quietly and successfully.${RESET}"
  mark_step_completed "dependencies_installed"
}


# Configure installation
configure_installation() {
  echo -e "\n${BOLD}${YELLOW}==========[ Configuration ]==========${RESET}"

  if step_completed "installation_configured"; then
    echo -e "${GREEN}✅ Installation already configured. Loading existing config...${RESET}"
    # Load configuration from .env if it exists
    if [ -f "$INSTALL_DIR/.env" ]; then
      # Extract configuration values from .env
      PROXYCHECK_API_KEY=$(grep "^PROXYCHECK_API_KEY=" "$INSTALL_DIR/.env" | cut -d '=' -f2)
      PTERO_URL=$(grep "^PTERODACTYL_URL=" "$INSTALL_DIR/.env" | cut -d '=' -f2)
      PTERO_API_URL=$(grep "^PTERODACTYL_API_URL=" "$INSTALL_DIR/.env" | cut -d '=' -f2)
      PTERO_CLIENT_URL=$(grep "^PTERODACTYL_CLIENT_KEY=" "$INSTALL_DIR/.env" | cut -d '=' -f2)
      PAYPAL_SANDBOX=$(grep "^PAYPAL_SANDBOX=" "$INSTALL_DIR/.env" | cut -d '=' -f2)
      PAYPAL_CLIENT=$(grep "^PAYPAL_CLIENT=" "$INSTALL_DIR/.env" | cut -d '=' -f2)
      PAYPAL_SECRET=$(grep "^PAYPAL_SECRET=" "$INSTALL_DIR/.env" | cut -d '=' -f2)
      STRIPE_KEY=$(grep "^STRIPE_KEY=" "$INSTALL_DIR/.env" | cut -d '=' -f2)
      STRIPE_SECRET=$(grep "^STRIPE_SECRET=" "$INSTALL_DIR/.env" | cut -d '=' -f2)
      STRIPE_WEBHOOK_SECRET=$(grep "^STRIPE_WEBHOOK_SECRET=" "$INSTALL_DIR/.env" | cut -d '=' -f2)
      DISCORD_CLIENT_ID=$(grep "^DISCORD_CLIENT_ID=" "$INSTALL_DIR/.env" | cut -d '=' -f2)
      DISCORD_CLIENT_SECRET=$(grep "^DISCORD_CLIENT_SECRET=" "$INSTALL_DIR/.env" | cut -d '=' -f2)
      DISCORD_REDIRECT_URI=$(grep "^DISCORD_REDIRECT_URI=" "$INSTALL_DIR/.env" | cut -d '=' -f2)
      DISCORD_WEBHOOK_URL=$(grep "^DISCORD_WEBHOOK_URL=" "$INSTALL_DIR/.env" | cut -d '=' -f2)
      
      echo -e "${CYAN}ℹ️ Loaded configuration from existing .env file${RESET}"
      return 0
    else
      echo -e "${YELLOW}⚠️ Existing configuration state found but no .env file. Reconfiguring...${RESET}"
    fi
  fi

  # First time configuration
  if [ -z "$INSTALL_DIR" ]; then
    read -p "Install directory [/var/www/DezerX]: " INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-/var/www/DezerX}
  fi

  # Check if directory exists, create if not
  if [ ! -d "$INSTALL_DIR" ]; then
    mkdir -p "$INSTALL_DIR"
    echo -e "${GREEN}✅ Created directory: $INSTALL_DIR${RESET}"
  fi

  read -p "ProxyCheck API Key [XXXXXXXXXXXXXX]: " PROXYCHECK_API_KEY
  PROXYCHECK_API_KEY=${PROXYCHECK_API_KEY:-XXXXXXXXXXXXXX}

  read -p "Pterodactyl URL [https://panel.example.com]: " PTERO_URL
  PTERO_URL=${PTERO_URL:-https://panel.example.com}

  read -p "Pterodactyl API URL: " PTERO_API_URL
  read -p "Pterodactyl Client URL: " PTERO_CLIENT_URL

  read -p "Enable PayPal sandbox? (true/false) [false]: " PAYPAL_SANDBOX
  PAYPAL_SANDBOX=${PAYPAL_SANDBOX:-false}
  read -p "PayPal Client ID: " PAYPAL_CLIENT
  read -p "PayPal Secret: " PAYPAL_SECRET

  read -p "Stripe Key: " STRIPE_KEY
  read -p "Stripe Secret: " STRIPE_SECRET
  read -p "Stripe Webhook Secret: " STRIPE_WEBHOOK_SECRET

  read -p "Enable Discord integration? (y/n): " ENABLE_DISCORD
  if [[ "$ENABLE_DISCORD" == "y" ]]; then
    read -p "Discord Client ID: " DISCORD_CLIENT_ID
    read -p "Discord Client Secret: " DISCORD_CLIENT_SECRET
    read -p "Discord Redirect URI: " DISCORD_REDIRECT_URI
    read -p "Discord Webhook URL: " DISCORD_WEBHOOK_URL
  fi

  mark_step_completed "installation_configured"
}
# Setup database
setup_database() {
  echo -e "${CYAN}🧱 Creating database and user...${RESET}"

  if ! systemctl is-active --quiet mariadb; then
    echo -e "${BLUE}🔄 Starting MariaDB service...${RESET}"
    systemctl start mariadb
    if [ $? -ne 0 ]; then
      echo -e "${RED}❌ Failed to start MariaDB. Exiting.${RESET}"
      exit 1
    else
      echo -e "${GREEN}✅ MariaDB started.${RESET}"
    fi
  fi

  DB_PASSWORD=$(openssl rand -base64 18)
  DB_NAME="dezerx"
  DB_USERNAME="dezer"
  DB_HOST="127.0.0.1"
  DB_PORT="3306"

  # Check if "dezerx" database already exists
  if mariadb -u root -e "USE $DB_NAME;" 2>/dev/null; then
    while :; do
      RAND_SUFFIX=$(( RANDOM % 9000 + 1000 ))
      NEW_DB_NAME="dezerx_$RAND_SUFFIX"
      if ! mariadb -u root -e "USE $NEW_DB_NAME;" 2>/dev/null; then
        DB_NAME="$NEW_DB_NAME"
        break
      fi
    done
    echo -e "${YELLOW}⚠️ Database 'dezerx' already exists. Using unique name: ${BOLD}${BLUE}$DB_NAME${RESET}"
  else
    echo -e "${BLUE}📝 Database name set to: ${BOLD}$DB_NAME${RESET}"
  fi

  # Check if user exists and create a new one if needed
  if mariadb -u root -sse "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = '$DB_USERNAME');" | grep -q 1; then
    while :; do
      RAND_SUFFIX=$(( RANDOM % 9000 + 1000 ))
      NEW_DB_USER="dezer_$RAND_SUFFIX"
      if ! mariadb -u root -sse "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = '$NEW_DB_USER');" | grep -q 1; then
        DB_USERNAME="$NEW_DB_USER"
        break
      fi
    done
    echo -e "${YELLOW}⚠️ User 'dezer' already exists. Using unique user: ${BOLD}${BLUE}$DB_USERNAME${RESET}"
  else
    echo -e "${BLUE}📝 DB user set to: ${BOLD}$DB_USERNAME${RESET}"
  fi

  echo -e "${BLUE}🚀 Running MySQL commands to create database and user...${RESET}"
  mariadb -u root <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
CREATE USER '$DB_USERNAME'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';
CREATE USER '$DB_USERNAME'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USERNAME'@'127.0.0.1' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USERNAME'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL_SCRIPT

  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Database and user successfully created.${RESET}"
    echo -e "${GREEN}ℹ️  Database: ${BOLD}$DB_NAME${RESET}, Password: ${BOLD}**********${RESET} User: ${BOLD}$DB_USERNAME${RESET}"
  else
    echo -e "${RED}❌ Failed to create database and user. Check MySQL permissions or syntax.${RESET}"
    exit 1
  fi

  mark_step_completed "database_setup"
}


# Setup Laravel
setup_laravel() {
  echo -e "\n${BOLD}${YELLOW}==========[ Laravel Setup ]==========${RESET}"

  # Check if we're in the right directory
  if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${RED}❌ Installation directory does not exist: $INSTALL_DIR${RESET}"
    exit 1
  fi

  # Check if Laravel is already set up by looking for .env file
  if [ -f "$INSTALL_DIR/.env" ] && step_completed "laravel_setup"; then
    echo -e "${GREEN}✅ Laravel already set up. Skipping...${RESET}"
    
    # We still need to check permissions
    echo -e "${CYAN}📦 Ensuring proper file permissions...${RESET}"
    chown -R www-data:www-data "$INSTALL_DIR"/*
    
    return 0
  fi

  # Check for either .env.example or existing .env
  if [ ! -f "$INSTALL_DIR/.env.example" ] && [ ! -f "$INSTALL_DIR/.env" ]; then
    echo -e "${RED}❌ Neither .env.example nor .env file found in $INSTALL_DIR${RESET}"
    echo -e "${CYAN}ℹ️ Please ensure the DezerX application files are in $INSTALL_DIR${RESET}"
    exit 1
  fi

  cd "$INSTALL_DIR"
  
  # Copy .env.example to .env if .env doesn't exist
  if [ ! -f "$INSTALL_DIR/.env" ]; then
    cp .env.example .env
    echo -e "${CYAN}📦 Created new .env file from template${RESET}"
  else
    echo -e "${YELLOW}⚠️ Using existing .env file${RESET}"
  fi

  # Update .env file with proper domain format
  sed -i "s|^APP_URL=.*|APP_URL=https://$CLEAN_DOMAIN|" .env
  sed -i "s|^APP_DEBUG=.*|APP_DEBUG=false|" .env
  sed -i "s|^LICENSE_KEY=.*|LICENSE_KEY=$LICENSE_KEY|" .env
  sed -i "s|^PROXYCHECK_API_KEY=.*|PROXYCHECK_API_KEY=$PROXYCHECK_API_KEY|" .env
  sed -i "s|^PTERODACTYL_API_URL=.*|PTERODACTYL_API_URL=$PTERO_API_URL|" .env
  sed -i "s|^PTERODACTYL_CLIENT_KEY=.*|PTERODACTYL_CLIENT_KEY=$PTERO_CLIENT_URL|" .env
  sed -i "s|^PAYPAL_SANDBOX=.*|PAYPAL_SANDBOX=$PAYPAL_SANDBOX|" .env
  sed -i "s|^PAYPAL_CLIENT=.*|PAYPAL_CLIENT=$PAYPAL_CLIENT|" .env
  sed -i "s|^PAYPAL_SECRET=.*|PAYPAL_SECRET=$PAYPAL_SECRET|" .env
  sed -i "s|^STRIPE_KEY=.*|STRIPE_KEY=$STRIPE_KEY|" .env
  sed -i "s|^STRIPE_SECRET=.*|STRIPE_SECRET=$STRIPE_SECRET|" .env
  sed -i "s|^STRIPE_WEBHOOK_SECRET=.*|STRIPE_WEBHOOK_SECRET=$STRIPE_WEBHOOK_SECRET|" .env
  sed -i "s|^DB_HOST=.*|DB_HOST=$DB_HOST|" .env
  sed -i "s|^DB_PORT=.*|DB_PORT=$DB_PORT|" .env
  sed -i "s|^DB_DATABASE=.*|DB_DATABASE=$DB_NAME|" .env
  sed -i "s|^DB_USERNAME=.*|DB_USERNAME=$DB_USERNAME|" .env
  sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=$DB_PASSWORD|" .env

  if [[ "$ENABLE_DISCORD" == "y" ]]; then
    sed -i "s|^DISCORD_CLIENT_ID=.*|DISCORD_CLIENT_ID=$DISCORD_CLIENT_ID|" .env
    sed -i "s|^DISCORD_CLIENT_SECRET=.*|DISCORD_CLIENT_SECRET=$DISCORD_CLIENT_SECRET|" .env
    sed -i "s|^DISCORD_REDIRECT_URI=.*|DISCORD_REDIRECT_URI=$DISCORD_REDIRECT_URI|" .env
    sed -i "s|^DISCORD_WEBHOOK_URL=.*|DISCORD_WEBHOOK_URL=$DISCORD_WEBHOOK_URL|" .env
  fi

  # Check if composer dependencies are already installed
  if [ -d "$INSTALL_DIR/vendor" ] && step_completed "composer_installed"; then
    echo -e "${GREEN}✅ Composer dependencies already installed.${RESET}"
  else
    echo -e "${CYAN}📦 Installing composer dependencies...${RESET}"
    run_quietly composer install --no-interaction --no-progress --no-dev --optimize-autoloader
    mark_step_completed "composer_installed"
  fi
  
  # Check if frontend assets are already built
  if [ -d "$INSTALL_DIR/public/build" ] && step_completed "npm_built"; then
    echo -e "${GREEN}✅ Frontend assets already built.${RESET}"
  else
    # Install and build frontend assets
    echo -e "${CYAN}📦 Building frontend assets...${RESET}"
    run_quietly npm install
    run_quietly npm run build
    mark_step_completed "npm_built"
  fi
  
  # Generate key and run migrations if not done already
  if step_completed "migrations_run"; then
    echo -e "${GREEN}✅ Database migrations already run.${RESET}"
  else
    echo -e "${CYAN}📦 Setting up the database...${RESET}"
    run_quietly php artisan key:generate --force
    run_quietly php artisan migrate
    run_quietly php artisan db:seed --force
    mark_step_completed "migrations_run"
  fi
  
  # Set permissions
  echo -e "${CYAN}📦 Setting file permissions...${RESET}"
  chown -R www-data:www-data "$INSTALL_DIR"/*
  
  echo -e "${GREEN}✅ Laravel application set up successfully.${RESET}"
  mark_step_completed "laravel_setup"
}

# Setup SSL and Nginx
setup_ssl_nginx() {
  echo -e "\n${BOLD}${YELLOW}==========[ SSL + NGINX Setup ]==========${RESET}"
  
  if step_completed "ssl_nginx_setup" && [ -f "/etc/nginx/sites-enabled/dezerx.conf" ]; then
    echo -e "${GREEN}✅ Nginx and SSL already set up. Checking certificate renewal...${RESET}"
    # We'll still try to renew the certificate later
  else
    # Install Certbot if not installed
    if ! command -v certbot &> /dev/null; then
      echo -e "${CYAN}🔧 Installing Certbot...${RESET}"
      run_quietly apt-get install -y certbot python3-certbot-nginx
    fi
    
    # Create Nginx config first so certbot can find the domain
    echo -e "${CYAN}🔧 Setting up Nginx configuration...${RESET}"
    
    # Remove default nginx config if exists
    rm -f /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default 2>/dev/null || true
    
    # Create initial Nginx config
    cat <<EOF > /etc/nginx/sites-available/dezerx.conf
server {
    listen 80;
    server_name $CLEAN_DOMAIN;
    
    root $INSTALL_DIR/public;
    index index.php;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF
    
    # Enable site
    ln -sf /etc/nginx/sites-available/dezerx.conf /etc/nginx/sites-enabled/dezerx.conf
    run_quietly nginx -t && systemctl restart nginx
  fi
  
  # Check if SSL certificate exists
  SSL_CERT_EXISTS=false
  if [ -d "/etc/letsencrypt/live/$CLEAN_DOMAIN" ]; then
    SSL_CERT_EXISTS=true
    echo -e "${CYAN}🔒 SSL certificate already exists for $CLEAN_DOMAIN${RESET}"
    
    # Check if we need to renew
    RENEWAL_NEEDED=false
    EXPIRY_DATE=$(openssl x509 -enddate -noout -in /etc/letsencrypt/live/$CLEAN_DOMAIN/fullchain.pem | cut -d= -f2)
    EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
    CURRENT_EPOCH=$(date +%s)
    DAYS_LEFT=$(( ($EXPIRY_EPOCH - $CURRENT_EPOCH) / 86400 ))
    
    if [ $DAYS_LEFT -lt 30 ]; then
      echo -e "${YELLOW}⚠️ Certificate expires in $DAYS_LEFT days. Renewing...${RESET}"
      RENEWAL_NEEDED=true
    else
      echo -e "${GREEN}✅ Certificate valid for $DAYS_LEFT more days.${RESET}"
    fi
    
    if [ "$RENEWAL_NEEDED" = true ]; then
      # Force certificate renewal
      echo -e "${CYAN}🔄 Forcing certificate renewal...${RESET}"
      run_quietly certbot renew --force-renewal --cert-name $CLEAN_DOMAIN
    fi
  else
    # Get SSL certificate
    echo -e "${CYAN}🔒 Obtaining new SSL certificate for $CLEAN_DOMAIN...${RESET}"
    
    # Try certbot with nginx plugin first
    if ! run_quietly certbot certonly --nginx -d "$CLEAN_DOMAIN" --non-interactive --agree-tos -m admin@"$CLEAN_DOMAIN"; then
      echo -e "${YELLOW}⚠️ Certbot nginx plugin failed, trying standalone mode...${RESET}"
      # Try standalone mode (requires port 80 to be free)
      if systemctl is-active --quiet nginx; then
        systemctl stop nginx
      fi
      
      if ! run_quietly certbot certonly --standalone -d "$CLEAN_DOMAIN" --non-interactive --agree-tos -m admin@"$CLEAN_DOMAIN"; then
        echo -e "${YELLOW}⚠️ Automated certificate generation failed. Trying interactive mode...${RESET}"
        certbot certonly --standalone -d "$CLEAN_DOMAIN"
      fi
      
      # Start nginx back if we stopped it
      if ! systemctl is-active --quiet nginx; then
        systemctl start nginx
      fi
    fi
    
    SSL_CERT_EXISTS=true
  fi
  
  # Update Nginx config with SSL if we have it
  if [ "$SSL_CERT_EXISTS" = true ]; then
    echo -e "${CYAN}🔧 Updating Nginx configuration with SSL...${RESET}"
    
    cat <<EOF > /etc/nginx/sites-available/dezerx.conf
server {
    listen 80;
    server_name $CLEAN_DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $CLEAN_DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$CLEAN_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$CLEAN_DOMAIN/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/$CLEAN_DOMAIN/chain.pem;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    index index.php;
    root $INSTALL_DIR/public;
    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF

    # Test and reload Nginx
    run_quietly nginx -t && systemctl restart nginx
    echo -e "${GREEN}✅ Nginx configured with SSL for $CLEAN_DOMAIN.${RESET}"
  else
    echo -e "${RED}❌ Failed to obtain SSL certificate. Using HTTP configuration only.${RESET}"
  fi
  
  mark_step_completed "ssl_nginx_setup"
}
# Setup cron jobs
setup_cron() {
  echo -e "\n${BOLD}${YELLOW}==========[ Setting up Cron Jobs ]==========${RESET}"
  
  if step_completed "cron_setup"; then
    echo -e "${GREEN}✅ Cron jobs already set up. Skipping...${RESET}"
    return 0
  fi
  
  # Check if the cron job already exists before adding it
  if ! crontab -l 2>/dev/null | grep -q "$INSTALL_DIR.*schedule:run"; then
    echo -e "${CYAN}📅 Adding Laravel scheduler to crontab...${RESET}"
    (crontab -l 2>/dev/null; echo "* * * * * cd $INSTALL_DIR && php artisan schedule:run >> /dev/null 2>&1") | crontab -
    echo -e "${GREEN}✅ Cron job added.${RESET}"
  else
    echo -e "${GREEN}✅ Laravel scheduler already in crontab.${RESET}"
  fi
  
  mark_step_completed "cron_setup"
}

# Setup queue worker
setup_queue_worker() {
  echo -e "\n${BOLD}${YELLOW}==========[ Setting up Queue Worker ]==========${RESET}"
  
  if step_completed "queue_worker_setup"; then
    echo -e "${GREEN}✅ Queue worker already set up. Checking status...${RESET}"
    if systemctl is-active --quiet dezerx-worker.service; then
      echo -e "${GREEN}✅ Queue worker service is running.${RESET}"
    else
      echo -e "${YELLOW}⚠️ Queue worker service exists but is not running. Starting...${RESET}"
      systemctl start dezerx-worker.service
    fi
    return 0
  fi
  
  # Create systemd service file for queue worker
  echo -e "${CYAN}🔄 Creating queue worker service...${RESET}"
  cat <<EOF > /etc/systemd/system/dezerx-worker.service
[Unit]
Description=DezerX Queue Worker
After=network.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/php $INSTALL_DIR/artisan queue:work --sleep=3 --tries=3 --max-time=3600
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  # Enable and start the service
  run_quietly systemctl daemon-reload
  run_quietly systemctl enable dezerx-worker.service
  run_quietly systemctl start dezerx-worker.service
  
  echo -e "${GREEN}✅ Queue worker service configured and started.${RESET}"
  mark_step_completed "queue_worker_setup"
}

# Configure automatic SSL renewal
setup_ssl_renewal() {
  echo -e "\n${BOLD}${YELLOW}==========[ Setting up SSL Auto-Renewal ]==========${RESET}"
  
  if step_completed "ssl_renewal_setup"; then
    echo -e "${GREEN}✅ SSL auto-renewal already set up. Skipping...${RESET}"
    return 0
  fi
  
  # Make sure renewal hook directory exists
  mkdir -p /etc/letsencrypt/renewal-hooks/post
  
  # Create renewal hook to restart Nginx
  cat <<EOF > /etc/letsencrypt/renewal-hooks/post/nginx-restart.sh
#!/bin/bash
systemctl restart nginx
EOF

  # Make it executable
  chmod +x /etc/letsencrypt/renewal-hooks/post/nginx-restart.sh
  
  # Test certbot renewal process (dry run)
  echo -e "${CYAN}🔄 Testing certificate renewal process...${RESET}"
  run_quietly certbot renew --dry-run
  
  echo -e "${GREEN}✅ SSL auto-renewal configured.${RESET}"
  mark_step_completed "ssl_renewal_setup"
}

# Save installation details for reference
save_installation_details() {
  echo -e "\n${BOLD}${YELLOW}==========[ Saving Installation Details ]==========${RESET}"

  INSTALL_INFO_FILE="$INSTALL_DIR/installation_details.txt"

  cat <<EOF > "$INSTALL_INFO_FILE"
${BOLD}${CYAN}DezerX Installation Details${RESET}
${CYAN}============================${RESET}

${BOLD}${MAGENTA}📅 Installation Date:${RESET}     $(date)
${BOLD}${MAGENTA}🌐 Domain:${RESET}                 ${BOLD}${BLUE}$CLEAN_DOMAIN${RESET}
${BOLD}${MAGENTA}📁 Install Directory:${RESET}      $INSTALL_DIR

${BOLD}${BLUE}🗄️  Database Information:${RESET}
  ${BOLD}• Host:${RESET}     $DB_HOST
  ${BOLD}• Port:${RESET}     $DB_PORT
  ${BOLD}• Name:${RESET}     $DB_NAME
  ${BOLD}• Username:${RESET} $DB_USERNAME
  ${BOLD}• Password:${RESET} $DB_PASSWORD

${RED}${BOLD}⚠️  This file contains sensitive information. Please keep it secure!${RESET}
EOF

  chmod 600 "$INSTALL_INFO_FILE"
  chown www-data:www-data "$INSTALL_INFO_FILE"

  echo -e "${GREEN}✅ Installation details saved to ${BOLD}$INSTALL_INFO_FILE${RESET}"
}


# Main function
main() {
  check_root
  display_logo
  check_prerequisites
  check_existing_installation
  verify_license
  install_dependencies
  configure_installation
  setup_database
  setup_laravel
  setup_ssl_nginx
  setup_cron
  setup_queue_worker
  setup_ssl_renewal
  save_installation_details
  
  # Final message
  echo -e "\n${BOLD}${GREEN}✅ DezerX installation complete!"
  echo -e "🌐 Visit your app at: https://$CLEAN_DOMAIN"
  echo -e "📝 Database information:"
  echo -e "   - Database: $DB_NAME"
  echo -e "   - Username: $DB_USERNAME"
  echo -e "   - Password: $DB_PASSWORD (SAVE THIS PASSWORD SECURELY)"
  echo -e "${RESET}"
  echo -e "${YELLOW}📘 Installation details saved to $INSTALL_DIR/installation_details.txt${RESET}"
  rm -f "$STATE_FILE"
  
}

# Run the main function
main
