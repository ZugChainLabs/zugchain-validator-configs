#!/usr/bin/env bash
# ==========================================================
# ZUG CHAIN - VALIDATOR JOINER (ENTERPRISE)
# Compatible with enterprise bootnode/rpc deployment
# ==========================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }

check_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    log_err "Run as root (sudo)."
    exit 1
  fi
}

ZUG_DIR="/opt/zugchain"
DATA_DIR="${ZUG_DIR}/data"
CONFIG_DIR="${ZUG_DIR}/config"
LOGS_DIR="${ZUG_DIR}/logs"

CHAIN_ID="${CHAIN_ID:-824642}"
NETWORK_ID="${NETWORK_ID:-824642}"
CHAIN_CONFIG_SOURCE="${CHAIN_CONFIG_SOURCE:-}"
PEER_MANIFEST_URL="${PEER_MANIFEST_URL:-}"
GETH_BOOTNODES="${GETH_BOOTNODES:-}"
PRYSM_BOOTSTRAP_NODES="${PRYSM_BOOTSTRAP_NODES:-}"
STATIC_ENODES="${STATIC_ENODES:-}"
ALLOW_EMPTY_PEERS="${ALLOW_EMPTY_PEERS:-false}"
FRESH_INSTALL="${FRESH_INSTALL:-false}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
BINARIES_TARBALL_URL="${BINARIES_TARBALL_URL:-https://codeload.github.com/ZugChainLabs/zugchain-validator-configs/tar.gz/refs/heads/main}"

ARCH_DIR=""
PUBLIC_IP="${PUBLIC_IP:-}"
FEE_RECIPIENT="${FEE_RECIPIENT:-}"

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --fresh)
        FRESH_INSTALL="true"
        shift
        ;;
      --public-ip)
        shift
        PUBLIC_IP="${1:-}"
        [[ -z "${PUBLIC_IP}" ]] && { log_err "--public-ip requires a value"; exit 1; }
        shift
        ;;
      --fee-recipient)
        shift
        FEE_RECIPIENT="${1:-}"
        [[ -z "${FEE_RECIPIENT}" ]] && { log_err "--fee-recipient requires a value"; exit 1; }
        shift
        ;;
      *)
        log_err "Unknown argument: $1"
        log_info "Supported: --fresh --public-ip <ip> --fee-recipient <wallet>"
        exit 1
        ;;
    esac
  done
}

detect_arch() {
  local arch
  arch="$(uname -m)"
  if [[ "${arch}" == "x86_64" ]]; then
    ARCH_DIR="x86"
  elif [[ "${arch}" == "aarch64" || "${arch}" == "arm64" ]]; then
    ARCH_DIR="arm64"
  else
    log_err "Unsupported architecture: ${arch}"
    exit 1
  fi
  log_ok "Architecture: ${arch} (${ARCH_DIR})"
}

detect_public_ip() {
  if [[ -n "${PUBLIC_IP}" ]]; then
    return
  fi

  if command -v curl >/dev/null 2>&1; then
    PUBLIC_IP="$(curl -4 -fsS --max-time 5 ifconfig.me 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ -z "${PUBLIC_IP}" ]]; then
      PUBLIC_IP="$(curl -4 -fsS --max-time 5 api.ipify.org 2>/dev/null | tr -d '[:space:]' || true)"
    fi
  fi

  if [[ -z "${PUBLIC_IP}" ]]; then
    PUBLIC_IP="$(hostname -I 2>/dev/null | awk '{print $1}' | tr -d '[:space:]' || true)"
  fi

  if [[ -z "${PUBLIC_IP}" ]]; then
    log_err "Could not auto-detect PUBLIC_IP"
    exit 1
  fi

  log_ok "Using PUBLIC_IP=${PUBLIC_IP}"
}

prompt_fee_recipient() {
  if [[ -n "${FEE_RECIPIENT}" ]]; then
    log_ok "Fee recipient (env/arg): ${FEE_RECIPIENT}"
    return
  fi

  local default_fee="0x98CE9a541aFCfCa53804702F9d273FE1bB653eA9"
  echo -e "${YELLOW}Enter fee recipient wallet [${default_fee}]${NC}"
  read -r -p "Fee recipient: " FEE_RECIPIENT
  FEE_RECIPIENT="${FEE_RECIPIENT:-$default_fee}"
  log_ok "Fee recipient: ${FEE_RECIPIENT}"
}

