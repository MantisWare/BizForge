#!/usr/bin/env bash
set -euo pipefail

# ── Canopy macOS Installer ──────────────────────────────────────────────────
#
# macOS-specific installer that handles:
#   - Homebrew keg-only formulas (postgresql@15/16 PATH issues)
#   - Correct PostgreSQL user detection (uses whoami, not hardcoded)
#   - Existing postgresql@15 installations
#   - Apple Silicon + Intel Homebrew paths
#   - Xcode CLI tools verification
#
# Usage:
#   ./install_mac.sh              # Full install + setup
#   ./install_mac.sh --check      # Dry run: check prerequisites only
#   ./install_mac.sh --no-launch  # Install but don't start the app
# ─────────────────────────────────────────────────────────────────────────────

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

CHECK_ONLY=false
NO_LAUNCH=false

for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=true ;;
    --no-launch) NO_LAUNCH=true ;;
    --help|-h)
      printf "Usage: ./install_mac.sh [--check] [--no-launch]\n"
      printf "  --check      Dry run: only check prerequisites\n"
      printf "  --no-launch  Install everything but don't start the app\n"
      exit 0
      ;;
  esac
done

# ── Verify macOS ────────────────────────────────────────────────────────────

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf "${RED}This script is for macOS only. Use install.sh for other platforms.${NC}\n"
  exit 1
fi

# ── Helpers ─────────────────────────────────────────────────────────────────

ok()   { printf "  ${GREEN}✓${NC} %s\n" "$*"; }
warn() { printf "  ${YELLOW}!${NC} %s\n" "$*"; }
fail() { printf "  ${RED}✗${NC} %s\n" "$*"; }
step() { printf "\n${BOLD}%s${NC}\n" "$*"; }
dim()  { printf "  ${DIM}%s${NC}\n" "$*"; }

has() { command -v "$1" >/dev/null 2>&1; }

CURRENT_USER="$(whoami)"

# Detect Homebrew prefix (Apple Silicon vs Intel)
if [[ -d "/opt/homebrew" ]]; then
  BREW_PREFIX="/opt/homebrew"
elif [[ -d "/usr/local/Homebrew" ]]; then
  BREW_PREFIX="/usr/local"
else
  BREW_PREFIX=""
fi

PG_BIN=""
PG_VERSION=""

# Find the installed PostgreSQL version and set PATH accordingly
find_postgres() {
  local pg_bin=""

  for ver in 17 16 15 14; do
    local candidate="${BREW_PREFIX}/opt/postgresql@${ver}/bin"
    if [[ -x "${candidate}/psql" ]]; then
      pg_bin="$candidate"
      PG_VERSION="$ver"
      break
    fi
  done

  if [[ -z "$pg_bin" ]] && has psql; then
    pg_bin="$(dirname "$(command -v psql)")"
    PG_VERSION="$(psql --version | grep -oE '[0-9]+' | head -1)"
  fi

  if [[ -n "$pg_bin" ]]; then
    PG_BIN="$pg_bin"
    export PATH="${pg_bin}:${PATH}"
    return 0
  fi

  PG_BIN=""
  PG_VERSION=""
  return 1
}

# ── Banner ──────────────────────────────────────────────────────────────────

printf "\n"
printf "${BLUE}${BOLD}"
printf "   ╔══════════════════════════════════════╗\n"
printf "   ║      Canopy Command Center (macOS)   ║\n"
printf "   ║     Your AI team, one command away   ║\n"
printf "   ╚══════════════════════════════════════╝\n"
printf "${NC}\n"
dim "User: ${CURRENT_USER} | Arch: $(uname -m) | macOS $(sw_vers -productVersion)"
dim "Homebrew prefix: ${BREW_PREFIX:-not found}"

# ── Step 1: Prerequisites ──────────────────────────────────────────────────

step "1/6  Checking prerequisites..."

MISSING=0

# Xcode Command Line Tools
if xcode-select -p >/dev/null 2>&1; then
  ok "Xcode CLI tools"
else
  if $CHECK_ONLY; then
    fail "Xcode CLI tools — install with: xcode-select --install"
    MISSING=1
  else
    warn "Xcode CLI tools not found — installing..."
    xcode-select --install 2>/dev/null || true
    printf "  ${YELLOW}Complete the Xcode CLI tools install dialog, then re-run this script.${NC}\n"
    exit 1
  fi
fi

# Homebrew
if has brew; then
  ok "Homebrew $(brew --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
else
  if $CHECK_ONLY; then
    fail "Homebrew — install from https://brew.sh"
    MISSING=1
  else
    warn "Homebrew not found — installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$("${BREW_PREFIX}/bin/brew" shellenv)"
    ok "Homebrew installed"
  fi
fi

# Node.js
if has node; then
  NODE_VER="$(node --version)"
  NODE_MAJOR="${NODE_VER#v}"
  NODE_MAJOR="${NODE_MAJOR%%.*}"
  if [[ "$NODE_MAJOR" -ge 20 ]]; then
    ok "Node.js ${NODE_VER}"
  else
    warn "Node.js ${NODE_VER} found but v20+ required"
    if ! $CHECK_ONLY; then
      brew install node
      ok "Node.js upgraded to $(node --version)"
    else
      MISSING=1
    fi
  fi
