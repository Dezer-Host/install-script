#!/bin/bash
clear

# ===== IMPROVED COLOR DEFINITIONS WITH BETTER CONTRAST =====
RED="\033[1;31m"
GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
MAGENTA="\033[1;35m"
WHITE="\033[1;37m"
BOLD="\033[1m"
DIM="\033[2m"
RESET="\033[0m"

# Animated spinner for long-running processes
spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='|/-\'
  while ps -p $pid > /dev/null; do
    local temp=${spinstr#?}
    printf " [%c]  " "$spinstr"
    local spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b\b\b"
  done
  printf "    \b\b\b\b"
}

# Progress bar function
progress_bar() {
  local progress=$1
  local total=$2
  local width=40
  local percentage=$((progress * 100 / total))
  local completed=$((progress * width / total))
  local remaining=$((width - completed))
  
  printf "${YELLOW}[${RESET}"
  printf "%${completed}s" | tr ' ' '█'
  printf "%${remaining}s" | tr ' ' '░'
  printf "${YELLOW}] ${WHITE}%3d%%${RESET}" $percentage
}

# Temporary state file to track update progress
STATE_FILE="/tmp/dezerx_update_state.json"

check_root() {
  if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}⛔ Error: This script must be run as root${RESET}"
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
    echo -e "${YELLOW}⚠️  Command had non-zero exit: $1${RESET}"
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
    echo -e "${YELLOW}⚠️  Warning: Failed to update state file. Continuing anyway.${RESET}"
    rm -f "$TEMP_FILE"
  fi
}

display_logo() {
  echo
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
  echo -e "${BOLD}${MAGENTA}🚀 DezerX Update Tool${RESET} ${YELLOW}v1.1.0${RESET}"
  echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"

  echo -e "${BOLD}${BLUE}🔗 Discord:${RESET} ${WHITE}https://discord.gg/UN4VVc2hWJ${RESET}"
  echo -e "${BOLD}${BLUE}🌐 Website:${RESET} ${WHITE}https://dezerx.com${RESET}"
  echo -e "${BOLD}${BLUE}🐞 Version:${RESET} ${WHITE}v1.1.0 — Please report any bugs you encounter!${RESET}"
  echo
}