merge_csv_unique() {
  local merged
  merged="$(
    printf '%s\n' "$@" \
      | tr ',' '\n' \
      | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
      | awk 'NF && !seen[$0]++'
  )"
  paste -sd, - <<< "${merged}"
}

install_dependencies() {
  apt-get update -qq
  apt-get install -y -qq git curl wget jq openssl software-properties-common net-tools
}

install_geth_if_needed() {
  if command -v geth >/dev/null 2>&1; then
    log_info "Geth already installed"
    return
  fi

  add-apt-repository -y ppa:ethereum/ethereum
  apt-get update -qq
  apt-get install -y ethereum
  log_ok "Installed geth"
}

install_prysm_binaries() {
  local bin_source="${REPO_ROOT}/bin/${ARCH_DIR}"
  local tmp_dir=""
  if [[ ! -f "${bin_source}/beacon-chain" || ! -f "${bin_source}/validator" ]]; then
    log_warn "Local binaries not found at ${bin_source}, downloading from GitHub..."
    tmp_dir="$(mktemp -d)"
    curl -fsSL "${BINARIES_TARBALL_URL}" -o "${tmp_dir}/validator-configs.tar.gz"
    tar -xzf "${tmp_dir}/validator-configs.tar.gz" -C "${tmp_dir}"

    local extracted=""
    for d in "${tmp_dir}"/zugchain-validator-configs-*/bin/"${ARCH_DIR}"; do
      [[ -d "${d}" ]] || continue
      extracted="${d}"
      break
    done
    if [[ -z "${extracted}" ]]; then
      log_err "Could not locate bin/${ARCH_DIR} in downloaded archive"
      exit 1
    fi
    bin_source="${extracted}"
  fi

  cp -f "${bin_source}/beacon-chain" /usr/local/bin/
  cp -f "${bin_source}/validator" /usr/local/bin/
  [[ -f "${bin_source}/prysmctl" ]] && cp -f "${bin_source}/prysmctl" /usr/local/bin/
  chmod +x /usr/local/bin/beacon-chain /usr/local/bin/validator
  [[ -f /usr/local/bin/prysmctl ]] && chmod +x /usr/local/bin/prysmctl
  [[ -n "${tmp_dir}" ]] && rm -rf "${tmp_dir}"
  log_ok "Installed custom binaries from ${bin_source}"
}

resolve_chain_config_source() {
  if [[ -n "${CHAIN_CONFIG_SOURCE}" ]]; then
    if [[ ! -d "${CHAIN_CONFIG_SOURCE}" ]]; then
      log_err "CHAIN_CONFIG_SOURCE not found: ${CHAIN_CONFIG_SOURCE}"
      exit 1
    fi
  elif [[ -d "${SCRIPT_DIR}/config" ]]; then
    CHAIN_CONFIG_SOURCE="${SCRIPT_DIR}/config"
    log_warn "Using fallback config source: ${CHAIN_CONFIG_SOURCE}"
  else
    log_err "Provide CHAIN_CONFIG_SOURCE with genesis.json/config.yml/genesis.ssz"
    exit 1
  fi

  local file
  for file in genesis.json config.yml genesis.ssz; do
    if [[ ! -f "${CHAIN_CONFIG_SOURCE}/${file}" ]]; then
      log_err "Missing config file: ${CHAIN_CONFIG_SOURCE}/${file}"
      exit 1
    fi
  done

  log_ok "Chain config source: ${CHAIN_CONFIG_SOURCE}"
}

