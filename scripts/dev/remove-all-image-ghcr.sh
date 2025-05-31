#!/usr/bin/env bash
#
# remove-all-ghcr-packages.sh
#
# Usage:
#   # To delete user‐owned private packages:
#   ./remove-all-ghcr-packages.sh --token <GHCR_TOKEN>
#
#   # To delete org‐owned private packages (e.g. “milou-sh”):
#   ./remove-all-ghcr-packages.sh --token <GHCR_TOKEN> --owner milou-sh
#
# What it does:
#   1. Detects whether you want to target your user account or a specific org (via --owner).
#   2. Lists (prints) every private container package in that namespace.
#   3. Deletes each package by calling the correct DELETE endpoint (with URL-encoded names).
#
# Prerequisites:
#   • A GitHub PAT with at least: packages:read and packages:delete scopes.  
#   • jq installed (for JSON parsing).
#
set -euo pipefail

# -----------------------
# 1) Parse arguments
# -----------------------
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 --token <GHCR_TOKEN> [--owner <OWNER_NAME>]"
  exit 1
fi

TOKEN=""
OWNER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --token)
      shift
      TOKEN="$1"
      ;;
    --owner)
      shift
      OWNER="$1"
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: $0 --token <GHCR_TOKEN> [--owner <OWNER_NAME>]"
      exit 1
      ;;
  esac
  shift
done

if [[ -z "${TOKEN}" ]]; then
  echo "Error: --token is required."
  exit 1
fi

# -----------------------
# 2) Build the “list” URL based on whether an owner is provided
# -----------------------
if [[ -n "${OWNER}" ]]; then
  # List private container packages for an organization
  LIST_URL="https://api.github.com/orgs/${OWNER}/packages?package_type=container&visibility=private&per_page=100"
  DELETE_BASE="https://api.github.com/orgs/${OWNER}/packages/container"
else
  # List private container packages for the authenticated user
  LIST_URL="https://api.github.com/user/packages?package_type=container&visibility=private&per_page=100"
  DELETE_BASE="https://api.github.com/user/packages/container"
fi

ACCEPT_HEADER="Accept: application/vnd.github+json"
AUTH_HEADER="Authorization: Bearer ${TOKEN}"

# -----------------------
# 3) Paginate through all pages and collect package names
# -----------------------
next_url="${LIST_URL}"
all_packages=()

echo "→ Fetching all private container packages for “${OWNER:-<your user account>}”…"

while [[ -n "${next_url}" ]]; do
  # Grab headers + body
  response=$(curl -s -D - \
    -H "${AUTH_HEADER}" \
    -H "${ACCEPT_HEADER}" \
    "${next_url}")

  # Split into headers vs. body
  headers=$(printf '%s' "${response}" | sed -n '1,/^\r$/p')
  body=$(printf '%s' "${response}" | sed -n '1,/^\r$/!p')

  # Extract each “name” from the JSON array (.[].name)
  names=( $(printf '%s' "${body}" | jq -r '.[].name') )
  if [[ ${#names[@]} -gt 0 ]]; then
    all_packages+=("${names[@]}")
  fi

  # Look for “rel=\"next\"” in the Link header to continue pagination
  next_url=$(printf '%s' "${headers}" \
    | tr -d '\r' \
    | grep -i '^Link:' \
    | sed -E 's/.*<([^>]+)>; rel="next".*/\1/' \
    || true)

  # If there was no “next” link at all, break
  if ! grep -qi 'rel="next"' <<<"${headers}"; then
    next_url=""
  fi
done

# -----------------------
# 4) Print (list) everything we found
# -----------------------
if [[ ${#all_packages[@]} -eq 0 ]]; then
  echo
  echo "✓ No private container packages found for “${OWNER:-<your user account>}”."
  exit 0
fi

echo
echo "Found the following private container packages under “${OWNER:-<your user account>}”:"
for pkg in "${all_packages[@]}"; do
  echo "  • ${pkg}"
done
echo

# -----------------------
# 5) Delete each package by name (URL-encoding “/” → “%2F”)
# -----------------------
echo "→ Deleting all of them now…"
for pkg in "${all_packages[@]}"; do
  # URL-encode any “/” in the package name → “%2F”
  encoded_pkg="${pkg//\//%2F}"

  echo -n "   • Deleting “${pkg}”… "
  http_status=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
    -H "${AUTH_HEADER}" \
    -H "${ACCEPT_HEADER}" \
    "${DELETE_BASE}/${encoded_pkg}")

  if [[ "${http_status}" =~ ^2 ]]; then
    echo "OK"
  else
    echo "FAILED (status ${http_status})"
  fi
done

echo
echo "✅ All done. Every listed private container package has been deleted."
