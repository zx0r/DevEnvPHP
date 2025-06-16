#!/usr/bin/env bash
# set -euo pipefail
# IFS=$'\n\t'

# Fix PHP
# brew list --formula | grep php
# brew services list
# sudo brew services stop php@8.2
# launchctl remove homebrew.mxcl.php@8.2
# sudo rm -f /Library/LaunchDaemons/homebrew.mxcl.php.plist
# brew tap shivammathur/php
# brew install "shivammathur/php/php@8.4"
# brew unlink php@8.2
# brew link --overwrite --force shivammathur/php/php@8.4  # or whatever version you installed
# brew services start shivammathur/php/php@8.4
# brew list --formula | grep php
# brew services list

# --- Configurable Environment Variables ---
: "${PHP_VERSION:=8.2}"
: "${DB_TYPE:=mysql}"
: "${DB_VERSION:=}"
: "${SERVER_TYPE:=nginx}"
: "${SERVER_VERSION:=}"
: "${PROJECT_NAME:=xclean}"
: "${PROJECTS_DIR:=$HOME/sites}"
: "${PROJECT_PATH:=$PROJECTS_DIR/$PROJECT_NAME}"
: "${WEBROOT:=$PROJECT_PATH/web}"
: "${WP_PATH:=$WEBROOT/wp}"

: "${WP_ENV:=development}"
: "${WP_HOME:=$PROJECT_NAME.test}"
: "${WP_SITEURL:=$WP_HOME/wp}"
: "${WP_TITLE:=WPDev}"
: "${WP_ADMIN:=admin}"
: "${WP_ADMIN_PASS:=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9!@#$%^&*()_+[]{}|:,.<>?~' | head -c 64)}"
: "${WP_ADMIN_EMAIL:=admin@local.test}"

: "${WP_THEME_NAME:=sage}"
: "${WP_THEME_PATH:=$WEBROOT/app/themes/$WP_THEME_NAME}"
: "${APP_URL:=$PROJECT_NAME.test}"

: "${DB_NAME:=$PROJECT_NAME}"
: "${DB_USER:=root}"
: "${DB_PASS:=}"
: "${DB_HOST:=127.0.0.1}"

# --- Constants ---
declare -A DB_PACKAGES=([mysql]="mysql" [mariadb]="mariadb")
declare -A WEB_PACKAGES=([nginx]="nginx" [apache]="httpd")
REQUIRED_WP_PACKAGES=(
  "aaemnnosttv/wp-cli-valet-command:@stable"
  "aaemnnosttv/wp-cli-dotenv-command:@stable"
  "aaemnnosttv/wp-cli-login-command:@stable"
)

# --- Logging ---
log() { echo -e "\033[34m[➤ ]\033[0m $*"; }
success() { echo -e "\033[32m[✓ ]\033[0m $*"; }
warn() { echo -e "\033[33m[⚠ ]\033[0m $*"; }
err() {
  echo -e "\033[31m[✗ ] $*\033[0m" >&2
  exit 1
}

# --- Utilities ---
check_or_create_dir() { [ -d "$1" ] || mkdir -p "$1"; }

