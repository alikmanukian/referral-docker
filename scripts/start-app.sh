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
  local formats="$1"
  local text="$2"
  local target="$3"

  if [ "$target" == "file" ]; then
    printf "%b%b%b\n" "${formats}" "${text}" "${COLORS[RESET]}" >> "$CONTAINER_OUTPUT_FILE"
  else
    printf "%b%b%b\n" "${formats}" "${text}" "${COLORS[RESET]}"
  fi
}

# If no token is provided, stop the build before we go anywhere,
if [ -z "$REPO_PULL_TOKEN" ]; then
  print_with_formatting "${COLORS[RED]}${COLORS[BOLD]}" "You have not provided a REPO_PULL_TOKEN. Please get this token from Referral Factory Support and set the envvar via your .env or secrets"
  exit 1;
fi

# If no app key is provided, stop the build before we go anywhere,
if [ -z "$APP_KEY" ]; then
  print_with_formatting "${COLORS[RED]}${COLORS[BOLD]}" "You have not provided an APP_KEY environment variable. In order to securely encrypt some of the setup information during Docker builds, you need to provide this before building. Once this is set, changing it WILL cause decryption issues, and will affect containerisation in the future. It is also very important to keep this secure.\n\nSupported ciphers are: aes-256-cbc and the key should be exactly 32 characters in length."
  exit 1;
fi

# Test the supplied APP_KEY before building
PLAINTEXT="test"

# Check if the APP_KEY starts with "base64:"
if [[ "$APP_KEY" == base64:* ]]; then
    # Strip the "base64:" prefix and decode
    raw_key=$(echo "${APP_KEY#base64:}" | base64 --decode 2>/dev/null)

    if [ $? -ne 0 ]; then
        print_with_formatting "${COLORS[RED]}${COLORS[BOLD]}" "Provided APP_KEY is not in valid base64 format."
        exit 1;
    fi

else
    # Treat as raw key and encode to the expected base64 format
    raw_key="$APP_KEY"
    APP_KEY="base64:$(echo -n "$raw_key" | base64)"
fi