resolve_peer_manifest() {
  local manifest_file="${CONFIG_DIR}/peer-manifest.json"
  local local_manifest="${SCRIPT_DIR}/peer-manifest.json"
  mkdir -p "${CONFIG_DIR}"

  if [[ -n "${PEER_MANIFEST_URL}" ]]; then
    log_info "Fetching peer manifest from ${PEER_MANIFEST_URL}"
    curl -fsSL "${PEER_MANIFEST_URL}" -o "${manifest_file}"
  elif [[ -f "${local_manifest}" ]]; then
    log_info "Using repository peer manifest: ${local_manifest}"
    cp -f "${local_manifest}" "${manifest_file}"
  elif [[ -f "${manifest_file}" ]]; then
    log_info "Using existing peer manifest: ${manifest_file}"
  fi

  if [[ -f "${manifest_file}" ]]; then
    local manifest_geth manifest_prysm manifest_static
    manifest_geth="$(jq -r '.geth_bootnodes // [] | join(",")' "${manifest_file}")"
    manifest_prysm="$(jq -r '.prysm_bootstrap_nodes // [] | join(",")' "${manifest_file}")"
    manifest_static="$(jq -r '.static_peers // [] | join(",")' "${manifest_file}")"

    GETH_BOOTNODES="$(merge_csv_unique "${GETH_BOOTNODES}" "${manifest_geth}" "${manifest_static}")"
    PRYSM_BOOTSTRAP_NODES="$(merge_csv_unique "${PRYSM_BOOTSTRAP_NODES}" "${manifest_prysm}")"
    STATIC_ENODES="$(merge_csv_unique "${STATIC_ENODES}" "${manifest_static}")"
  fi

  if [[ -z "${GETH_BOOTNODES}" ]]; then
    log_warn "GETH_BOOTNODES is empty (join may be slower on restarts)"
  fi
  if [[ -z "${PRYSM_BOOTSTRAP_NODES}" ]]; then
    log_warn "PRYSM_BOOTSTRAP_NODES is empty (beacon discovery may be slower)"
  fi

  if [[ "${ALLOW_EMPTY_PEERS}" != "true" && -z "${GETH_BOOTNODES}" && -z "${PRYSM_BOOTSTRAP_NODES}" ]]; then
    log_err "No peers resolved. Provide repository peer-manifest.json, PEER_MANIFEST_URL, or set GETH_BOOTNODES/PRYSM_BOOTSTRAP_NODES."
    exit 1
  fi
}

cleanup_and_prepare_dirs() {
  systemctl stop zugchain-geth zugchain-beacon zugchain-validator 2>/dev/null || true
  systemctl disable zugchain-geth zugchain-beacon zugchain-validator 2>/dev/null || true
  systemctl disable --now zugchain-peer-refresh.timer zugchain-peer-refresh.service 2>/dev/null || true

  rm -f /etc/systemd/system/zugchain-geth.service
  rm -f /etc/systemd/system/zugchain-beacon.service
  rm -f /etc/systemd/system/zugchain-validator.service
  rm -f /etc/systemd/system/zugchain-peer-refresh.service
  rm -f /etc/systemd/system/zugchain-peer-refresh.timer
  rm -f "${CONFIG_DIR}/peer-refresh.env"
  systemctl daemon-reload

  rm -rf "${CONFIG_DIR}"
  mkdir -p "${CONFIG_DIR}" "${LOGS_DIR}"

  if [[ "${FRESH_INSTALL}" == "true" ]]; then
    log_warn "Fresh install requested: wiping ${DATA_DIR}"
    rm -rf "${DATA_DIR}"
  else
    log_info "Preserving existing chain/wallet data in ${DATA_DIR}"
  fi

  mkdir -p "${DATA_DIR}/geth" "${DATA_DIR}/beacon" "${DATA_DIR}/validators"
}

copy_chain_config() {
  cp -f "${CHAIN_CONFIG_SOURCE}/genesis.json" "${CONFIG_DIR}/genesis.json"
  cp -f "${CHAIN_CONFIG_SOURCE}/config.yml" "${CONFIG_DIR}/config.yml"
  cp -f "${CHAIN_CONFIG_SOURCE}/genesis.ssz" "${CONFIG_DIR}/genesis.ssz"
  log_ok "Copied chain config bundle"
}