else
  if $CHECK_ONLY; then
    fail "Node.js — install with: brew install node"
    MISSING=1
  else
    warn "Node.js not found — installing..."
    brew install node
    ok "Node.js $(node --version)"
  fi
fi

# Elixir + Erlang
if has elixir && has mix; then
  ok "Elixir $(elixir --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
else
  if $CHECK_ONLY; then
    fail "Elixir — install with: brew install elixir"
    MISSING=1
  else
    warn "Elixir not found — installing..."
    brew install elixir
    ok "Elixir installed"
  fi
fi

# PostgreSQL — detect existing keg-only installs before trying to install
if find_postgres; then
  ok "PostgreSQL @${PG_VERSION} (${PG_BIN})"

  if "${PG_BIN}/pg_isready" -q 2>/dev/null; then
    ok "PostgreSQL server is accepting connections"
  else
    warn "PostgreSQL @${PG_VERSION} is installed but not running"
    if ! $CHECK_ONLY; then
      dim "Starting postgresql@${PG_VERSION}..."
      brew services start "postgresql@${PG_VERSION}" 2>/dev/null || true
      sleep 2
      if "${PG_BIN}/pg_isready" -q 2>/dev/null; then
        ok "PostgreSQL server started"
      else
        fail "Could not start PostgreSQL — start manually: brew services start postgresql@${PG_VERSION}"
        MISSING=1
      fi
    else
      fail "Start with: brew services start postgresql@${PG_VERSION}"
      MISSING=1
    fi
  fi
else
  if $CHECK_ONLY; then
    fail "PostgreSQL — install with: brew install postgresql@15"
    MISSING=1
  else
    warn "PostgreSQL not found — installing postgresql@15..."
    brew install postgresql@15
    brew services start postgresql@15
    sleep 2
    find_postgres
    ok "PostgreSQL @${PG_VERSION} installed and started"
  fi
fi

# just (command runner)
if has just; then
  ok "just $(just --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
else
  if $CHECK_ONLY; then
    fail "just — install with: brew install just"
    MISSING=1
  else
    warn "just not found — installing..."
    brew install just
    ok "just $(just --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
  fi
fi

# Rust (optional — only for native Tauri builds)
if has rustc; then
  ok "Rust $(rustc --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
else
  if $CHECK_ONLY; then
    warn "Rust not installed (optional — only needed for native Tauri desktop builds)"
  else
    warn "Rust not found — installing (needed for native desktop app)..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env" 2>/dev/null || export PATH="$HOME/.cargo/bin:$PATH"
    ok "Rust $(rustc --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
  fi
fi

if $CHECK_ONLY; then
  printf "\n"
  if [[ "$MISSING" -eq 0 ]]; then
    printf "${GREEN}${BOLD}  All prerequisites satisfied.${NC}\n"
  else
    printf "${YELLOW}${BOLD}  Some prerequisites are missing. Run without --check to install them.${NC}\n"
  fi
  exit "$MISSING"
fi

# ── Step 2: Locate the Project ──────────────────────────────────────────────

step "2/6  Locating project..."

if [[ -f "backend/mix.exs" ]] && [[ -d "desktop" ]]; then
  CANOPY_DIR="$(pwd)"
  ok "Already in Canopy directory: ${CANOPY_DIR}"
elif [[ -f "mix.exs" ]] && grep -q "canopy" "mix.exs" 2>/dev/null; then
  CANOPY_DIR="$(pwd)"
  ok "Already in Canopy directory: ${CANOPY_DIR}"
else
  INSTALL_DIR="${CANOPY_HOME:-$HOME/.canopy-app}"
  if [[ -d "$INSTALL_DIR" ]] && [[ -f "$INSTALL_DIR/backend/mix.exs" ]]; then
    CANOPY_DIR="$INSTALL_DIR"
    ok "Found existing install at ${CANOPY_DIR}"
  else
    dim "Cloning to ${INSTALL_DIR}..."
    git clone --depth 1 "https://github.com/Miosa-osa/canopy.git" "$INSTALL_DIR"
    CANOPY_DIR="$INSTALL_DIR"
    ok "Cloned to ${CANOPY_DIR}"
  fi
fi

cd "$CANOPY_DIR"

# ── Step 3: Configure PostgreSQL User ───────────────────────────────────────

step "3/6  Configuring database user..."

DEV_CONFIG="backend/config/dev.exs"