processed_key="$APP_KEY"
key_length=${#raw_key}

# Ensure the raw key length is valid for aes-256-cbc
if [ $key_length -ne 32 ]; then
    print_with_formatting "${COLORS[RED]}${COLORS[BOLD]}" "Provided APP_KEY does not meet the requirements of the supported cipher aes-256-cbc. Please generate a 32-character key and try your build again."
    exit 1;
fi

CIPHER="aes-256-cbc"

# Encrypt and then decrypt using the provided raw key
ENCRYPTED=$(echo "$PLAINTEXT" | openssl enc -"$CIPHER" -e -a -k "$raw_key" 2>/dev/null)
DECRYPTED=$(echo "$ENCRYPTED" | openssl enc -"$CIPHER" -d -a -k "$raw_key" 2>/dev/null)

# Check if the decrypted value matches the original plaintext
if [ "$DECRYPTED" != "$PLAINTEXT" ]; then
    print_with_formatting "${COLORS[RED]}${COLORS[BOLD]}" "Provided APP_KEY is not valid for cipher $CIPHER.\n\nPlease generate another key and try your build again."
    exit 1;
fi

SUPERVISORD_PASSWORD=$(openssl rand -hex 32)

# Update envars in .env, regardless of container state, to allow changes and restarts
# ensuring Dockerfile ENV's are considered
if [ -e "/var/www/html/.env" ]; then
  ENV_FILE_LOCATION=.env
else
  ENV_FILE_LOCATION=app/.env
fi

declare -A ENV_MAPPINGS
ENV_MAPPINGS[SUPERUSER_EMAIL]="MAIL_FROM_ADDRESS=REPLACE_MAIL_FROM_ADDRESS,MAIL_FROM_ADDRESS"
ENV_MAPPINGS[APP_URL]="APP_URL=REPLACE_APP_URL,APP_URL"
ENV_MAPPINGS[OTP_ENABLED]="OTP_ENABLED=.*,OTP_ENABLED"
ENV_MAPPINGS[APP_RF_FULL_URL]="APP_RF_FULL_URL=.*,APP_RF_FULL_URL"

for key in "${!ENV_MAPPINGS[@]}"; do
  if [ -n "${!key}" ]; then
    IFS=',' read -ra TARGETS <<< "${ENV_MAPPINGS[$key]}"
    sed -i "s#${TARGETS[0]}#${TARGETS[1]}=${!key}#" "$ENV_FILE_LOCATION"
  fi
done

# Handle external assets URLs
if [ -z "$ASSET_URL" ]; then
  sed -i "s/ASSET_URL=*/#ASSET_URL=/" "$ENV_FILE_LOCATION"
else
  sed -i "s#ASSET_URL=*#ASSET_URL='${ASSET_URL}'#" "$ENV_FILE_LOCATION"
fi

# Ensure we override the APP_KEY without getting any potential conflicts
awk -v app_key="$processed_key" 'BEGIN {FS = OFS = "="} /^APP_KEY=/ {$2 = app_key } 1' "$ENV_FILE_LOCATION" > temp.env && mv temp.env "$ENV_FILE_LOCATION"

# Handle various DB setups where required
if [ -n "$DB_CONNECTION" ]; then

  # Ensure we use supported engines
  if [ "$DB_CONNECTION" != "pgsql" ] && [ "$DB_CONNECTION" != "sqlite" ] && [ "$DB_CONNECTION" != "mysql" ]; then
    print_with_formatting "${COLORS[RED]}${COLORS[BOLD]}" "You are not using a supported DB_CONNECTION - Please use 'mysql', 'pgsql', or 'sqlite'"
    exit 1;
  fi

  # Ensure that no one can override the internal engine from MySQL, as that is the only supported engine for internal DB
  if ( [ -z "$USE_EXTERNAL_DB" ] && [ "$DB_CONNECTION" != "mysql" ] ) || ( [ -n "$USE_EXTERNAL_DB" ] && [ "$USE_EXTERNAL_DB" = "false" ] && [ "$DB_CONNECTION" != "mysql" ] ); then
    print_with_formatting "${COLORS[RED]}${COLORS[BOLD]}" "The internal database only supports using MySQL as an engine. Please ensure DB_CONNECTION=mysql or remove the DB_CONNECTION from your .env file"
    exit 1;
  fi;

  if [ "$DB_CONNECTION" != "mysql" ]; then
    sed -i "s/DB_CONNECTION=mysql/DB_CONNECTION='${DB_CONNECTION}'/" "$ENV_FILE_LOCATION"
  fi

  if [ "$DB_CONNECTION" = "sqlite" ]; then
    sed -i "s/DB_FOREIGN_KEYS=false/DB_FOREIGN_KEYS=true/" "$ENV_FILE_LOCATION"
  fi
fi

# Check if using an external database
if [ "$USE_EXTERNAL_DB" = "true" ]; then

  if [ -z "$DB_HOST" ] || [ -z "$DB_PORT" ] || [ -z "$DB_USERNAME" ] || [ -z "$DB_PASSWORD" ]; then
    print_with_formatting "${COLORS[RED]}${COLORS[BOLD]}" "You are using an external database, but have not provided a DB_HOST, DB_PORT, DB_USERNAME, or DB_PASSWORD. Please set these and build again"
    exit 1;
  fi

  if [ -z "$DB_DATABASE" ]; then
    DB_DATABASE='referral_factory_encryption'
  fi

  sed -i "s/DB_DATABASE=referral_factory_encryption/DB_DATABASE='${DB_DATABASE}'/" "$ENV_FILE_LOCATION"
  sed -i "s/DB_HOST=127.0.0.1/DB_HOST='${DB_HOST}'/" "$ENV_FILE_LOCATION"
  sed -i "s/DB_PORT=3306/DB_PORT='${DB_PORT}'/" "$ENV_FILE_LOCATION"
  sed -i "s/DB_USERNAME=laravel/DB_USERNAME='${DB_USERNAME}'/" "$ENV_FILE_LOCATION"
  sed -i "s/DB_PASSWORD=REPLACE_DB_PASSWORD/DB_PASSWORD='${DB_PASSWORD}'/" "$ENV_FILE_LOCATION"

fi

# Extract domain without protocol
DOMAIN=$(echo "$APP_URL" | sed -e 's/^http:\/\///' -e 's/^https:\/\///' -e 's/^\/\///')

# Replace the placeholder in the Nginx configuration
sed -i "s#REPLACE_WITH_URL#$DOMAIN#g" /etc/nginx/sites-available/default

# For proxy_pass, ensure it always uses http:// prefix
sed -i "s#proxy_pass http://$DOMAIN;#proxy_pass http://$DOMAIN;#g" /etc/nginx/sites-available/default

# Update Supervisor configurations
sed -i "s#REPLACE_WITH_URL#$DOMAIN#" /etc/supervisor/conf.d/supervisord.conf
sed -i "s#REPLACE_WITH_SUPERVISOR_PASSWORD#$SUPERVISORD_PASSWORD#" /etc/supervisor/conf.d/supervisord.conf

if [ "${DISABLE_NGINX_PROXY:-false}" = "true" ]; then
    sed -i '/^ *proxy_pass /,/proxy_set_header X-Forwarded-Proto $scheme;/d' /etc/nginx/sites-available/default
fi

# Base container has not yet been built, so lets run the setup
if [ -e "/var/www/html/.env" ]; then

  print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "Starting container build"

#  # Start memcached
#  service memcached start

  # Check if using an external database
  if [ "$USE_EXTERNAL_DB" = "false" ] || [ -z $USE_EXTERNAL_DB ]; then
    if [ -z "$ROOT_DB_PASSWORD" ] || [ "$ROOT_DB_PASSWORD" = "password" ]; then
      export ROOT_DB_PASSWORD="$(openssl rand -hex 32)"
    fi

    if [ -n "$DB_PASSWORD" ]; then
      if [ -z "$DB_CONNECTION" ] || ( [ -n "$DB_CONNECTION" ] && [ "$DB_CONNECTION" = "mysql" ] ); then
        # Start MariadDB and override the root user
        mysqld_safe --skip-grant-tables &
        while ! mysqladmin ping --silent; do
          sleep 1
        done

        print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "Overriding MySQL root user password"
        mysql -u root -e "USE mysql;FLUSH PRIVILEGES;SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$ROOT_DB_PASSWORD');"
        sleep 1
        print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "MySQL root user password updated"

        # Create app user
        mysqladmin -u root -p$ROOT_DB_PASSWORD shutdown
        mysqld --user=encryption &
        while ! mysqladmin ping --silent; do
          sleep 1
        done

        print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "Creating dedicated MySQL user for Laravel app"
        mysql -uroot -p$ROOT_DB_PASSWORD -e "CREATE USER 'laravel'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
        sleep 1
        mysql -uroot -p$ROOT_DB_PASSWORD -e "CREATE DATABASE referral_factory_encryption;"
        sleep 1
        mysql -uroot -p$ROOT_DB_PASSWORD -e "GRANT ALL PRIVILEGES ON referral_factory_encryption.* TO 'laravel'@'localhost' WITH GRANT OPTION;"
        sleep 1
        mysql -uroot -p$ROOT_DB_PASSWORD -e "FLUSH PRIVILEGES;"
        sleep 1
        sed -i "s/DB_PASSWORD=REPLACE_DB_PASSWORD/DB_PASSWORD='$DB_PASSWORD'/" "$ENV_FILE_LOCATION"
        print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "MySQL user created and .env updated"
      fi
    fi
  else
    # Remove mariadb config to ensure we don't start it when using external DBs
    sed -i '\|\[program:mariadb\]|,\|stdout_logfile=/home/encryption/log/mysql.log|d' /etc/supervisor/conf.d/supervisord.conf
  fi

  # Install NVM
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
  sleep 1

  # Set environment variables for NVM
  export NVM_DIR=/home/encryption/.nvm
  export NODE_VERSION=18.17.1

  # Source NVM to make it available
  export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm
  nvm install $NODE_VERSION && \
  nvm alias default $NODE_VERSION && \
  nvm use default

  # Clone the repo and install the laravel files
  if [ -n "$REPO_PULL_TOKEN" ]; then
    git clone "https://x-token-auth:$REPO_PULL_TOKEN@bitbucket.org/referral-factory/encryption.git" app
    mv /var/www/html/.env app/.env
    cd /var/www/html/app
    composer install

    # Setup Laravel
    php artisan storage:link

  else
    print_with_formatting "${COLORS[RED]}${COLORS[BOLD]}" "You have not provided the REPO_PULL_TOKEN. Please get this token from Referral Factory Support and set the ENV in your Dockerfile"
    exit 1;
  fi

  # Run migrations
  php artisan migrate --force
  sleep 1
  php artisan db:seed --force
  sleep 1

  print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "Setting permissions"

  # Setup Laravel logging & various permissions

  mkdir /var/www/html/app/node_modules
  mkdir /var/www/html/docs

  touch /var/www/html/app/storage/logs/laravel.log
  touch /var/www/html/app/storage/logs/queue-worker.log
  touch /var/www/html/docs/container-info.txt

  touch /home/encryption/log/php8.1-fpm.log
  touch /home/encryption/log/referral-factory/update.log
  touch /home/encryption/log/supervisord.log

  # PHP Permissions
  chmod 664 /var/www/html/app/storage/logs/laravel.log
  chmod -R 775 /var/www/html/app/storage
  chmod -R 775 /var/www/html/app/public/storage
  chmod -R 775 /var/www/html/app/bootstrap/cache
  chmod -R 755 /var/www/html/app/public
  chmod 644 /var/www/html/app/config/*.php
  chmod 644 /var/www/html/app/.env

  # Build frontend files
  print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "Building frontend files"
  npm install
  npm run build

  sleep 2

  # Caching
  php artisan cache:clear

  # Echo the final output
  echo -e "\n"

  print_with_formatting "${COLORS[GREEN]}" "===============================================================================================" "file"
  print_with_formatting "${COLORS[GREEN]}" "🚀 🚀 🚀 Your Referral Factory encrypted container is now setup " "file"
  print_with_formatting "${COLORS[GREEN]}" "===============================================================================================" "file"
  print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "::: Important Information :::" "file"
  print_with_formatting "${COLORS[GREEN]}" "===============================================================================================\n" "file"

  if [ -n "$DB_PASSWORD" ] && [ "$USE_EXTERNAL_DB" != "true" ]; then
    print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "Your 'root' MySQL password is: ${ROOT_DB_PASSWORD}" "file"
    print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "Your 'laravel' MySQL password is: ${DB_PASSWORD}" "file"
  fi

  print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "Your Referral Factory encrypted container URL: https://${APP_URL//\/\//}" "file"
  print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "Your Login Username: ${SUPERUSER_EMAIL}" "file"
  print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "Your Temporary Login Password: password\n" "file"
  print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "Your Supervisor URL: https://${APP_URL//\/\//}:9001" "file"
  print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "Your Supervisor Login: rfsupervisord" "file"
  print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "Your Supervisor Password: ${SUPERVISORD_PASSWORD}\n" "file"
  print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "Important Log File Locations" "file"
  print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "============================" "file"
  print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "Nginx (Access/Error) Logs: /home/encryption/log/nginx/${APP_URL//\/\//}.log" "file"
  print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "PHP Error Logs: /home/encryption/log/php8.1-fpm.log" "file"
  print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "Queue Worker Logs: /var/www/html/app/storage/logs/queue-worker.log\n" "file"
  print_with_formatting "${COLORS[GREEN]}" "===============================================================================================" "file"

fi

# Print container information and startup process
print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "Reminder: Your setup information has been added to /var/www/html/docs/container-info.txt for your reference."

cat /var/www/html/docs/container-info.txt

if [ -n "$DB_PASSWORD" ] && [ "$USE_EXTERNAL_DB" != "true" ]; then
  print_with_formatting "${COLORS[GREEN]}" "==============================================================================================="
  print_with_formatting "${COLORS[RED]}${COLORS[BOLD]}" "::: NB! PLEASE NOTE :::"
  print_with_formatting "${COLORS[RED]}" "You are using an internal MySQL server in this container. Deleting this "
  print_with_formatting "${COLORS[RED]}" "container/server will delete ALL of your data and be unrecoverable."
  print_with_formatting "${COLORS[RED]}${COLORS[BOLD]}" "We HIGHLY recommend using an external persistent database instead."
  print_with_formatting "${COLORS[GREEN]}" "==============================================================================================="
  echo -e "\n"
fi

print_with_formatting "${COLORS[GREEN]}${COLORS[BOLD]}" "Starting all services..."

# Stop mysql
if [ "$USE_EXTERNAL_DB" = "false" ] || [ -z $USE_EXTERNAL_DB ]; then
  while mysqladmin ping --silent; do
    mysqladmin -uroot -p"$ROOT_DB_PASSWORD" shutdown
  done;
fi;

# Start services under supervisord
/usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf