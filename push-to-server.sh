#!/usr/bin/env bash
set -euo pipefail

# ─── CONFIGURATION ─────────────────────────────────────────────────────────────
DEFAULT_IP="157.230.80.114"
REMOTE_IP="${1:-${DEFAULT_IP}}"

SSH_KEY="~/.ssh/digitalocean"
LOCAL_DIR="${HOME}/milou-cli"
REMOTE_DIR="/home/milou-cli"

# Git identity to use on the server (can be overridden with env vars)
GIT_NAME="${GIT_DEPLOY_NAME:-Milou CLI Deployer}"
GIT_EMAIL="${GIT_DEPLOY_EMAIL:-deployer@example.com}"
# ────────────────────────────────────────────────────────────────────────────────

usage() {
  cat <<EOF
Usage: $0 [remote_ip]

Deploy milou-cli to the remote server, auto-accept/refresh SSH host keys,
and configure Git identity. If no IP is supplied, defaults to ${DEFAULT_IP}.
EOF
  exit 1
}

# Show help if requested
if [[ "${1-}" == "-h" || "${1-}" == "--help" ]]; then
  usage
fi

# Logging helpers
_info()  { printf "\033[1;34m[INFO]\033[0m  %s\n" "$*"; }
_error() { printf "\033[1;31m[ERROR]\033[0m %s\n" "$*" >&2; }

# ─── PRE-CHECKS ────────────────────────────────────────────────────────────────
_info "Verifying prerequisites..."

if [[ ! -f "${SSH_KEY}" ]]; then
  _error "SSH key not found: ${SSH_KEY}"
  exit 1
fi
if [[ ! -d "${LOCAL_DIR}" ]]; then
  _error "Local directory not found: ${LOCAL_DIR}"
  exit 1
fi

chmod 600 "${SSH_KEY}"

# Ensure known_hosts exists
mkdir -p "${HOME}/.ssh"
touch "${HOME}/.ssh/known_hosts"

# Attempt SSH, auto-resolve host key issues
_info "Testing SSH connectivity to ${REMOTE_IP}..."
SSH_OUTPUT=""
SSH_STATUS=0

if ! SSH_OUTPUT=$(ssh -i "${SSH_KEY}" -o BatchMode=yes -o ConnectTimeout=5 root@"${REMOTE_IP}" true 2>&1); then
  SSH_STATUS=$?
  if echo "${SSH_OUTPUT}" | grep -qE "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED|Host key verification failed"; then
    _info "Detected old or missing host key for ${REMOTE_IP}, refreshing…"
    ssh-keygen -R "${REMOTE_IP}" >/dev/null 2>&1 || true
    ssh-keyscan -H "${REMOTE_IP}" >> "${HOME}/.ssh/known_hosts" 2>/dev/null
    _info "New host key added. Re-testing SSH connectivity…"
    if ! ssh -i "${SSH_KEY}" -o BatchMode=yes -o ConnectTimeout=5 root@"${REMOTE_IP}" true; then
      _error "SSH still failing after refreshing host key."
      exit 1
    fi
  else
    _error "SSH connection failed: ${SSH_OUTPUT}"
    exit 1
  fi
fi
# ────────────────────────────────────────────────────────────────────────────────

# ─── DEPLOY ────────────────────────────────────────────────────────────────────
_info "Ensuring remote directory exists…"
ssh -i "${SSH_KEY}" root@"${REMOTE_IP}" "mkdir -p '${REMOTE_DIR}'"

_info "Syncing files to ${REMOTE_IP}:${REMOTE_DIR}…"
rsync -azh --delete \
  -e "ssh -i ${SSH_KEY}" \
  --exclude '.git' \
  --exclude '.gitignore' \
  --exclude '.env' \
  --exclude '.env.example' \
  --exclude '*README*' \
  --exclude '*FIXES*' \
  "${LOCAL_DIR}/" root@"${REMOTE_IP}":"${REMOTE_DIR}/"
# ────────────────────────────────────────────────────────────────────────────────

# ─── REMOTE GIT CONFIG ─────────────────────────────────────────────────────────
_info "Configuring Git identity on remote (if not already set)…"
ssh -i "${SSH_KEY}" root@"${REMOTE_IP}" bash <<EOF
if ! git config --global user.name >/dev/null 2>&1; then
  git config --global user.name "${GIT_NAME}"
fi
if ! git config --global user.email >/dev/null 2>&1; then
  git config --global user.email "${GIT_EMAIL}"
fi
EOF
# ────────────────────────────────────────────────────────────────────────────────

_info "✅ Deployment complete!"
_info "   Git identity on ${REMOTE_IP} is now: ${GIT_NAME} <${GIT_EMAIL}>"