print_section_header() {
  local title=$1
  local width=50
  local padding=$(( (width - ${#title} - 6) / 2 ))
  echo
  echo -e "${BOLD}${YELLOW}╔═$( printf '═%.0s' $(seq 1 $width) )═╗${RESET}"
  echo -e "${BOLD}${YELLOW}║ ${WHITE}$( printf ' %.0s' $(seq 1 $padding) )[ ${CYAN}$title${WHITE} ]$( printf ' %.0s' $(seq 1 $padding) ) ${YELLOW}║${RESET}"
  echo -e "${BOLD}${YELLOW}╚═$( printf '═%.0s' $(seq 1 $width) )═╝${RESET}"
  echo
}

check_prerequisites() {
  print_section_header "Checking Prerequisites"
  
  local missing=0
  
  echo -e "${CYAN}📋 Verifying required components...${RESET}"
  sleep 0.5
  
  for cmd in curl apt-get; do
    echo -ne "${WHITE}  ⟐ Checking for ${BLUE}$cmd${WHITE}...${RESET} "
    if command -v $cmd &> /dev/null; then
      echo -e "${GREEN}Found ✓${RESET}"
      sleep 0.2
    else
      echo -e "${RED}Missing ✗${RESET}"
      missing=1
      sleep 0.2
    fi
  done
  
  # Check for composer and npm
  echo -ne "${WHITE}  ⟐ Checking for ${BLUE}composer${WHITE}...${RESET} "
  if ! command -v composer &> /dev/null; then
    echo -e "${YELLOW}Not Found - Installing${RESET}"
    echo -ne "${WHITE}    ↳ Installing Composer...${RESET} "
    if ! curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer > /dev/null 2>&1; then
      echo -e "${RED}Failed ✗${RESET}"
      echo -e "${RED}    ↳ Could not install Composer automatically. Please install manually.${RESET}"
      missing=1
    else
      echo -e "${GREEN}Installed ✓${RESET}"
    fi
  else
    echo -e "${GREEN}Found ✓${RESET}"
  fi
  
  echo -ne "${WHITE}  ⟐ Checking for ${BLUE}npm${WHITE}...${RESET} "
  if ! command -v npm &> /dev/null; then
    echo -e "${YELLOW}Not Found - Installing${RESET}"
    echo -ne "${WHITE}    ↳ Installing NodeJS...${RESET} "
    if ! curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1 && apt-get install -y nodejs > /dev/null 2>&1; then
      echo -e "${RED}Failed ✗${RESET}"
      echo -e "${RED}    ↳ Could not install NodeJS automatically. Please install manually.${RESET}"
      missing=1
    else
      echo -e "${GREEN}Installed ✓${RESET}"
    fi
  else
    echo -e "${GREEN}Found ✓${RESET}"
  fi
  
  if [ $missing -eq 1 ]; then
    echo -e "\n${RED}❌ Some required components are missing. Please install them before continuing.${RESET}"
    exit 1
  fi
  
  echo -e "\n${GREEN}✅ All prerequisites satisfied.${RESET}"
  sleep 1
}

verify_license() {
  print_section_header "License Verification"

  echo -e "${CYAN}🔑 Please enter your license information:${RESET}\n"
  
  read -p "$(echo -e "${WHITE}Enter your license key: ${RESET}")" LICENSE_KEY
  read -p "$(echo -e "${WHITE}Enter your domain (must point to this server): ${RESET}")" DOMAIN
  
  CLEAN_DOMAIN=$(echo "$DOMAIN" | sed -e 's|^https\?://||' -e 's|/.*$||')
  export CLEAN_DOMAIN

  echo -e "\n${CYAN}🔍 Verifying license...${RESET}"
  
  # Show animated spinner during verification
  (
    i=0
    sp="⣾⣽⣻⢿⡿⣟⣯⣷"
    echo -n ' '
    while [ $i -lt 10 ]; do
      printf "\b${CYAN}${sp:i++%${#sp}:1}${RESET}"
      sleep 0.1
    done
  ) &
  spinner_pid=$!
  
  sleep 1 # Give spinner some time to run
  
  if ! curl -s --head https://license-check.dezerx.com > /dev/null; then
    kill $spinner_pid 2>/dev/null
    echo -e "\n${RED}❌ Cannot reach license verification server.${RESET}"
    exit 1
  fi
  
  VERIFY_RESPONSE=$(curl -s -X POST "https://license-check.dezerx.com/api/verify-license" \
    -H "Content-Type: application/json" \
    -d "{\"domain_or_subdomain\":\"$DOMAIN\", \"license_key\":\"$LICENSE_KEY\"}")

  kill $spinner_pid 2>/dev/null
  printf "\b \b"
  
  if command -v jq &> /dev/null; then
    if [[ "$VERIFY_RESPONSE" == *'"verify":false'* ]]; then
      echo -e "\n${RED}❌ License verification failed: $(echo $VERIFY_RESPONSE | jq -r '.message')${RESET}"
      exit 1
    fi
  else
    if [[ "$VERIFY_RESPONSE" == *'"verify":false'* ]]; then
      echo -e "\n${RED}❌ License verification failed. Please check your license key and domain.${RESET}"
      exit 1
    fi
  fi
  
  echo -e "\n${GREEN}✅ License verified successfully.${RESET}"
  export LICENSE_KEY
  mark_step_completed "license_verified"
  sleep 1
}

locate_installation() {
  print_section_header "Locating DezerX Installation"
  
  # Try to find potential installation directories
  local DEFAULT_DIR=""
  local FOUND_DIRS=()
  
  echo -e "${CYAN}🔍 Searching for DezerX installations...${RESET}"
  
  # Show animated dots during search
  (
    for i in $(seq 1 5); do
      echo -ne "${DIM}   Scanning system"
      for j in $(seq 1 3); do
        echo -ne "."
        sleep 0.2
      done
      echo -ne "\r\033[K"
      sleep 0.2
    done
  ) &
  search_pid=$!
  
  for dir in /var/www/*/; do
    if [ -f "${dir}artisan" ] && grep -q "DezerX" "${dir}artisan" 2>/dev/null; then
      FOUND_DIRS+=("$dir")
      DEFAULT_DIR="${dir%/}"  # Remove trailing slash
    fi
  done
  
  kill $search_pid 2>/dev/null
  wait $search_pid 2>/dev/null
  echo -ne "\r\033[K"
  
  if [ ${#FOUND_DIRS[@]} -gt 0 ]; then
    echo -e "${GREEN}Found existing DezerX installation(s):${RESET}"
    for ((i=0; i<${#FOUND_DIRS[@]}; i++)); do
      echo -e "  ${CYAN}[$i]${WHITE} ${FOUND_DIRS[$i]%/}${RESET}"
    done
    echo
    
    if [ ${#FOUND_DIRS[@]} -eq 1 ]; then
      read -p "$(echo -e "${WHITE}Use this installation directory? ${CYAN}[Y/n]${WHITE}: ${RESET}")" CONFIRM
      if [[ "$CONFIRM" =~ ^[Nn] ]]; then
        read -p "$(echo -e "${WHITE}Enter the DezerX installation directory: ${RESET}")" INSTALL_DIR
      else
        INSTALL_DIR="${FOUND_DIRS[0]%/}"
      fi
    else
      read -p "$(echo -e "${WHITE}Select installation by number or enter a custom path: ${RESET}")" SELECTION
      if [[ "$SELECTION" =~ ^[0-9]+$ ]] && [ "$SELECTION" -lt ${#FOUND_DIRS[@]} ]; then
        INSTALL_DIR="${FOUND_DIRS[$SELECTION]%/}"
      else
        INSTALL_DIR="$SELECTION"
      fi
    fi
  else
    echo -e "${YELLOW}No existing DezerX installations automatically detected.${RESET}"
    read -p "$(echo -e "${WHITE}Enter the DezerX installation directory ${CYAN}[/var/www/DezerX]${WHITE}: ${RESET}")" INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-/var/www/DezerX}
  fi
  
  # Check if directory exists and contains a DezerX installation
  if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "\n${RED}❌ Directory doesn't exist: $INSTALL_DIR${RESET}"
    exit 1
  fi
  
  if [ ! -f "$INSTALL_DIR/artisan" ]; then
    echo -e "\n${RED}❌ No Laravel/DezerX installation found in $INSTALL_DIR${RESET}"
    exit 1
  fi
  
  echo -e "\n${GREEN}✅ DezerX installation found at: $INSTALL_DIR${RESET}"
  export INSTALL_DIR
  mark_step_completed "installation_found"
  sleep 1
}

backup_env() {
  print_section_header "Backing Up Environment"
  
  if [ ! -f "$INSTALL_DIR/.env" ]; then
    echo -e "${RED}❌ No .env file found in $INSTALL_DIR${RESET}"
    exit 1
  fi
  
  ENV_BACKUP="$INSTALL_DIR/.env.backup-$(date +%Y%m%d%H%M%S)"
  
  echo -e "${CYAN}💾 Creating backup of your environment file...${RESET}"
  
  cp "$INSTALL_DIR/.env" "$ENV_BACKUP"
  
  echo -e "${GREEN}✅ Environment backed up to:${RESET}"
  echo -e "   ${WHITE}$ENV_BACKUP${RESET}"
  echo -e "\n${YELLOW}⚠️  Please note this backup location for reference.${RESET}"
  mark_step_completed "env_backed_up"
  sleep 1
}

prepare_for_update() {
  print_section_header "Update Preparation"
  
  echo -e "${CYAN}ℹ️  Before continuing, please make sure you have:${RESET}"
  echo -e "   ${WHITE}1. Downloaded the latest DezerX files${RESET}"
  echo -e "   ${WHITE}2. Backed up your existing installation (recommended)${RESET}"
  echo -e "   ${WHITE}3. Copied the new files to $INSTALL_DIR${RESET}"
  echo
  
  read -p "$(echo -e "${WHITE}Have you copied the new DezerX files to the installation directory? ${CYAN}[y/N]${WHITE} ${RESET}")" FILES_READY
  
  if [[ ! "$FILES_READY" =~ ^[Yy] ]]; then
    echo -e "\n${YELLOW}⚠️  Please follow these steps:${RESET}"
    echo -e "   ${CYAN}1.${WHITE} Back up your .env file${RESET}"
    echo -e "   ${CYAN}2.${WHITE} Add the new DezerX files to $INSTALL_DIR${RESET}"
    echo -e "   ${CYAN}3.${WHITE} Make sure you've restored your .env file if necessary${RESET}"
    echo
    read -p "$(echo -e "${WHITE}Run this update script again when you're ready. Press any key to exit...${RESET}")" -n1
    exit 0
  fi
  
  # Verify that the .env file exists after files were copied
  if [ ! -f "$INSTALL_DIR/.env" ]; then
    echo -e "\n${RED}❌ No .env file found in $INSTALL_DIR after files were copied!${RESET}"
    echo -e "${YELLOW}⚠️  Please restore your .env file from backup.${RESET}"
    exit 1
  fi
  
  mark_step_completed "update_prepared"
  sleep 1
}

update_application() {
  print_section_header "Updating DezerX Application"
  
  # Change to installation directory
  cd "$INSTALL_DIR"
  
  # Install/update composer dependencies
  echo -e "${CYAN}⚙️  Updating composer dependencies...${RESET}"
  
  STEPS_TOTAL=8
  STEP=1
  
  echo -ne "${WHITE}   "
  progress_bar $STEP $STEPS_TOTAL
  echo -e "${RESET}"
  
  composer install --no-interaction --no-dev --optimize-autoloader > /dev/null 2>&1 &
  composer_pid=$!
  
  spinner $composer_pid
  wait $composer_pid
  check_command "composer install" || { echo -e "${RED}❌ Composer installation failed${RESET}"; exit 1; }
  
  STEP=$((STEP+1))
  echo -ne "${WHITE}   "
  progress_bar $STEP $STEPS_TOTAL
  echo -e "${RESET}"
  
  # Install/update npm dependencies
  echo -e "${CYAN}⚙️  Updating npm packages...${RESET}"
  npm install > /dev/null 2>&1 &
  npm_pid=$!
  
  spinner $npm_pid
  wait $npm_pid
  check_command "npm install" || { echo -e "${RED}❌ NPM installation failed${RESET}"; exit 1; }
  
  STEP=$((STEP+2))
  echo -ne "${WHITE}   "
  progress_bar $STEP $STEPS_TOTAL
  echo -e "${RESET}"
  
  # Build assets
  echo -e "${CYAN}⚙️  Building frontend assets...${RESET}"
  npm run build > /dev/null 2>&1 &
  build_pid=$!
  
  spinner $build_pid
  wait $build_pid
  check_command "npm run build" || { echo -e "${YELLOW}⚠️  Frontend build had issues but continuing...${RESET}"; }
  
  STEP=$((STEP+2))
  echo -ne "${WHITE}   "
  progress_bar $STEP $STEPS_TOTAL
  echo -e "${RESET}"
  
  # Run database migrations
  echo -e "${CYAN}⚙️  Running database migrations...${RESET}"
  php artisan migrate --force > /dev/null 2>&1 &
  migrate_pid=$!
  
  spinner $migrate_pid
  wait $migrate_pid
  check_command "database migrations" || { echo -e "${RED}❌ Database migrations failed${RESET}"; exit 1; }
  
  STEP=$((STEP+1))
  echo -ne "${WHITE}   "
  progress_bar $STEP $STEPS_TOTAL
  echo -e "${RESET}"
  
  # Run seeders
  echo -e "${CYAN}⚙️  Running database seeders...${RESET}"
  php artisan db:seed --force > /dev/null 2>&1 &
  seed_pid=$!
  
  spinner $seed_pid
  wait $seed_pid
  check_command "database seeding" || { echo -e "${YELLOW}⚠️  Database seeding had issues but continuing...${RESET}"; }
  
  STEP=$((STEP+1))
  echo -ne "${WHITE}   "
  progress_bar $STEP $STEPS_TOTAL
  echo -e "${RESET}\n"
  
  # Clear caches
  echo -e "${CYAN}⚙️  Clearing application caches...${RESET}"
  
  echo -ne "${DIM}   Clearing config cache...${RESET}\r"
  php artisan config:clear > /dev/null 2>&1
  sleep 0.3
  
  echo -ne "${DIM}   Clearing application cache...${RESET}\r"
  php artisan cache:clear > /dev/null 2>&1
  sleep 0.3
  
  echo -ne "${DIM}   Clearing view cache...${RESET}\r"
  php artisan view:clear > /dev/null 2>&1
  sleep 0.3
  
  echo -ne "${DIM}   Clearing route cache...${RESET}\r"
  php artisan route:clear > /dev/null 2>&1
  sleep 0.3
  
  echo -ne "\033[K"
  echo -e "${GREEN}   All caches cleared successfully.${RESET}"
  
  # Fix permissions
  echo -e "${CYAN}⚙️  Setting proper file permissions...${RESET}"
  
  echo -ne "${DIM}   Setting ownership...${RESET}\r"
  chown -R www-data:www-data "$INSTALL_DIR" > /dev/null 2>&1
  sleep 0.3
  
  echo -ne "${DIM}   Setting storage permissions...${RESET}\r"
  find "$INSTALL_DIR/storage" -type d -exec chmod 775 {} \; > /dev/null 2>&1
  find "$INSTALL_DIR/storage" -type f -exec chmod 664 {} \; > /dev/null 2>&1
  sleep 0.3
  
  echo -ne "${DIM}   Setting cache permissions...${RESET}\r"
  find "$INSTALL_DIR/bootstrap/cache" -type d -exec chmod 775 {} \; > /dev/null 2>&1
  sleep 0.3
  
  echo -ne "\033[K"
  echo -e "${GREEN}   Permissions set successfully.${RESET}"
  
  echo -e "\n${GREEN}✅ Application update completed successfully!${RESET}"
  mark_step_completed "update_completed"
  sleep 1
}

restart_services() {
  print_section_header "Restarting Services"
  
  echo -e "${CYAN}⚙️  Restarting system services...${RESET}"
  
  # Get PHP version
  PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
  
  echo -ne "${WHITE}   Restarting PHP-FPM ${PHP_VERSION}...${RESET} "
  if systemctl restart php${PHP_VERSION}-fpm > /dev/null 2>&1; then
    echo -e "${GREEN}Success ✓${RESET}"
  else
    echo -e "${YELLOW}Failed ⚠️  (trying other PHP versions)${RESET}"
    # Try common PHP versions
    for ver in 8.3 8.2 8.1 8.0 7.4; do
      if systemctl restart php${ver}-fpm > /dev/null 2>&1; then
        echo -e "${GREEN}   Found and restarted PHP ${ver} ✓${RESET}"
        break
      fi
    done
  fi
  
  echo -ne "${WHITE}   Restarting Nginx...${RESET} "
  if systemctl restart nginx > /dev/null 2>&1; then
    echo -e "${GREEN}Success ✓${RESET}"
  else
    echo -e "${YELLOW}Failed ⚠️${RESET}"
    # Try Apache
    echo -ne "${WHITE}   Trying Apache instead...${RESET} "
    if systemctl restart apache2 > /dev/null 2>&1; then
      echo -e "${GREEN}Success ✓${RESET}"
    else
      echo -e "${YELLOW}Failed ⚠️  (web server may need manual restart)${RESET}"
    fi
  fi
  
  # Check if queue worker exists and restart it
  echo -ne "${WHITE}   Checking for queue worker...${RESET} "
  if systemctl list-unit-files | grep -q dezerx-worker; then
    echo -e "${GREEN}Found ✓${RESET}"
    echo -ne "${WHITE}   Restarting queue worker...${RESET} "
    if systemctl restart dezerx-worker > /dev/null 2>&1; then
      echo -e "${GREEN}Success ✓${RESET}"
    else
      echo -e "${YELLOW}Failed ⚠️${RESET}"
    fi
  else
    echo -e "${YELLOW}Not found ⚠️${RESET}"
    echo -e "${DIM}   Queue worker not installed or using different name.${RESET}"
  fi
  
  echo -e "\n${GREEN}✅ Services restart process completed.${RESET}"
  mark_step_completed "services_restarted"
  sleep 1
}

finalize_update() {
  print_section_header "Finalizing Update"
  
  # Create/update update log
  local UPDATE_LOG="$INSTALL_DIR/update_history.log"
  local TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  
  echo -e "${CYAN}📝 Creating update record...${RESET}"
  echo "[$TIMESTAMP] DezerX updated successfully" >> "$UPDATE_LOG"
  
  # Check for any potential issues
  echo -e "${CYAN}🔍 Running post-update checks...${RESET}"
  
  local ISSUES_FOUND=false
  local ISSUES_LOG=""
  
  echo -ne "${WHITE}   Checking storage permissions...${RESET} "
  if [ ! -w "$INSTALL_DIR/storage" ]; then
    echo -e "${RED}Failed ✗${RESET}"
    ISSUES_FOUND=true
    ISSUES_LOG="${ISSUES_LOG}   ${RED}▸${WHITE} Storage directory is not writable${RESET}\n"
  else
    echo -e "${GREEN}Good ✓${RESET}"
  fi
  
  echo -ne "${WHITE}   Checking .env file...${RESET} "
  if [ ! -f "$INSTALL_DIR/.env" ]; then
    echo -e "${RED}Failed ✗${RESET}"
    ISSUES_FOUND=true
    ISSUES_LOG="${ISSUES_LOG}   ${RED}▸${WHITE} .env file is missing${RESET}\n"
  else
    echo -e "${GREEN}Good ✓${RESET}"
  fi
  
  echo -ne "${WHITE}   Checking bootstrap/cache permissions...${RESET} "
  if [ ! -w "$INSTALL_DIR/bootstrap/cache" ]; then
    echo -e "${RED}Failed ✗${RESET}"
    ISSUES_FOUND=true
    ISSUES_LOG="${ISSUES_LOG}   ${RED}▸${WHITE} bootstrap/cache directory is not writable${RESET}\n"
  else
    echo -e "${GREEN}Good ✓${RESET}"
  fi
  
  if [ "$ISSUES_FOUND" = true ]; then
    echo -e "\n${YELLOW}⚠️  Potential issues detected:${RESET}"
    echo -e "$ISSUES_LOG"
    echo -e "${YELLOW}   Please address these issues manually to ensure proper operation.${RESET}"
  else
    echo -e "\n${GREEN}✅ No issues detected.${RESET}"
  fi
  
  echo -e "\n${GREEN}✅ Update process finalized successfully.${RESET}"
  mark_step_completed "update_finalized"
  sleep 1
}

show_success_message() {
  clear
  echo
  echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║                                                       ║${RESET}"
  echo -e "${BOLD}${CYAN}║${RESET}  ${GREEN}       ✅ DezerX UPDATE COMPLETED SUCCESSFULLY!       ${CYAN}║${RESET}"
  echo -e "${BOLD}${CYAN}║                                                       ║${RESET}"
  echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════╝${RESET}"
  echo
  
  echo -e "${BLUE}  APPLICATION DETAILS${RESET}"
  echo -e "${CYAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "  ${BLUE}🌐 Your application:${RESET} ${WHITE}https://$CLEAN_DOMAIN${RESET}"
  echo -e "  ${BLUE}📁 Installation path:${RESET} ${WHITE}$INSTALL_DIR${RESET}"
  echo -e "  ${BLUE}📝 Environment backup:${RESET} ${WHITE}$ENV_BACKUP${RESET}"
  echo
  
  echo -e "${BLUE}  NEXT STEPS${RESET}"
  echo -e "${CYAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "  ${WHITE}1. Verify that your application is working correctly${RESET}"
  echo -e "  ${WHITE}2. Check the admin dashboard for any new features${RESET}"
  echo -e "  ${WHITE}3. Clear browser cache if needed${RESET}"
  echo
  
  echo -e "${YELLOW}  For support, visit our Discord: https://discord.gg/UN4VVc2hWJ${RESET}"
  echo -e "${CYAN}  Thanks for using DezerX!${RESET}"
  echo
  
  # Clean up state file
  rm -f "$STATE_FILE"
}
check_root() { :; }
display_logo() { :; }
check_prerequisites() { :; }
verify_license() { :; }
locate_installation() { :; }
backup_env() { :; }
prepare_for_update() { :; }
update_application() { :; }
restart_services() { :; }
finalize_update() { :; }

# Main function - simplified for testing just the success message
main() {
  # Set variables for testing the success message
  CLEAN_DOMAIN="example.com"
  INSTALL_DIR="/var/www/DezerX"
  ENV_BACKUP="/var/www/DezerX/.env.backup-20250414120000"
  
  show_success_message
}