init_execution() {
  if [[ ! -f "${DATA_DIR}/jwt.hex" ]]; then
    openssl rand -hex 32 > "${DATA_DIR}/jwt.hex"
    chmod 600 "${DATA_DIR}/jwt.hex"
  else
    chmod 600 "${DATA_DIR}/jwt.hex"
    log_info "Reusing existing jwt.hex"
  fi

  if [[ "${FRESH_INSTALL}" == "true" || ! -d "${DATA_DIR}/geth/geth/chaindata" ]]; then
    geth init --datadir "${DATA_DIR}/geth" --state.scheme=path "${CONFIG_DIR}/genesis.json"
    log_ok "Initialized geth"
  else
    log_info "Existing geth chaindata detected; skipping geth init"
  fi
}

write_peer_env() {
  cat > "${CONFIG_DIR}/network-peers.env" <<EOF
PUBLIC_IP="${PUBLIC_IP}"
NETWORK_ID="${NETWORK_ID}"
CHAIN_ID="${CHAIN_ID}"
GETH_BOOTNODES="${GETH_BOOTNODES}"
PRYSM_BOOTSTRAP_NODES="${PRYSM_BOOTSTRAP_NODES}"
STATIC_ENODES="${STATIC_ENODES}"
FEE_RECIPIENT="${FEE_RECIPIENT}"
EOF
  chmod 600 "${CONFIG_DIR}/network-peers.env"
}

write_start_scripts() {
  cat > "${ZUG_DIR}/start-geth.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ZUG_DIR="/opt/zugchain"
source "${ZUG_DIR}/config/network-peers.env"
[ -f "${ZUG_DIR}/config/dynamic-peers.env" ] && source "${ZUG_DIR}/config/dynamic-peers.env"

ARGS=(
  --datadir="${ZUG_DIR}/data/geth"
  --networkid="${NETWORK_ID}"
  --http --http.addr=0.0.0.0 --http.port=8545
  --http.api="eth,net,web3,engine,txpool"
  --authrpc.addr=127.0.0.1 --authrpc.port=8551
  --authrpc.vhosts=localhost,127.0.0.1
  --authrpc.jwtsecret="${ZUG_DIR}/data/jwt.hex"
  --syncmode=full --gcmode=archive --state.scheme=path
  --port=30303 --discovery.port=30303
  --verbosity=3
)

MERGED_BOOTNODES="$(printf '%s,%s\n' "${GETH_BOOTNODES:-}" "${STATIC_ENODES:-}" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | awk 'NF && !seen[$0]++' | paste -sd, -)"
if [[ -n "${MERGED_BOOTNODES:-}" ]]; then
  ARGS+=(--bootnodes="${MERGED_BOOTNODES}")
fi

exec geth "${ARGS[@]}"
EOF
  chmod +x "${ZUG_DIR}/start-geth.sh"

  cat > "${ZUG_DIR}/start-beacon.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ZUG_DIR="/opt/zugchain"
source "${ZUG_DIR}/config/network-peers.env"
[ -f "${ZUG_DIR}/config/dynamic-peers.env" ] && source "${ZUG_DIR}/config/dynamic-peers.env"

ARGS=(
  --datadir="${ZUG_DIR}/data/beacon"
  --genesis-state="${ZUG_DIR}/config/genesis.ssz"
  --chain-config-file="${ZUG_DIR}/config/config.yml"
  --execution-endpoint=http://127.0.0.1:8551
  --jwt-secret="${ZUG_DIR}/data/jwt.hex"
  --accept-terms-of-use
  --rpc-host=0.0.0.0 --rpc-port=4000
  --grpc-gateway-host=0.0.0.0 --grpc-gateway-port=3500
  --p2p-local-ip=0.0.0.0
  --p2p-host-ip="${PUBLIC_IP}"
  --p2p-tcp-port=13000 --p2p-udp-port=12000
  --min-sync-peers=1
  --minimum-peers-per-subnet=1
  --deposit-contract=0x00000000219ab540356cBB839Cbe05303d7705Fa
  --contract-deployment-block=0
  --verbosity=info
)

if [[ -n "${PRYSM_BOOTSTRAP_NODES:-}" ]]; then
  IFS=',' read -ra ENRS <<< "${PRYSM_BOOTSTRAP_NODES}"
  for enr in "${ENRS[@]}"; do
    trimmed="$(echo "${enr}" | xargs)"
    [[ -n "${trimmed}" ]] && ARGS+=(--bootstrap-node="${trimmed}")
  done
else
  ARGS+=(--bootstrap-node="")
fi

exec beacon-chain "${ARGS[@]}"
EOF
  chmod +x "${ZUG_DIR}/start-beacon.sh"

  cat > "${ZUG_DIR}/start-validator.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ZUG_DIR="/opt/zugchain"
source "${ZUG_DIR}/config/network-peers.env"

exec validator \
  --datadir="${ZUG_DIR}/data/validators" \
  --beacon-rpc-provider=127.0.0.1:4000 \
  --chain-config-file="${ZUG_DIR}/config/config.yml" \
  --accept-terms-of-use \
  --wallet-dir="${ZUG_DIR}/data/validators" \
  --wallet-password-file="${ZUG_DIR}/data/validators/wallet-password.txt" \
  --suggested-fee-recipient="${FEE_RECIPIENT}" \
  --verbosity=info
EOF
  chmod +x "${ZUG_DIR}/start-validator.sh"
}

