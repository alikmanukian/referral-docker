#!/usr/bin/env bash
set -e

# Color and formatting codes
declare -A COLORS
COLORS[RED]="\033[0;31m"
COLORS[GREEN]="\033[0;32m"
COLORS[YELLOW]="\033[0;33m"

CONTAINER_OUTPUT_FILE=/var/www/html/docs/container-info.txt

# Check if tput supports bold text
if tput bold >/dev/null 2>&1; then
  COLORS[BOLD]=$(tput bold)
  COLORS[RESET]=$(tput sgr0)
else
  COLORS[BOLD]="\033[1m"
  COLORS[RESET]="\033[0m"
fi

print_with_formatting() {
  local formats="$1" # This now can accept multiple formats, e.g. "${COLORS[GREEN]}${COLORS[BOLD]}"
  local text="$2"
  local target="$3"

  if [ "$target" == "file" ]; then
    printf "%b%b%b\n" "${formats}" "${text}" "${COLORS[RESET]}" >> "$CONTAINER_OUTPUT_FILE"
  else
    printf "%b%b%b\n" "${formats}" "${text}" "${COLORS[RESET]}"
  fi
}

# Set environment variables for NVM
export NVM_DIR=/home/encryption/.nvm
export NODE_VERSION=18.17.1

# Source NVM to make it available
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm
nvm use default --silent

cd /var/www/html/app

echo -e "\n"

print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "==============================================="
print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "Referral Factory Encryption Update"
print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "===============================================\n"
print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "Update started at: $(date -u +"%Y-%m-%d %H:%M:%S UTC")\n"
print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "-----------------------------------------------"
print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "-> Commencing app update..."
print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "-----------------------------------------------"

git pull

print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "-----------------------------------------------"
print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "-> App update complete..."
print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "-----------------------------------------------"
print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "-> Updating database..."
print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "-----------------------------------------------"

php artisan migrate --force

print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "-----------------------------------------------"
print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "-> Database update complete..."
print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "-----------------------------------------------"
print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "-> Clearing app cache..."
print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "-----------------------------------------------"

php artisan cache:clear

print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "-----------------------------------------------"
print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "-> App cache cleared..."
print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "-----------------------------------------------"
print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "-> Updating frontend files..."
print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "-----------------------------------------------"

npm install
npm run build

print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "----------------------------------------------\n"
print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "=============================================="
print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "Update completed at: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "==============================================\n"