# --- Bootstrap ---
init() {
  xcode-select -p >/dev/null 2>&1 || xcode-select --install || true
  command -v brew >/dev/null || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

install_php() {
  sudo chown -R "$(whoami)":admin "$(brew --prefix)/opt" || true
  sudo chown -R "$(whoami)":admin "$(brew --prefix)/Cellar" || true
  sudo chown -R "$(whoami)":admin "$(brew --prefix)/var/homebrew/linked" || true

  brew tap shivammathur/php
  local formula="shivammathur/php/php@${PHP_VERSION}"
  brew list "$formula" >/dev/null 2>&1 || brew install "$formula"
  # brew install "$formula"
  brew unlink php@"${PHP_VERSION}" || true && brew link --overwrite --force "$formula"
}

install_pkgs() {
  local pkgs=(
    "${DB_PACKAGES[$DB_TYPE]}${DB_VERSION}"
    "${WEB_PACKAGES[$SERVER_TYPE]}${SERVER_VERSION}"
    nginx mysql wp-cli composer brew-php-switcher mkcert nss
  )
  for pkg in "${pkgs[@]}"; do
    brew list --versions "$pkg" >/dev/null 2>&1 || brew install "$pkg"
  done
}

install_laravel_valet() {
  composer global require laravel/valet
  local bin_dir
  bin_dir=$(composer global config bin-dir --absolute)
  [[ ":$PATH:" != *":$bin_dir:"* ]] && export PATH="$PATH:$bin_dir"
  grep -q "$bin_dir" "$HOME/.config/fish/config.fish" || echo "fish_add_path $bin_dir" >>"$HOME/.config/fish/config.fish"
  valet install || err "Valet install failed"
  valet trust || err "Valet trust failed"
  valet use php@"$PHP_VERSION" --force
}

ensure_wp_cli_pkgs() {
  local current
  current=$(wp package list --field=name 2>/dev/null || echo "")
  for pkg in "${REQUIRED_WP_PACKAGES[@]}"; do
    echo "$current" | grep -qx "$pkg" || wp package install "$pkg"
  done
}

mysql_drop_db() {
  local db="$1"
  mysql -u root -e "DROP DATABASE IF EXISTS wp_$db"
}

mysql_ensure_running() {
  mysql.server status | grep -q 'not running' && mysql.server start
}

# --- Main Setup ---
setup_bedrock_valet() {
  check_or_create_dir "$PROJECTS_DIR"
  [ -d "$PROJECT_PATH" ] && err "Project \"$PROJECT_NAME\" already exists at $PROJECT_PATH"
  mkdir -p "$PROJECT_PATH"
  cd "$PROJECT_PATH"
  valet park && valet link --secure "$PROJECT_NAME"
  mysql_ensure_running
  ensure_wp_cli_pkgs
  mysql_drop_db "$DB_NAME"
  log "Creating Bedrock project with Valet..."
  wp valet new "$PROJECT_NAME" \
    --project=bedrock \
    --in="$PROJECTS_DIR" \
    --admin_user="$WP_ADMIN" \
    --admin_password="$WP_ADMIN_PASS" \
    --admin_email="$WP_ADMIN_EMAIL"

  wp dotenv set DB_NAME "$DB_NAME" --quiet
  wp dotenv set DB_USER "$DB_USER" --quiet
  wp dotenv set DB_PASSWORD "$DB_PASS" --quiet
  wp dotenv set DB_HOST "$DB_HOST" --quiet
  # wp dotenv set DB_PREFIX "$DB_PREFIX" --quiet

  wp dotenv set APP_URL "$APP_URL" --quiet
  wp dotenv set WP_ENV "$WP_ENV" --quiet
  wp dotenv set WP_HOME "$WP_HOME" --quiet
  wp dotenv set WP_SITEURL "$WP_SITEURL" --quiet
  wp dotenv set WP_TITLE "$WP_TITLE" --quiet
  wp dotenv set WP_ADMIN_USER "$WP_ADMIN" --quiet
  wp dotenv set WP_ADMIN_EMAIL "$WP_ADMIN_EMAIL" --quiet

  wp dotenv salts generate && wp dotenv list
  success "✅ Site created: $WP_URL"
  echo "$WP_ADMIN_PASS" | pbcopy
  log "🔑 Admin password copied to clipboard."
}

install_wordpress_theme() {
  local npm_cmd="dev"
  local composer_flags=(--no-ansi --no-interaction --no-progress)
  SAGE_BUD_CONFIG="$DEMYX"/web/app/themes/"$SAGE_THEME"/bud.config.mjs

  if [[ "$WP_ENV" == "production" ]]; then
    composer_flags+=(--no-dev --optimize-autoloader --no-scripts)
    npm_cmd="build"
  fi

  [[ -z "$WP_THEME_NAME" ]] && error "Theme name is required"
  [[ -d "$WP_THEME_PATH" ]] && error "Theme directory for $WP_THEME_PATH already exists"

  log "🛠️ Installing WordPress theme: $WP_THEME_NAME"
  composer create-project roots/sage "$WP_THEME_PATH" || error "Failed to create theme $WP_THEME_NAME with Composer"

  cd "$WP_THEME_PATH" || error "Failed to cd into $WP_THEME_PATH"
  log "📦 Installing Composer dependencies for $WP_THEME_NAME"

  composer install "${composer_flags[@]}" || error "Composer install failed for theme $WP_THEME_NAME"
  npm install || error "NPM install failed for theme $WP_THEME_NAME"
  npm run "$npm_cmd" || error "Asset compilation failed for theme $WP_THEME_NAME"

  log "Activating WordPress theme: $WP_THEME_NAME"
  wp theme activate "$WP_THEME_NAME" || error "Failed to activate theme $WP_THEME_NAME"
  success "Theme: $WP_THEME_NAME successfully installed and activated"
}

setup_xclean_structure() {
  echo "Создаю структуру сайта $PROJECT_NAME"

  # Страницы: slug -> "Заголовок|Содержимое"
  declare -A pages=(
    ["home"]="Главная|Добро пожаловать"
    ["services"]="Услуги|Наши услуги: ..."
    ["about"]="О нас|Информация о компании ..."
    ["contacts"]="Контакты|Свяжитесь с нами: ..."
  )
  declare -A page_ids=()

  # Создание страниц, если не существуют
  for slug in home services about contacts; do
    IFS="|" read -r title content <<<"${pages[$slug]}"
    page_id=$(wp post list --post_type=page --name="$slug" --field=ID --path="$WP_PATH" --quiet)
    if [[ -z "$page_id" ]]; then
      page_id=$(wp post create --post_type=page --post_title="$title" --post_name="$slug" --post_content="$content" --post_status=publish --path="$WP_PATH" --porcelain)
      echo "✅ Создана страница: $title (ID $page_id)"
    else
      echo "ℹ️  Страница '$title' уже существует (ID $page_id)"
    fi
    page_ids["$slug"]=$page_id
  done

  # Главное меню: создать и наполнить
  MENU_NAME="Главное меню"
  menu_id=$(wp menu list --field=term_id --name="$MENU_NAME" --path="$WP_PATH" --quiet)
  if [[ -z "$menu_id" ]]; then
    menu_id=$(wp menu create "$MENU_NAME" --path="$WP_PATH" --porcelain)
    echo "✅ Создано меню '$MENU_NAME' (ID $menu_id)"
    # Добавить страницы в меню в нужном порядке
    for slug in home services about contacts; do
      title=$(wp post get "${page_ids[$slug]}" --field=post_title --path="$WP_PATH")
      wp menu item add-post "$menu_id" "${page_ids[$slug]}" --path="$WP_PATH" --porcelain >/dev/null
      echo "➕ Добавлен пункт меню: $title"
    done
    wp menu location assign "$menu_id" primary --path="$WP_PATH"
    echo "📌 Меню '$MENU_NAME' назначено на локацию 'primary'"
  else
    echo "ℹ️  Меню '$MENU_NAME' уже существует (ID $menu_id)"
  fi

  # Настройка главной страницы
  wp option update show_on_front page --path="$WP_PATH"
  wp option update page_on_front "${page_ids["home"]}" --path="$WP_PATH"
  wp option update page_for_posts 0 --path="$WP_PATH"

  echo "🎉 Структура сайта $PROJECT_NAME успешно создана"
}
# post_install_config() {
#   log "Running post-install WordPress config..."

#   wp option update blog_public 0
#   wp option update posts_per_page 6

#   wp post delete "$(wp post list --post_type=page --pagename='sample-page' --field=ID --format=ids || true)" || true

#   local home_id
#   home_id=$(wp post create --post_type=page --post_title="Home" --post_status=publish --porcelain)
#   wp option update show_on_front 'page'
#   wp option update page_on_front "$home_id"

#   for page in About Contact Services Blog; do
#     wp post create --post_type=page --post_status=publish --post_title="$page" --porcelain
#   done

#   wp menu create "Main Navigation" || true
#   for pid in $(wp post list --orderby=date --post_type=page --post_status=publish --field=ID); do
#     wp menu item add-post main-navigation "$pid"
#   done
#   wp menu location assign main-navigation primary
#   wp rewrite structure '/%postname%/' && wp rewrite flush
#   wp plugin delete akismet hello || true
# }

main() {
  [[ "$(uname)" == "Darwin" ]] || err "This script must be run on macOS"
  init
  install_php
  install_pkgs
  install_laravel_valet
  setup_bedrock_valet
  install_wordpress_theme
  setup_xclean_structure
  success "🎉 WordPress Bedrock site with Sage theme is ready at https://$PROJECT_NAME.test"
}

main "$@"

# #!/usr/bin/env bash
# # set -euo pipefail
# # IFS=$'\n\t'

# # --- Configurable Environment Variables ---
# : "${PHP_VERSION:=8.2}"
# : "${DB_TYPE:=mysql}" : "${DB_VERSION:=}"
# : "${SERVER_TYPE:=nginx}" : "${SERVER_VERSION:=}"
# : "${PROJECT_NAME:=xclean}" : "${PROJECTS_DIR:=$HOME/sites}"
# : "${PROJECT_PATH:=$PROJECTS_DIR/$PROJECT_NAME}"
# : "${WEBROOT:=$PROJECT_PATH/web}"

# : "${DB_NAME:=wpdb}" : "${DB_USER:=wpuser}" : "${DB_PASS:=wppass}" : "${DB_HOST:=localhost}"
# : "${WP_ENV:=development}" : "${WP_URL:=$PROJECT_NAME.test}"
# : "${WP_HOME:=$WP_URL}" : "${WP_SITEURL:=$WP_URL/wp}"
# : "${WP_TITLE:=WPDev}" : "${WP_ADMIN:=admin}"
# : "${WP_ADMIN_PASS:=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9!@#$%^&*()_+[]{}|:,.<>?~' | head -c 64)}"
# : "${WP_ADMIN_EMAIL:=admin@local.test}"

# : "${WP_THEME_NAME:=sage}" : "${WP_THEME_PATH:=web/app/themes/$PROJECT_NAME}"
# : "${WP_THEME_REPO:=https://github.com/roots/sage.git}"

# # --- Constants ---
# declare -A DB_PACKAGES=([mysql]="mysql" [mariadb]="mariadb")
# declare -A WEB_PACKAGES=([nginx]="nginx" [apache]="httpd")
# REQUIRED_WP_PACKAGES=(
#   "aaemnnosttv/wp-cli-valet-command:@stable"
#   "aaemnnosttv/wp-cli-dotenv-command:@stable"
#   "aaemnnosttv/wp-cli-login-command:@stable"
# )

# # --- Utility ---
# log() { echo -e "\033[34m[➤ ]\033[0m $*"; }
# success() { echo -e "\033[32m[✓ ]\033[0m $*"; }
# warn() { echo -e "\033[33m[⚠ ]\033[0m $*"; }
# err() {
#   echo -e "\033[31m[✗ ] $*\033[0m" >&2
#   exit 1
# }

# check_or_create_dir() { [ -d "$1" ] || mkdir -p "$1"; }

# # --- Bootstrap ---
# init() {
#   xcode-select -p >/dev/null 2>&1 || xcode-select --install || true
#   command -v brew >/dev/null || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# }

# install_php() {
#   sudo chown -R "$(whoami)":admin "$(brew --prefix)/opt" || true
#   sudo chown -R "$(whoami)":admin "$(brew --prefix)/Cellar" || true
#   sudo chown -R "$(whoami)":admin "$(brew --prefix)/var/homebrew/linked" || true

#   brew tap shivammathur/php
#   local php_formula="shivammathur/php/php@${PHP_VERSION}"
#   brew list "$php_formula" >/dev/null 2>&1 || brew install "$php_formula"
#   brew unlink php || true
#   brew link --overwrite --force "$php_formula"
# }

# install_pkgs() {
#   local pkgs=(
#     "${DB_PACKAGES[$DB_TYPE]}${DB_VERSION}"
#     "${WEB_PACKAGES[$SERVER_TYPE]}${SERVER_VERSION}"
#     nginx mysql wp-cli composer brew-php-switcher mkcert nss
#   )
#   for pkg in "${pkgs[@]}"; do
#     brew list --versions "$pkg" >/dev/null 2>&1 || brew install "$pkg"
#   done
# }

# install_laravel_valet() {
#   composer global require laravel/valet
#   local bin_dir
#   bin_dir=$(composer global config bin-dir --absolute)
#   [[ ":$PATH:" != *":$bin_dir:"* ]] && export PATH="$PATH:$bin_dir"
#   grep -q "$bin_dir" "$HOME/.config/fish/config.fish" || echo "fish_add_path $bin_dir" >>"$HOME/.config/fish/config.fish"

#   valet install || error "Valet install failed"
#   valet trust || error "Valet trust failed"
#   valet use php@8.2 --force
# }

# ensure_wp_cli_pkgs() {
#   local current_pkgs
#   current_pkgs=$(wp package list --field=name 2>/dev/null || echo "")
#   for pkg in "${REQUIRED_WP_PACKAGES[@]}"; do
#     echo "$current_pkgs" | grep -qx "$pkg" || wp package install "$pkg"
#   done
# }

# mysql_drop_db() {
#   mysql -u root -e "DROP DATABASE IF EXISTS $1"
# }

# mysql_ensure_running() {
#   mysql.server status | grep -q 'not running' && mysql.server start
# }

# # --- Main Setup ---
# setup_bedrock_valet() {
#   check_or_create_dir "$PROJECTS_DIR"
#   [ -d "$PROJECT_PATH" ] && err "Project \"$PROJECT_NAME\" already exists at $PROJECT_PATH"
#   mkdir -p "$PROJECT_PATH"

#   cd "$PROJECT_PATH"
#   valet park
#   valet link --secure "$PROJECT_NAME"

#   mysql_ensure_running
#   ensure_wp_cli_pkgs
#   mysql_drop_db "$DB_NAME"

#   log "Creating Bedrock project with Valet..."
#   wp valet new "$PROJECT_NAME" \
#     --project=bedrock \
#     --in="$PROJECTS_DIR" \
#     --admin_user="$WP_ADMIN" \
#     --admin_password="$WP_ADMIN_PASS" \
#     --admin_email="$WP_ADMIN_EMAIL"

#   wp dotenv salts generate && wp dotenv list

#   success "✅ Site created: $WP_URL"
#   echo "$WP_ADMIN_PASS" | pbcopy
#   log "🔑 Admin copied to clipboard."
# }

# install_theme() {
#   log "Installing Sage theme..."
#   local theme_dir="$WEBROOT/web/app/themes/$WP_THEME_NAME"
#   check_or_create_dir "$(dirname "$theme_dir")"
#   [ -d "$theme_dir" ] || git clone "$WP_THEME_REPO" "$theme_dir"

#   pushd "$theme_dir" >/dev/null
#   composer install && npm install && (npm run build || gulp || true)
#   popd >/dev/null

#   wp theme activate "$WP_THEME_NAME"
# }

# post_install_config() {
#   log "Running post-install WordPress config..."

#   wp option update blog_public 0
#   wp option update posts_per_page 6

#   wp post delete "$(wp post list --post_type=page --pagename='sample-page' --field=ID --format=ids || true)" || true

#   local home_id
#   home_id=$(wp post create --post_type=page --post_title="Home" --post_status=publish --porcelain)
#   wp option update show_on_front 'page'
#   wp option update page_on_front "$home_id"

#   for page in About Contact Services Blog; do
#     wp post create --post_type=page --post_status=publish --post_title="$page" --porcelain
#   done

#   wp menu create "Main Navigation" || true
#   for pid in $(wp post list --orderby=date --post_type=page --post_status=publish --field=ID); do
#     wp menu item add-post main-navigation "$pid"
#   done
#   wp menu location assign main-navigation primary
#   wp rewrite structure '/%postname%/' && wp rewrite flush
#   wp plugin delete akismet hello || true
# }

# # --- Main ---
# main() {
#   [[ "$(uname)" == "Darwin" ]] || err "This script must be run on macOS"

#   init
#   install_php
#   install_pkgs
#   install_laravel_valet
#   setup_bedrock_valet
#   install_theme
#   post_install_config

#   success "🎉 WordPress Bedrock site with Sage theme is ready at https://$PROJECT_NAME.test"
# }

# main "$@"

# #!/usr/bin/env bash

# # ╭────────────────────────────────────────────────────────────────────────────╮
# # │ Easy Bedrock Project Builder for macOS                                     │
# # │ Stack: WordPress, wp-cli, Valet, MySQL/MariaDB, Redis, Mailhog             │
# # │ Author: zx0r                                                               │
# # ╰────────────────────────────────────────────────────────────────────────────╯

# set -euo pipefail

# # ╭───────────────────────────────────────╮
# # │ Constants and Configuration           │
# # ╰───────────────────────────────────────╯

# : "${PHP_VERSION:=8.2}"     # PHP version (default: 8.2)
# : "${DB_ENGINE:=mysql}"     # Database engine: mysql | mariadb
# : "${DB_VERSION:=}"         # Database version (empty = latest)
# : "${WEB_SERVER:=nginx}"    # Web server: nginx | apache
# : "${WEB_SERVER_VERSION:=}" # Web server version (empty = latest)

# : "${PROJECT_NAME:=xclean}"                      # Project name (default: xclean)
# : "${PROJECTS_DIR:=$HOME/sites}"                 # Directory for all local projects
# : "${PROJECT_PATH:=$PROJECTS_DIR/$PROJECT_NAME}" # Full path to the project
# : "${WEBROOT:=$PROJECT_PATH/web}"                # Web root directory (Bedrock: usually /web)

# : "${DB_NAME:=$PROJECT_NAME}" # Database name
# : "${DB_USER:=root}"          # Database user
# : "${DB_PASS:=}"              # Database password
# : "${DB_HOST:=127.0.0.1}"     # Database host
# # : "${DB_PREFIX:=$(LC_ALL=C tr -dc '[:lower:]' </dev/urandom | head -c6)_}" # Random 6-char prefix, e.g., `kzyaqz_`

# : "${WP_ENV:=development}"         # WordPress environment: development | staging | production
# : "${WP_HOME:=$PROJECT_NAME.test}" # WordPress home URL
# : "${WP_SITEURL:=$WP_HOME/wp}"     # WordPress site URL (Bedrock: /wp)

# : "${WP_TITLE:=dev}"                                                                                       # WordPress site title
# : "${WP_ADMIN:=admin}"                                                                                     # WordPress admin username
# : "${WP_ADMIN_PASS:=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9!@#$%^&*()_+[]{}|:,.<>?~' | head -c 64)}" # Random strong password
# : "${WP_ADMIN_EMAIL:=admin@local.test}"                                                                    # WordPress admin email

# : "${WP_THEME_NAME:=sage}"                              # Default theme name (usually Sage for Bedrock)
# : "${WP_THEME_PATH:=web/app/themes/$PROJECT_NAME}"      # Theme path relative to Bedrock
# : "${WP_THEME_REPO:=https://github.com/roots/sage.git}" # Git repo for theme installation

# : "${ENABLE_SSL:=true}"     # Enable HTTPS (Valet secure)
# : "${ENABLE_CACHE:=true}"   # Enable Redis
# : "${ENABLE_XDEBUG:=true}"  # Enable Xdebug
# : "${ENABLE_MAILHOG:=true}" # Enable Mailhog

# : "${CACHE_ENGINE:=redis}" # Cache engine: redis | memcached | none
# : "${CACHE_ENABLED:=true}" # Enable object cache: true | false

# : "${REDIS_HOST:=127.0.0.1}"     # Redis host
# : "${REDIS_PORT:=6379}"          # Redis port
# : "${MEMCACHED_HOST:=127.0.0.1}" # Memcached host
# : "${MEMCACHED_PORT:=11211}"     # Memcached port
# : "${MAILHOG_PORT:=8025}"        # Mailhog port

# declare -A DB_PACKAGES=([mysql]="mysql" [mariadb]="mariadb")
# declare -A WEB_PACKAGES=([nginx]="nginx" [apache]="httpd")

# # ╭───────────────────────────────────────╮
# # │ UTILITY FUNCTIONS                     │
# # ╰───────────────────────────────────────╯

# log() { echo -e "\033[34m[➤ ]\033[0m $*"; }
# warn() { echo -e "\033[33m[!]\033[0m $*"; }
# success() { echo -e "\033[32m[✓ ]\033[0m $*"; }
# error() {
#   echo -e "\033[31m[✗ ] $*\033[0m" >&2
#   exit 1
# }

# # ╭───────────────────────────────────────╮
# # │ Check Platform                        │
# # ╰───────────────────────────────────────╯

# check_platform() {
#   [[ $(uname) = "Darwin" ]] || error "This script must be run on macOS"

#   if ! xcode-select -p >/dev/null 2>&1; then
#     xcode-select --install || true
#   fi
#   if ! command -v brew >/dev/null; then
#     /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
#   fi
# }

# # ╭───────────────────────────────────────╮
# # │ Install PHP                           │
# # ╰───────────────────────────────────────╯

# install_php() {
#   sudo chown -R "$(whoami)":admin "$(brew --prefix)/opt" || true
#   sudo chown -R "$(whoami)":admin "$(brew --prefix)/Cellar" || true
#   sudo chown -R "$(whoami)":admin "$(brew --prefix)/var/homebrew/linked" || true

#   brew tap shivammathur/php 2>/dev/null || true
#   brew list --formula | grep -Fxq "php@${PHP_VERSION}" || brew install "shivammathur/php/php@${PHP_VERSION}"
#   brew unlink php || true
#   brew link --overwrite --force "php@${PHP_VERSION}"
# }

# # ╭───────────────────────────────────────╮
# # │ INSTALL SERVICES                      │
# # ╰───────────────────────────────────────╯

# install_brew_packages() {
#   local pkgs=(
#     composer node yarn wp-cli mkcert nss openssl brew-php-switcher
#     "${DB_PACKAGES[$DB_ENGINE]}${DB_VERSION}"
#     "${WEB_PACKAGES[$WEB_SERVER]}${WEB_SERVER_VERSION}"
#     redis mailhog
#   )

#   for pkg in "${pkgs[@]}"; do
#     [[ -n "$pkg" ]] || continue
#     if ! brew list --versions "$pkg" >/dev/null 2>&1; then
#       log "Installing: $pkg"
#       brew install "$pkg"
#     fi
#   done
# }

# # ╭───────────────────────────────────────╮
# # │  WP-CLI Packages & Plugins            │
# # ╰───────────────────────────────────────╯

# install_wp_packages() {
#   local wp_packages=(
#     "aaemnnosttv/wp-cli-valet-command:@stable"
#     "aaemnnosttv/wp-cli-dotenv-command:@stable"
#     "aaemnnosttv/wp-cli-login-command:@stable"
#   )

#   # Get the list of currently installed WP-CLI packages
#   local installed_pkgs
#   installed_pkgs="$(wp package list --field=name 2>/dev/null || true)"

#   for pkg in "${wp_packages[@]}"; do
#     if ! grep -Fxq "$pkg" <<<"$installed_pkgs"; then
#       log "Installing WP package: $pkg"
#       wp package install "$pkg"
#     fi
#   done
# }

# install_wp_plugins() {
#   local wp_plugins=(
#     "query-monitor"
#     "wp-redis/wp-redis"
#     "wpackagist-plugin/wp-mail-smtp"
#     "wpackagist-plugin/wp-migrate-db"
#     "wpackagist-plugin/debug-bar"
#   )

#   log "Installing default WordPress plugins..."

#   for plugin in "${wp_plugins[@]}"; do
#     if ! wp plugin is-installed "$plugin"; then
#       wp plugin install "$plugin" --activate >/dev/null
#     fi
#   done
# }

# # ╭───────────────────────────────────────╮
# # │ Laravel VALET                         │
# # ╰───────────────────────────────────────╯

# install_laravel_valet() {
#   local bin_dir
#   bin_dir=$(composer global config bin-dir --absolute)

#   composer global require laravel/valet
#   [[ ":$PATH:" != *":$bin_dir:"* ]] && export PATH="$PATH:$bin_dir"
#   grep -q "$bin_dir" "$HOME/.config/fish/config.fish" || echo "fish_add_path $bin_dir" >>"$HOME/.config/fish/config.fish"

#   valet install || error "Valet install failed"
#   valet trust || error "Valet trust failed"
# }

# # ╭───────────────────────────────────────╮
# # │ DATABASE SETUP                        │
# # ╰───────────────────────────────────────╯

# check_and_create_db() {
#   MYSQL_ARGS=(-u"$DB_USER" -h "$DB_HOST")
#   [ -n "$DB_PASS" ] && MYSQL_ARGS+=(-p"$DB_PASS")
#   if echo "USE $DB_NAME;" | mysql "${MYSQL_ARGS[@]}" 2>/dev/null; then
#     warn "Database '$DB_NAME' already exists. Dropping and recreating."
#     mysql "${MYSQL_ARGS[@]}" -e "DROP DATABASE $DB_NAME;"
#   fi
#   # mysql "${MYSQL_ARGS[@]}" -e "CREATE DATABASE $DB_NAME;" || error "Failed to create DB"
#   # success "Database '$DB_NAME' created."
# }

# # check_and_create_db() {
# #   # Function to check if the database exists
# #   check_db_exists() {
# #     mysql -u "$DB_USER" -p"$DB_PASS" -h "$DB_HOST" -e "USE $DB_NAME;" >/dev/null 2>&1
# #   }

# #   if check_db_exists; then
# #     error "Database '$DB_NAME' already exists."
# #   else
# #     if mysql -u "$DB_USER" -p"$DB_PASS" -h "$DB_HOST" -e "CREATE DATABASE $DB_NAME;"; then
# #       success "Database '$DB_NAME' successfully created."
# #     else
# #       error "Failed to create database '$DB_NAME'."
# #     fi
# #   fi
# # }

# db_ensure_running() {
#   case "$DB_ENGINE" in
#   mysql) brew services start mysql ;;
#   mariadb) brew services start mariadb ;;
#   *) error "Unsupported DB_ENGINE: $DB_ENGINE" ;;
#   esac
# }

# # ╭───────────────────────────────────────╮
# # │ Environment Configuration             │
# # ╰───────────────────────────────────────╯

# setup_env_variables() {
#   log "🔧 Setting WordPress and DB environment variables"

#   if [[ ! -d "$PROJECT_PATH" ]]; then
#     mkdir -p "$PROJECT_PATH"
#     log "Created: $PROJECTS_DIR and $PROJECT_PATH"
#   else
#     error "Skipped: $PROJECT_PATH already exists"
#   fi

#   cd "$WEBROOT" || error "Failed to cd into $WEBROOT"
#   [ -f .env ] || cp .env.example .env

#   wp dotenv set DB_NAME "$DB_NAME" --quiet
#   wp dotenv set DB_USER "$DB_USER" --quiet
#   wp dotenv set DB_PASSWORD "$DB_PASS" --quiet
#   wp dotenv set DB_HOST "$DB_HOST" --quiet
#   # wp dotenv set DB_PREFIX "$DB_PREFIX" --quiet

#   wp dotenv set WP_ENV "$WP_ENV" --quiet
#   wp dotenv set WP_HOME "$WP_HOME" --quiet
#   wp dotenv set WP_SITEURL "$WP_SITEURL" --quiet
#   wp dotenv set WP_TITLE "$WP_TITLE" --quiet
#   wp dotenv set WP_ADMIN_USER "$WP_ADMIN" --quiet
#   wp dotenv set WP_ADMIN_EMAIL "$WP_ADMIN_EMAIL" --quiet
#   #wp dotenv set WP_THEME "$WP_THEME_NAME" --quiet

#   log "🔐 Generating security salts..."
#   wp dotenv salts generate --quiet

#   log "📄 .env file content:"
#   wp dotenv list

#   success "✅ Site created and .env configured at $WEBROOT"
#   echo "$WP_ADMIN_PASS" | pbcopy
#   log "🔑 Admin password copied to clipboard."
# }

# setup_new_project() {
#   log "🛠️ Creating Bedrock site with wp valet new..."

#   cd "$PROJECT_PATH" || error "Failed to cd into $PROJECT_PATH"

#   valet park "$PROJECTS_DIR" || error "Failed to park Valet in $PROJECTS_DIR"
#   valet link --secure "$PROJECT_NAME" || error "Failed to link project $PROJECT_NAME with Valet"

#   wp valet new "$PROJECT_NAME" \
#     --project=bedrock \
#     --in="$PROJECT_PATH" \
#     --admin_user="$WP_ADMIN" \
#     --admin_password="$WP_ADMIN_PASS" \
#     --admin_email="$WP_ADMIN_EMAIL" || error "wp valet new failed"

#   success "Successfully created Bedrock site: $PROJECT_NAME"
# }

# install_wordpress_theme() {
#   local theme_name="$WP_THEME_NAME"
#   local theme_path="$PROJECT_PATH/web/app/themes/$theme_name"

#   if [[ -z "$theme_name" ]]; then
#     error "Theme name is required."
#   fi

#   log "🛠️ Installing WordPress theme: $theme_name"

#   if [[ ! -d "$theme_path" ]]; then
#     log "📁 Installing theme $theme_name"
#     composer create-project roots/sage "$theme_path" || error "Failed to create theme $theme_name with Composer"
#   else
#     log "📁 Theme directory for $theme_name already exists."
#   fi

#   cd "$theme_path" || error "Failed to cd into $theme_path"

#   log "📦 Installing Composer dependencies for $theme_name"
#   composer install --no-ansi --no-dev --no-interaction --no-progress --optimize-autoloader --no-scripts || error "Composer install failed for theme $theme_name"

#   log "📦 Installing NPM dependencies for $theme_name"
#   npm install || error "NPM install failed for theme $theme_name"

#   log "🎨 Compiling assets for theme $theme_name"
#   npm run build || error "Asset compilation failed for theme $theme_name"

#   log "📝 Activating theme in WordPress"
#   wp theme activate "$theme_name" || error "Failed to activate theme $theme_name"

#   log "✅ Theme $theme_name successfully installed and activated."
# }

# post_install_config() {
#   log "Running post-install WordPress config..."

#   wp option update blog_public 0
#   wp option update posts_per_page 6

#   wp post delete "$(wp post list --post_type=page --pagename='sample-page' --field=ID --format=ids || true)" || true

#   local home_id
#   home_id=$(wp post create --post_type=page --post_title="Home" --post_status=publish --porcelain)
#   wp option update show_on_front 'page'
#   wp option update page_on_front "$home_id"

#   for page in About Contact Services Blog; do
#     wp post create --post_type=page --post_status=publish --post_title="$page" --porcelain
#   done

#   wp menu create "Main Navigation" || true
#   for pid in $(wp post list --orderby=date --post_type=page --post_status=publish --field=ID); do
#     wp menu item add-post main-navigation "$pid"
#   done
#   wp menu location assign main-navigation primary
#   wp rewrite structure '/%postname%/' && wp rewrite flush
#   wp plugin delete akismet hello || true
# }

# show_summary() {
#   # Define colors for terminal output
#   local GREEN='\033[0;32m'
#   local BLUE='\033[0;34m'
#   local WHITE='\033[0;37m'
#   local NC='\033[0m' # No Color

#   # Display project summary with formatting
#   echo -e "\n${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
#   echo -e "${GREEN}║${NC}                     🎉 Installation Complete! 🎉                   ${GREEN}║${NC}"
#   echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}"

#   echo -e "\n${BLUE}📋 Project Summary:${NC}"

#   echo -e "   ${WHITE}Project Name:${NC} $PROJECT_NAME"
#   echo -e "   ${WHITE}PHP Version:${NC} $PHP_VERSION"
#   echo -e "   ${WHITE}Database:${NC} $DB_ENGINE $DB_VERSION"
#   echo -e "   ${WHITE}Web Server:${NC} $WEB_SERVER $WEB_SERVER_VERSION"
#   echo -e "   ${WHITE}Cache:${NC} $CACHE_ENGINE"
#   echo -e "   ${WHITE}Cache Enabled:${NC} $CACHE_ENABLED"
#   echo -e "   ${WHITE}URL:${NC} https://$WP_HOME"
#   echo -e "   ${WHITE}Webroot:${NC} $WEBROOT"
#   echo -e "   ${WHITE}Mailhog:${NC} http://localhost:$MAILHOG_PORT"
#   echo -e "   ${WHITE}Redis:${NC} $REDIS_HOST:$REDIS_PORT"
#   echo -e "   ${WHITE}Xdebug:${NC} $(php -m | grep -q xdebug && echo "enabled" || echo "not enabled")"
#   echo -e "   ${WHITE}Theme:${NC} $WP_THEME_NAME"
#   echo -e "   ${WHITE}Admin Username:${NC} $WP_ADMIN"
#   echo -e "   ${WHITE}Admin Email:${NC} $WP_ADMIN_EMAIL"

#   echo -e "\n${GREEN}Happy coding! 🚀${NC}\n"
# }

# main() {
#   check_platform
#   check_and_create_db
#   #db_ensure_running
#   install_php
#   install_brew_packages
#   install_wp_packages
#   install_laravel_valet
#   setup_new_project
#   setup_env_variables
#   install_wordpress_theme
#   #post_install_config
#   #install_wp_plugins

#   echo "Visit: $(wp option get siteurl)"
#   show_summary
#   success "🎉 WordPress Bedrock site with Sage theme is ready at https://$WP_HOME"
# }

# main "$@"

# #!/usr/bin/env bash

# # set -euo pipefail

# # ╭────────────────────────────────────────────────────────────────────────────╮
# # │ Easy Bedrock Project Builder for macOS                                     │
# # │ Stack: WordPress, wp-cli, Valet, MySQL/MariaDB, Redis, Mailhog             │
# # │ Author: zx0r                                                               │
# # ╰────────────────────────────────────────────────────────────────────────────╯

# # ╭───────────────────────────────────────╮
# # │ Constants and Configuration           │
# # ╰───────────────────────────────────────╯

# : "${PHP_VERSION:=8.4}"     # PHP version (empty = latest)
# : "${DB_ENGINE:=mysql}"     # Database engine: mysql | mariadb
# : "${DB_VERSION:=}"         # Database version (empty = latest)
# : "${WEB_SERVER:=nginx}"    # Web server: nginx | apache
# : "${WEB_SERVER_VERSION:=}" # Web server version (empty = latest)

# : "${PROJECT_NAME:=xclean}"                      # Project name (default: xclean)
# : "${PROJECTS_DIR:=$HOME/sites}"                 # Directory for all local projects
# : "${PROJECT_PATH:=$PROJECTS_DIR/$PROJECT_NAME}" # Full path to the project
# : "${WEBROOT:=$PROJECT_PATH/web}"                # Web root directory (Bedrock: usually /web)

# : "${DB_NAME:=$PROJECT_NAME}"                                              # Database name
# : "${DB_USER:=root}"                                                       # Database user
# : "${DB_PASS:=}"                                                           # Database password
# : "${DB_HOST:=127.0.0.1}"                                                  # Database host
# : "${DB_PREFIX:=$(LC_ALL=C tr -dc '[:lower:]' </dev/urandom | head -c6)_}" # Random 6-char prefix, e.g., `kzyaqz_`

# : "${WP_ENV:=development}"         # WordPress environment: development | staging | production
# : "${WP_HOME:=$PROJECT_NAME.test}" # WordPress home URL
# : "${WP_SITEURL:=$WP_HOME/wp}"     # WordPress site URL (Bedrock: /wp)

# : "${WP_TITLE:=dev}"                                                                                       # WordPress site title
# : "${WP_ADMIN:=admin}"                                                                                     # WordPress admin username
# : "${WP_ADMIN_PASS:=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9!@#$%^&*()_+[]{}|:,.<>?~' | head -c 64)}" # Random strong password
# : "${WP_ADMIN_EMAIL:=admin@local.test}"                                                                    # WordPress admin email

# : "${WP_THEME_NAME:=sage}"                              # Default theme name (usually Sage for Bedrock)
# : "${WP_THEME_PATH:=web/app/themes/$PROJECT_NAME}"      # Theme path relative to Bedrock
# : "${WP_THEME_REPO:=https://github.com/roots/sage.git}" # Git repo for theme installation

# : "${ENABLE_SSL:=true}"               # Enable HTTPS (Valet secure)
# : "${ENABLE_CACHE:=true}"             # Enable Redis
# : "${ENABLE_XDEBUG:=true}"            # Enable Xdebug
# : "${ENABLE_MAILHOG:=true}"           # Enable Mailhog

# : "${CACHE_ENGINE:=redis}"            # Cache engine: redis | memcached | none
# : "${CACHE_ENABLED:=true}"            # Enable object cache: true | false

# : "${REDIS_HOST:=127.0.0.1}"           # Redis host
# : "${REDIS_PORT:=6379}"                 # Redis port
# : "${MEMCACHED_HOST:=127.0.0.1}"        # Memcached host
# : "${MEMCACHED_PORT:=11211}"            # Memcached port

# declare -A DB_PACKAGES=([mysql]="mysql" [mariadb]="mariadb") # Brew packages for DB engines
# declare -A WEB_PACKAGES=([nginx]="nginx" [apache]="httpd")   # Brew packages for web servers

# # ╭───────────────────────────────────────╮
# # │ UTILITY FUNCTIONS                     │
# # ╰───────────────────────────────────────╯

# log() { echo -e "\033[34m[➤ ]\033[0m $*"; }
# warn() { echo -e "\033[33m[!]\033[0m $*"; }
# success() { echo -e "\033[32m[✓ ]\033[0m $*"; }
# error() {
#   echo -e "\033[31m[✗ ] $*\033[0m" >&2
#   exit 1
# }

# # ╭───────────────────────────────────────╮
# # │ Check Platform                        │
# # ╰───────────────────────────────────────╯

# check_platform() {
#   [[ $(uname) = "Darwin" ]] || error "This script must be run on macOS"

#   xcode-select -p >/dev/null 2>&1 || xcode-select --install || true
#   command -v brew >/dev/null || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# }

# # ╭───────────────────────────────────────╮
# # │ Install PHP                           │
# # ╰───────────────────────────────────────╯

# install_php() {
#   sudo chown -R "$(whoami)":admin "$(brew --prefix)/opt" || true
#   sudo chown -R "$(whoami)":admin "$(brew --prefix)/Cellar" || true
#   sudo chown -R "$(whoami)":admin "$(brew --prefix)/var/homebrew/linked" || true

#   brew tap shivammathur/php 2>/dev/null
#   brew install shivammathur/php/php@8.4
#   brew unlink php
#   brew link --overwrite --force shivammathur/php/php@8.4

#   # brew list --formula | grep -Fxq "php@${PHP_VERSION}" || brew install "php@${PHP_VERSION}"
#   # brew list --formula | grep -Fxq "php" && brew unlink php
#   # brew link --overwrite --force "php@${PHP_VERSION}" && echo "PHP $PHP_VERSION linked"
# }

# # ╭───────────────────────────────────────╮
# # │ INSTALL SERVICES                      │
# # ╰───────────────────────────────────────╯

# install_brew_packages() {
#   local pkgs=(
#     composer node yarn wp-cli mkcert nss openssl brew-php-switcher
#     "${DB_PACKAGES[$DB_ENGINE]}${DB_VERSION}"
#     "${WEB_PACKAGES[$WEB_SERVER]}${WEB_SERVER_VERSION}"
#   )

#   for pkg in "${pkgs[@]}"; do
#     [[ -n "$pkg" ]] || continue # Skip empty/null values
#     brew list --versions "$pkg" >/dev/null 2>&1 || log "Installing: $pkg"
#     brew install "$pkg"
#   done

#   #  npm install -g gulp-cli bower || true
#   # pecl install xdebug redis || true

#   # # Database version management tool
#   # brew install --cask dbngin || true

#   # # PHP version management tool
#   # brew tap nicoverbruggen/homebrew-cask || true
#   # brew install --cask phpmon || true
# }

# # ╭───────────────────────────────────────╮
# # │  WP-CLI Packages & Plugins            │
# # ╰───────────────────────────────────────╯

# install_wp_packages() {
#   local wp_packages=(
#     "aaemnnosttv/wp-cli-valet-command:@stable"
#     "aaemnnosttv/wp-cli-dotenv-command:@stable"
#     "aaemnnosttv/wp-cli-login-command:@stable"
#   )

#   # Get the list of currently installed WP-CLI packages
#   local installed_pkgs
#   installed_pkgs="$(wp package list --field=name 2>/dev/null || true)"

#   for pkg in "${wp_packages[@]}"; do
#     if grep -Fxq "$pkg" <<<"$installed_pkgs"; then
#       echo "[+] Installing WP package: $pkg"
#       wp package install "$pkg"
#     fi
#   done
# }

# install_wp_plugins() {
#   local wp_plugins=(
#     "query-monitor"
#     "wp-redis/wp-redis"
#     "wpackagist-plugin/wp-mail-smtp"
#     "wpackagist-plugin/wp-migrate-db"
#     "wpackagist-plugin/debug-bar"
#   )

#   log "Installing default WordPress plugins..."

#   for plugin in "${wp_plugins[@]}"; do
#     if ! wp plugin is-installed "$plugin"; then
#       wp plugin install "$plugin" --activate >/dev/null
#     fi
#   done
# }

# # ╭───────────────────────────────────────╮
# # │ Laravel VALET                         │
# # ╰───────────────────────────────────────╯

# install_laravel_valet() {
#   local bin_dir
#   bin_dir=$(composer global config bin-dir --absolute)

#   composer global require laravel/valet
#   [[ ":$PATH:" != *":$bin_dir:"* ]] && export PATH="$PATH:$bin_dir"
#   grep -q "$bin_dir" "$HOME/.config/fish/config.fish" || echo "fish_add_path $bin_dir" >>"$HOME/.config/fish/config.fish"

#   valet install || error "Valet install failed"
#   valet trust || error "Valet trust failed"
# }

# # ╭───────────────────────────────────────╮
# # │ DATABASE SETUP                        │
# # ╰───────────────────────────────────────╯

# check_and_create_db() {
#   # Function to check if the database exists
#   check_db_exists() {
#     "$DB_ENGINE" -u "$DB_USER" -p"$DB_PASS" -h "$DB_HOST" -e "USE $DB_NAME;" >/dev/null 2>&1
#   }

#   # Check if the database exists
#   if check_db_exists; then
#     error "Database '$DB_NAME' already exists."
#   else
#     # Create the database
#     if "$DB_ENGINE" -u "$DB_USER" -p"$DB_PASS" -h "$DB_HOST" -e "CREATE DATABASE $DB_NAME;"; then
#       success "Database '$DB_NAME' successfully created."
#     else
#       error "Failed to create database '$DB_NAME'."
#     fi
#   fi
# }

# db_ensure_running() {
#   case "$DB_ENGINE" in
#   mysql) mysql.server status | grep -q 'not running' && mysql.server start ;;
#   mariadb) systemctl is-active --quiet mariadb || systemctl start mariadb ;;
#   *) error "Unsupported DB_ENGINE: $DB_ENGINE" ;;
#   esac
# }
# # ╭───────────────────────────────────────╮
# # │ Environment Configuration             │
# # ╰───────────────────────────────────────╯

# setup_env_variables() {
#   log "🔧 Setting WordPress and DB environment variables"
#   cd "$WEBROOT" || error "Failed to cd into $WEBROOT"
#   [ -f .env ] || cp .env.example .env

#   # Database configuration
#   wp dotenv set DB_NAME "$DB_NAME" --quiet
#   wp dotenv set DB_USER "$DB_USER" --quiet
#   wp dotenv set DB_PASSWORD "$DB_PASS" --quiet
#   wp dotenv set DB_HOST "$DB_HOST" --quiet
#   wp dotenv set DB_PREFIX "$DB_PREFIX" --quiet

#   # WordPress site configuration
#   wp dotenv set WP_ENV "$WP_ENV" --quiet
#   wp dotenv set WP_HOME "$WP_HOME" --quiet
#   wp dotenv set WP_SITEURL "$WP_SITEURL" --quiet
#   wp dotenv set WP_TITLE "$WP_TITLE" --quiet
#   wp dotenv set WP_ADMIN_USER "$WP_ADMIN" --quiet
#   wp dotenv set WP_ADMIN_EMAIL "$WP_ADMIN_EMAIL" --quiet
#   wp dotenv set WP_THEME "$WP_THEME_NAME" --quiet

#   # Optional: Enable debug, Redis, MailHog, Xdebug
#   # wp dotenv set CACHE_TYPE     "$CACHE_TYPE"     --quiet
#   # wp dotenv set ENABLE_XDEBUG  "$ENABLE_XDEBUG"  --quiet
#   # wp dotenv set ENABLE_MAILHOG "$ENABLE_MAILHOG" --quiet
#   # wp dotenv set SSL_ENABLED    "$SSL_ENABLED"    --quiet
#   # wp dotenv set REDIS_PORT     "$REDIS_PORT"     --quiet
#   # wp dotenv set MAILHOG_PORT   "$MAILHOG_PORT"   --quiet
#   # wp dotenv set PHP_VERSION    "$PHP_VERSION"    --quiet
#   # wp dotenv set DB_ENGINE      "$DB_ENGINE"      --quiet
#   # wp dotenv set SERVER_TYPE    "$SERVER_TYPE"    --quiet

#   # Secure random salts
#   log "🔐 Generating security salts..."
#   wp dotenv salts generate --quiet

#   # Optional: review .env content
#   log "📄 .env file content:"
#   wp dotenv list

#   success "✅ Site created and .env configured at $WEBROOT"
#   echo "$WP_ADMIN_PASS" | pbcopy
#   log "🔑 Admin password copied to clipboard."
# }

# # # ╭───────────────────────────────────────╮
# # # │ PROJECT BOOTSTRAP                     │
# # # ╰───────────────────────────────────────╯

# setup_new_project() {
#   log "🛠️ Creating Bedrock site with wp valet new..."

#   # Ensure project directory exists
#   if [[ ! -d "$PROJECT_PATH" ]]; then
#     mkdir -p "$PROJECT_PATH/valet"
#     log "Created: $PROJECTS_DIR and $PROJECT_PATH"
#   else
#     error "Skipped: $PROJECT_PATH already exists"
#   fi

#   # Change to the project directory
#   cd "$PROJECT_PATH" || error "Failed to cd into $PROJECT_PATH"

#   # Run Valet commands
#   valet park "$PROJECTS_DIR" || error "Failed to park Valet in $PROJECTS_DIR"
#   valet link --secure "$PROJECT_NAME" || error "Failed to link project $PROJECT_NAME with Valet"

#   # Install Bedrock using wp valet new
#   wp valet new "$PROJECT_NAME" \
#     --project=bedrock \
#     --in="$PROJECT_PATH" \
#     --admin_user="$WP_ADMIN" \
#     --admin_password="$WP_ADMIN_PASS" \
#     --admin_email="$WP_ADMIN_EMAIL" || error "wp valet new failed"

#   success "Successfully created Bedrock site: $PROJECT_NAME"
# }

# # # ╭───────────────────────────────────────╮
# # # │ SAGE THEME INSTALL & ACTIVATION       │
# # # ╰───────────────────────────────────────╯

# install_wordpress_theme() {
#   local theme_name="$WP_THEME_NAME"
#   local theme_path="$WP_WEBROOT/app/themes/$theme_name"

#   # Validate that WP_THEME_NAME is provided
#   if [[ -z "$theme_name" ]]; then
#     error "Theme name is required."
#   fi

#   log "🛠️ Installing WordPress theme: $theme_name"

#   # Create the theme directory and install Sage theme via Composer if it doesn't exist
#   if [[ ! -d "$theme_path" ]]; then
#     log "📁 Installing theme $theme_name"
#     composer create-project roots/sage "$theme_path" || error "Failed to create theme $theme_name with Composer"
#   else
#     log "📁 Theme directory for $theme_name already exists."
#   fi

#   cd "$theme_path" || error "Failed to cd into $theme_path"

#   # Install Composer dependencies after theme creation
#   log "📦 Installing Composer dependencies for $theme_name"
#   composer install --no-ansi --no-dev --no-interaction --no-progress --optimize-autoloader --no-scripts || error "Composer install failed for theme $theme_name"

#   # Install NPM dependencies
#   log "📦 Installing NPM dependencies for $theme_name"
#   npm install || error "NPM install failed for theme $theme_name"

#   # Compile assets
#   log "🎨 Compiling assets for theme $theme_name"
#   npm run build || error "Asset compilation failed for theme $theme_name"

#   # Activate the theme in WordPress
#   log "📝 Activating theme in WordPress"
#   wp theme activate "$theme_name" || error "Failed to activate theme $theme_name"

#   log "✅ Theme $theme_name successfully installed and activated."
# }

# post_install_config() {
#   log "Running post-install WordPress config..."

#   wp option update blog_public 0
#   wp option update posts_per_page 6

#   wp post delete "$(wp post list --post_type=page --pagename='sample-page' --field=ID --format=ids || true)" || true

#   local home_id
#   home_id=$(wp post create --post_type=page --post_title="Home" --post_status=publish --porcelain)
#   wp option update show_on_front 'page'
#   wp option update page_on_front "$home_id"

#   for page in About Contact Services Blog; do
#     wp post create --post_type=page --post_status=publish --post_title="$page" --porcelain
#   done

#   wp menu create "Main Navigation" || true
#   for pid in $(wp post list --orderby=date --post_type=page --post_status=publish --field=ID); do
#     wp menu item add-post main-navigation "$pid"
#   done
#   wp menu location assign main-navigation primary
#   wp rewrite structure '/%postname%/' && wp rewrite flush
#   wp plugin delete akismet hello || true
# }

# # # ╭───────────────────────────────────────╮
# # # │ BANNER                                │
# # # ╰───────────────────────────────────────╯

# # show_banner() {
# #   echo -e "${PURPLE}"
# #   cat <<'EOF'
# # ╔═══════════════════════════════════════════════════════════════════╗
# # ║                                                                   ║
# # ║    🚀 Professional Development Environment Installer v2.0.0       ║
# # ║                                                                   ║
# # ║    Features:                                                      ║
# # ║    • Multiple PHP versions & frameworks support                   ║
# # ║    • Database management (MySQL, MariaDB)                         ║
# # ║    • Caching solutions (Redis, Memcached)                         ║
# # ║    • Development tools (Xdebug, MailHog)                          ║
# # ║    • Security & monitoring                                        ║
# # ║    • Telegram notifications                                       ║
# # ║    • SSL certificates                                             ║
# # ║                                                                   ║
# # ╚═══════════════════════════════════════════════════════════════════╝
# # EOF
# #   echo -e "${NC}"
# # }

# show_summary() {
#   # Define colors for terminal output
#   local GREEN='\033[0;32m'
#   local BLUE='\033[0;34m'
#   local WHITE='\033[0;37m'
#   local NC='\033[0m' # No Color

#   # Display project summary with formatting
#   echo -e "\n${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
#   echo -e "${GREEN}║${NC}                     🎉 Installation Complete! 🎉                   ${GREEN}║${NC}"
#   echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}"

#   echo -e "\n${BLUE}📋 Project Summary:${NC}"

#   echo -e "   ${WHITE}Project Name:${NC} $PROJECT_NAME"
#   echo -e "   ${WHITE}PHP Version:${NC} $PHP_VERSION"
#   echo -e "   ${WHITE}Database:${NC} $DB_ENGINE $DB_VERSION"
#   echo -e "   ${WHITE}Web Server:${NC} $WEB_SERVER $WEB_SERVER_VERSION"
#   echo -e "   ${WHITE}Cache:${NC} $CACHE_ENGINE"
#   echo -e "   ${WHITE}Cache Enabled:${NC} $CACHE_ENABLED"
#   echo -e "   ${WHITE}URL:${NC} https://$WP_HOME"
#   echo -e "   ${WHITE}Webroot:${NC} $WEBROOT"
#   echo -e "   ${WHITE}Mailhog:${NC} http://localhost:$MAILHOG_PORT"
#   echo -e "   ${WHITE}Redis:${NC} $REDIS_HOST:$REDIS_PORT"
#   echo -e "   ${WHITE}Xdebug:${NC} $(php -m | grep -q xdebug && echo "enabled" || echo "not enabled")"
#   echo -e "   ${WHITE}Theme:${NC} $WP_THEME_NAME"
#   echo -e "   ${WHITE}Admin Username:${NC} $WP_ADMIN"
#   echo -e "   ${WHITE}Admin Email:${NC} $WP_ADMIN_EMAIL"

#   echo -e "\n${GREEN}Happy coding! 🚀${NC}\n"
# }

# # # Hints
# # help() {
# # - To add more plugins/themes, extend the DEFAULT_PLUGINS array or add more steps.
# # - For custom Valet PHP versions, adjust PHP_VERSION and rerun valet isolate.
# # - If you hit permissions issues with Composer/npm, ensure $PATH includes composer global bin and npm global bin.
# # - Use `wp shell` or `wp db cli` for advanced troubleshooting inside the Bedrock project.
# # - Script is safe to run repeatedly; it skips already-done steps (idempotent).
# # }

# # # ╭───────────────────────────────────────╮
# # # │ REDIS CONFIGURATION                   │
# # # ╰───────────────────────────────────────╯

# # configure_redis() {
# #   grep -q "WP_REDIS" .env || {
# #     echo -e "WP_REDIS_HOST=127.0.0.1\nWP_REDIS_PORT=$REDIS_PORT" >>.env
# #   }
# # }

# # # ╭───────────────────────────────────────╮
# # # │ XDEBUG                                │
# # # ╰───────────────────────────────────────╯

# # enable_xdebug() {
# #   log "🐞 Enabling Xdebug…"
# #   php -m | grep -q xdebug && return
# #   local ini_file
# #   ini_file=$(php -i | awk -F'=> ' '/Loaded Configuration File/ {print $2}')
# #   local xdebug_so
# #   xdebug_so=$(find /usr/local/lib -name xdebug.so | head -n 1)
# #   [ -n "$xdebug_so" ] && echo "zend_extension=\"$xdebug_so\"" | sudo tee -a "$ini_file"
# #   sudo bash -c "echo 'xdebug.mode=develop,debug' >> $ini_file"
# # }

# # # ╭─────────────╮
# # # │ Main Flow   │
# # # ╰─────────────╯

# main() {

#   check_platform
#   # check_and_create_db
#   #db_ensure_running

#   install_php
#   install_brew_packages
#   install_wp_packages
#   # install_wp_plugins
#   install_laravel_valet
#   setup_new_project
#   setup_env_variables
#   install_wordpress_theme
#   # post_install_config

#   echo "Visit: $(wp option get siteurl)"

#   show_summary
#   success "🎉 WordPress Bedrock site with Sage theme is ready at https://$WP_HOME"
# }

# main "$@"
