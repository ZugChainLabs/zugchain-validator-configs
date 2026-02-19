#!/bin/bash
# ==========================================================
# ZUG CHAIN - VALIDATOR JOINER v8.9 (CLEAN & LOCAL)
# ==========================================================

set -e
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() { if [[ $EUID -ne 0 ]]; then log_error "This script must be run as root"; exit 1; fi }

#-------------------------------------------------------------------------------
# INSTALL GETH
#-------------------------------------------------------------------------------

install_geth() {
    echo -e "${GREEN}>>> Checking/Installing Geth (via PPA)${NC}"

    if command -v geth &> /dev/null; then
        log_info "Geth already installed"
        return
    fi

    log_info "Adding Ethereum PPA..."
    add-apt-repository -y ppa:ethereum/ethereum
    apt-get update -qq

    log_info "Installing Geth package..."
    apt-get install -y ethereum

    log_success "Geth installed"
}


# --- DIRECTORY CONFIGURATION (LOCAL) ---
ZUG_DIR="/opt/zugchain"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# If script is in 'validator/' folder, REPO_ROOT is the parent folder.
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# --- CURRENT NETWORK INFO (FROM MASTER) ---
BOOTSTRAP_NODE="enr:-Mq4QIbR8W918FBeVJ3zfIdE2jpuQVaMJPM4bCgOvZP1Uzu3Cvo0gTukq4Nl4l35G_dRHJVtAY_Bz0xdbSvB6tzbXC-GAZx1hGLGh2F0dG5ldHOIAAAADAAAAACEZXRoMpCBoWmuIAAABABMBgAAAAAAgmlkgnY0gmlwhBTlAJmEcXVpY4IyyIlzZWNwMjU2azGhAq2Rz_mwrG5IiWLrarg3VwKJo4oyWOJEkyh43fm7t_woiHN5bmNuZXRzD4N0Y3CCMsiDdWRwgi7g"
BOOTNODE_ENODE="enode://ebf01cb7db4ede4320918fb2ad7e16a0a4d3f2229c68cb4f4b636b99e03d4a36405dfcd5567f43b6560e2d902cde9f0af8c6d0246f33c77ca35aead68aa1e42f@20.229.0.153:30303"
# --- INTERACTIVE INPUT ---
echo -e "${GREEN}>>> Welcome to ZUG Chain Validator Installation.${NC}"
echo ""
echo -e "${YELLOW}>>> Please enter the wallet address to receive Block Rewards (Fee Recipient):${NC}"
read -p "Wallet Address [Default: 0x98CE9...]: " USER_FEE_RECIPIENT

# Assign default address if user leaves it empty
FEE_RECIPIENT=${USER_FEE_RECIPIENT:-"0x98CE9a541aFCfCa53804702F9d273FE1bB653eA9"}
echo -e "${GREEN}>>> Selected Wallet: ${FEE_RECIPIENT}${NC}"
echo ""

PUBLIC_IP=$(curl -s ifconfig.me)

echo -e "${GREEN}>>> ZUG Chain Validator (Smart Install) Starting...${NC}"

check_root


# --- 1. ARCHITECTURE DETECTION ---
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    ARCH_DIR="x86"
elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    ARCH_DIR="arm64"
else
    echo -e "${RED}ERROR: Unsupported architecture: $ARCH${NC}"
    exit 1
fi
echo -e "${GREEN}>>> Architecture: $ARCH ($ARCH_DIR)${NC}"

# --- 2. CLEANUP ---
echo -e "${YELLOW}>>> Cleaning up old data...${NC}"
systemctl stop zugchain-* 2>/dev/null || true
rm -rf ${ZUG_DIR}/config ${ZUG_DIR}/data
mkdir -p ${ZUG_DIR}/{data,config,logs}
mkdir -p ${ZUG_DIR}/data/{geth,beacon,validators}

# --- 3. LOCAL FILE CHECK AND COPY ---
# Binaries are taken from the bin/ folder in the root directory
BIN_SOURCE="${REPO_ROOT}/bin/${ARCH_DIR}"
# Configs are taken from the config/ folder next to the script
CONFIG_SOURCE="${SCRIPT_DIR}/config"

