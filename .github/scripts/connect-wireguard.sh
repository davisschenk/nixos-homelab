#!/usr/bin/env bash
set -euo pipefail

: "${CI_WIREGUARD_PRIVATE_KEY:?CI_WIREGUARD_PRIVATE_KEY is required}"
: "${ESTUARY_ENDPOINT:?ESTUARY_ENDPOINT is required}"

config=$(mktemp)
chmod 600 "$config"
trap 'shred -u "$config"' EXIT
{
  printf '[Interface]\n'
  printf 'Address = 10.88.0.3/32\n'
  printf 'PrivateKey = %s\n' "$CI_WIREGUARD_PRIVATE_KEY"
  printf 'MTU = 1380\n\n'
  printf '[Peer]\n'
  printf 'PublicKey = fX/cDl6eNrzE93glQ8VOq+6YUfJxPgEArXSh3NY0Ox0=\n'
  printf 'AllowedIPs = 10.88.0.0/24\n'
  printf 'Endpoint = %s\n' "$ESTUARY_ENDPOINT"
  printf 'PersistentKeepalive = 25\n'
} > "$config"

sudo install -D -m 600 "$config" /etc/wireguard/wg-ci.conf
sudo wg-quick up wg-ci