if [[ -f "$DEV_CONFIG" ]]; then
  CONFIGURED_USER="$(grep -oE 'username:\s*"[^"]+"' "$DEV_CONFIG" | grep -oE '"[^"]+"' | tr -d '"' || echo "")"

  if [[ -z "$CONFIGURED_USER" ]]; then
    warn "Could not detect configured username in dev.exs"
  elif [[ "$CONFIGURED_USER" == "$CURRENT_USER" ]]; then
    ok "dev.exs username matches system user: ${CURRENT_USER}"
  else
    # Check if the configured user actually exists in PostgreSQL
    if "${PG_BIN}/psql" -U "$CONFIGURED_USER" -c "" postgres 2>/dev/null; then
      ok "dev.exs username '${CONFIGURED_USER}' is valid in PostgreSQL"
    else
      warn "dev.exs has username '${CONFIGURED_USER}' but PostgreSQL role does not exist"

      if "${PG_BIN}/psql" -U "$CURRENT_USER" -c "" postgres 2>/dev/null; then
        dim "Updating dev.exs: username \"${CONFIGURED_USER}\" → \"${CURRENT_USER}\""
        sed -i '' "s/username: \"${CONFIGURED_USER}\"/username: \"${CURRENT_USER}\"/" "$DEV_CONFIG"
        ok "Updated dev.exs to use username: \"${CURRENT_USER}\""
      else
        fail "Neither '${CONFIGURED_USER}' nor '${CURRENT_USER}' can connect to PostgreSQL"
        printf "  ${YELLOW}Create a PostgreSQL role manually:${NC}\n"
        dim "${PG_BIN}/createuser -s ${CURRENT_USER}"
        exit 1
      fi
    fi
  fi
else
  warn "Could not find ${DEV_CONFIG}"
fi

# ── Step 4: Database Setup ──────────────────────────────────────────────────

step "4/6  Setting up database..."

if "${PG_BIN}/psql" -U "$CURRENT_USER" -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw canopy_dev; then
  ok "Database canopy_dev already exists"
else
  dim "Creating database canopy_dev..."
  (cd backend && mix ecto.create 2>&1) && ok "Database created" || {
    "${PG_BIN}/createdb" -U "$CURRENT_USER" canopy_dev 2>/dev/null && ok "Database created via createdb" || {
      fail "Could not create database — check PostgreSQL configuration"
      exit 1
    }
  }
fi

dim "Running migrations..."
(cd backend && mix ecto.migrate 2>&1) && ok "Migrations complete" || warn "Migrations failed (check database config)"

if [[ -f "backend/priv/repo/seeds.exs" ]]; then
  dim "Seeding initial data..."
  (cd backend && mix run priv/repo/seeds.exs 2>&1) && ok "Seed data loaded" || warn "Seeding skipped"
fi

# ── Step 5: Install Dependencies ────────────────────────────────────────────

step "5/6  Installing dependencies..."

if [[ ! -d "backend/deps" ]] || [[ ! -d "backend/_build" ]]; then
  dim "Backend: mix deps.get && mix compile..."
  (cd backend && mix deps.get && mix compile)
fi
ok "Backend dependencies ready"

if [[ ! -d "desktop/node_modules" ]]; then
  dim "Desktop: npm install..."
  (cd desktop && npm install)
fi
ok "Desktop dependencies ready"

# ── Step 6: Summary & Launch ────────────────────────────────────────────────

step "6/6  Ready!"

printf "\n"
printf "${GREEN}${BOLD}  Canopy setup complete!${NC}\n"
printf "\n"
printf "  ${DIM}──────────────────────────────────────────${NC}\n"
printf "  ${BOLD}System:${NC}     macOS %s (%s)\n" "$(sw_vers -productVersion)" "$(uname -m)"
printf "  ${BOLD}Node.js:${NC}    %s\n" "$(node --version)"
printf "  ${BOLD}Elixir:${NC}     %s\n" "$(elixir --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
printf "  ${BOLD}PostgreSQL:${NC} @%s (%s)\n" "${PG_VERSION}" "$("${PG_BIN}/pg_isready" 2>/dev/null | tail -1)"
printf "  ${BOLD}Rust:${NC}       %s\n" "$(rustc --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo 'not installed')"
printf "  ${BOLD}DB User:${NC}    %s\n" "${CURRENT_USER}"
printf "  ${BOLD}Project:${NC}    %s\n" "${CANOPY_DIR}"
printf "  ${DIM}──────────────────────────────────────────${NC}\n"
printf "\n"
printf "  ${BOLD}Commands:${NC}\n"
printf "    just dev              ${DIM}# Start full stack (browser)${NC}\n"
printf "    just app              ${DIM}# Start full stack (native Tauri)${NC}\n"
printf "    just stop             ${DIM}# Stop all services${NC}\n"
printf "    just status           ${DIM}# Show running services${NC}\n"
printf "    just backend          ${DIM}# Backend only (:9089)${NC}\n"
printf "    just desktop          ${DIM}# Desktop only (:5200, mock mode)${NC}\n"
printf "    just logs backend     ${DIM}# Tail backend logs${NC}\n"
printf "    just doctor           ${DIM}# Verify prerequisites${NC}\n"
printf "    just --list           ${DIM}# Show all commands${NC}\n"
printf "\n"

if $NO_LAUNCH; then
  dim "Skipping launch (--no-launch). Run 'just dev' when ready."
  exit 0
fi

printf "  ${BOLD}Launching Canopy...${NC}\n"
printf "\n"

if has just; then
  just dev
else
  ./scripts/start.sh
fi