write_systemd_services() {
  # Ensure old peer refresh automation units are cleaned up.
  systemctl disable --now zugchain-peer-refresh.timer zugchain-peer-refresh.service 2>/dev/null || true
  rm -f /etc/systemd/system/zugchain-peer-refresh.service
  rm -f /etc/systemd/system/zugchain-peer-refresh.timer
  rm -f "${CONFIG_DIR}/peer-refresh.env"

  cat > /etc/systemd/system/zugchain-geth.service <<EOF
[Unit]
Description=ZUG Chain Validator Geth
After=network.target

[Service]
Type=simple
ExecStart=${ZUG_DIR}/start-geth.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat > /etc/systemd/system/zugchain-beacon.service <<EOF
[Unit]
Description=ZUG Chain Validator Beacon
After=zugchain-geth.service
Requires=zugchain-geth.service

[Service]
Type=simple
ExecStartPre=/bin/sleep 10
ExecStart=${ZUG_DIR}/start-beacon.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat > /etc/systemd/system/zugchain-validator.service <<EOF
[Unit]
Description=ZUG Chain Validator Client
After=zugchain-beacon.service
Requires=zugchain-beacon.service

[Service]
Type=simple
ExecStartPre=/bin/sleep 15
ExecStart=${ZUG_DIR}/start-validator.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable zugchain-geth zugchain-beacon zugchain-validator
}

start_services() {
  systemctl restart zugchain-geth
  sleep 5
  systemctl restart zugchain-beacon
  log_ok "Started geth + beacon"
  log_warn "Validator service enabled but not auto-started."
}

print_next_steps() {
  echo
  echo "=================================================="
  echo " Validator Join Complete (Enterprise)"
  echo "=================================================="
  echo "Public IP: ${PUBLIC_IP}"
  echo "Network ID: ${NETWORK_ID}"
  echo
  echo "Next steps:"
  echo "1) Import validator wallet into ${DATA_DIR}/validators"
  echo "2) Create wallet password file:"
  echo "   ${DATA_DIR}/validators/wallet-password.txt"
  echo "3) Start validator:"
  echo "   sudo systemctl start zugchain-validator"
  echo
  echo "Optional peer refresh from manifest:"
  echo "  sudo ${SCRIPT_DIR}/05_refresh_peers_and_restart.sh <manifest-url>"
  echo
  echo "Rerun behavior:"
  echo "  - Default rerun keeps ${DATA_DIR} (chain + wallet data preserved)"
  echo "  - Use --fresh only for full reset"
  echo
}

main() {
  check_root
  parse_args "$@"
  log_info "Starting enterprise validator joiner"

  detect_arch
  detect_public_ip
  prompt_fee_recipient

  install_dependencies
  install_geth_if_needed
  install_prysm_binaries

  resolve_chain_config_source
  resolve_peer_manifest

  cleanup_and_prepare_dirs
  copy_chain_config
  init_execution
  write_peer_env
  write_start_scripts
  write_systemd_services
  start_services
  print_next_steps
}

main "$@"