# --- 2.5 DOWNLOAD/INSTALL GETH ---
install_geth


echo -e "${GREEN}>>> Copying files from local repository folders...${NC}"

# Binary Check
if [ ! -f "$BIN_SOURCE/beacon-chain" ]; then
    echo -e "${RED}ERROR: Binary not found: $BIN_SOURCE/beacon-chain${NC}"
    exit 1
fi

# Copy (From Local to System)
cp -f "$BIN_SOURCE/beacon-chain" /usr/local/bin/
cp -f "$BIN_SOURCE/validator" /usr/local/bin/
chmod +x /usr/local/bin/beacon-chain /usr/local/bin/validator

# Copy Config (From Local to /opt/zugchain)
if [ -d "$CONFIG_SOURCE" ]; then
    cp -f "$CONFIG_SOURCE"/* "${ZUG_DIR}/config/"
else
    echo -e "${RED}ERROR: Config folder not found: $CONFIG_SOURCE${NC}"
    exit 1
fi

# --- 4. SETTINGS AND INIT ---
openssl rand -hex 32 > ${ZUG_DIR}/data/jwt.hex
chmod 600 ${ZUG_DIR}/data/jwt.hex
geth init --datadir "${ZUG_DIR}/data/geth" --state.scheme=path "${ZUG_DIR}/config/genesis.json"

# --- 5. SERVICES (SYSTEMD) ---
# (Service blocks here are the same as your v5.0 stability settings)

# Geth
cat > /etc/systemd/system/zugchain-geth.service <<EOF
[Unit]
Description=ZUG Chain Geth
After=network.target
[Service]
User=root
ExecStart=/usr/bin/geth \\
    --datadir=${ZUG_DIR}/data/geth \\
    --networkid=824642 \\
    --http --http.addr=0.0.0.0 --http.port=8545 \\
    --authrpc.addr=127.0.0.1 --authrpc.port=8551 \\
    --authrpc.jwtsecret=${ZUG_DIR}/data/jwt.hex \\
    --syncmode=full --gcmode=archive \\
    --bootnodes="${BOOTNODE_ENODE}" \\
    --port 30303
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

# Beacon
cat > /etc/systemd/system/zugchain-beacon.service <<EOF
[Unit]
Description=ZUG Chain Beacon
After=zugchain-geth.service
[Service]
User=root
ExecStart=/usr/local/bin/beacon-chain \\
    --datadir=${ZUG_DIR}/data/beacon \\
    --genesis-state=${ZUG_DIR}/config/genesis.ssz \\
    --chain-config-file=${ZUG_DIR}/config/config.yml \\
    --execution-endpoint=http://127.0.0.1:8551 \\
    --jwt-secret=${ZUG_DIR}/data/jwt.hex \\
    --accept-terms-of-use \\
    --rpc-host=0.0.0.0 \\
    --rpc-port=4000 \\
    --grpc-gateway-host=0.0.0.0 \\
    --grpc-gateway-port=3500 \\
    --p2p-host-ip=${PUBLIC_IP} \\
    --p2p-tcp-port=13000 \\
    --p2p-udp-port=12000 \\
    --min-sync-peers=0 \\
    --bootstrap-node="${BOOTSTRAP_NODE}"
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

# Validator
cat > /etc/systemd/system/zugchain-validator.service <<EOF
[Unit]
Description=ZUG Chain Validator
After=zugchain-beacon.service
[Service]
User=root
ExecStart=/usr/local/bin/validator \\
    --datadir=${ZUG_DIR}/data/validators \\
    --beacon-rpc-provider=127.0.0.1:4000 \\
    --chain-config-file=${ZUG_DIR}/config/config.yml \\
    --accept-terms-of-use \\
    --wallet-dir=${ZUG_DIR}/data/validators \\
    --suggested-fee-recipient=${FEE_RECIPIENT} \\
    --wallet-password-file=/opt/zugchain/data/validators/wallet-password.txt
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable zugchain-geth zugchain-beacon zugchain-validator
systemctl start zugchain-geth
sleep 5
systemctl start zugchain-beacon

echo -e "${GREEN}>>> ZUG Chain Validator Successfully Installed!${NC}"
echo -e "${YELLOW}>>> Setup complete using local repository.${NC}"
