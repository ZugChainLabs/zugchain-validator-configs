# ZugChain Validator Node - Manual Installation Guide

## Overview

This repository contains the official configuration files required to set up a ZugChain validator node. This guide provides step-by-step instructions for manual installation and operation of a validator node, following Ethereum best practices.

**Network Information:**
- **Network ID:** 824642
- **Chain Name:** ZugChain
- **Consensus:** Proof of Stake (PoS)
- **Staking Requirement:** 32,000 ZUG per validator
- **Main Node RPC:** `http://20.229.0.153:8545`
- **Checkpoint Sync:** `http://20.229.0.153:3500`

---

## Prerequisites

### System Requirements
- **Operating System:** Ubuntu 20.04 LTS or 22.04 LTS (WSL2 supported)
- **CPU:** 4+ cores
- **RAM:** 16 GB minimum, 32 GB recommended
- **Storage:** 500 GB SSD minimum
- **Network:** Stable internet connection with open ports

### Required Software
- `curl`, `wget`, `git`
- `openssl` for JWT secret generation
- `screen` or `tmux` for session management
- Go 1.21+ (installed automatically with Geth)

### Firewall Configuration
Ensure the following ports are open:
- **30303 (TCP/UDP):** Geth P2P
- **13000 (TCP):** Beacon P2P
- **12000 (UDP):** Beacon discovery

---

## Installation Steps

### Step 1: System Preparation

Update your system and install dependencies:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git build-essential openssl screen
```

### Step 2: Install Execution Client (Geth)

Install the latest stable Geth version:

```bash
sudo add-apt-repository -y ppa:ethereum/ethereum
sudo apt update
sudo apt install -y ethereum
```

Verify installation:
```bash
geth version
```

### Step 3: Install Consensus Client (Prysm)

Download and install Prysm binaries:

```bash
mkdir -p ~/prysm && cd ~/prysm

# Download Validator and Beacon binaries
curl -LO https://github.com/prysmaticlabs/prysm/releases/download/v5.3.0/validator-v5.3.0-linux-amd64
curl -LO https://github.com/prysmaticlabs/prysm/releases/download/v5.3.0/beacon-chain-v5.3.0-linux-amd64

# Make executable and move to system path
chmod +x validator-v5.3.0-linux-amd64 beacon-chain-v5.3.0-linux-amd64
sudo mv validator-v5.3.0-linux-amd64 /usr/local/bin/validator
sudo mv beacon-chain-v5.3.0-linux-amd64 /usr/local/bin/beacon-chain
```

Verify installation:
```bash
validator --version
beacon-chain --version
```

---

## Configuration

### Step 4: Set Up Directory Structure

Create the standard directory layout:

```bash
cd ~
mkdir -p ~/zugchain-data/{consensus,execution,secrets,config}
mkdir -p ~/zugchain-data/consensus/wallet
```

### Step 5: Download Configuration Files

Clone this repository and copy configuration files:

```bash
git clone https://github.com/ZugChainLabs/zugchain-validator-configs.git
cd zugchain-validator-configs

# Copy configurations
cp genesis.json ~/zugchain-data/config/
cp config.yml ~/zugchain-data/config/
cp genesis.ssz ~/zugchain-data/config/
```

### Step 6: Generate JWT Secret

The JWT secret enables secure communication between Geth and Prysm:

```bash
openssl rand -hex 32 | tr -d "\n" > ~/zugchain-data/secrets/jwt.hex
```

### Step 7: Initialize Execution Layer

Initialize Geth with the ZugChain genesis configuration:

```bash
geth init --datadir=~/zugchain-data/execution ~/zugchain-data/config/genesis.json
```

Expected output: `Successfully wrote genesis state`

---

## Validator Key Management

### Step 8: Generate or Import Validator Keys

**Option A: Generate New Keys (Recommended for New Validators)**

Use the official Ethereum deposit CLI:

```bash
# Download deposit CLI
wget https://github.com/ethereum/staking-deposit-cli/releases/download/v2.7.0/staking_deposit-cli-fdab65d-linux-amd64.tar.gz
tar -xvf staking_deposit-cli-fdab65d-linux-amd64.tar.gz
cd staking_deposit-cli-*

# Generate keys
./deposit new-mnemonic --num_validators=1 --chain=zugchain
```

**Option B: Import Existing Keys**

If you already have validator keystores, place them in `~/validator_keys/`.

### Step 9: Import Keys into Prysm Wallet

```bash
validator accounts import \
  --keys-dir=$HOME/validator_keys \
  --wallet-dir=$HOME/zugchain-data/consensus/wallet
```

You will be prompted to:
1. Accept Prysm Terms of Service (`accept`)
2. Create a wallet password (minimum 8 characters)
3. Enter your keystore password

---

## Running the Validator Node

### Step 10: Start Execution Client (Geth)

Open a new screen session:

```bash
screen -S geth_node
```

Run Geth:

```bash
geth \
  --networkid=824642 \
  --datadir=$HOME/zugchain-data/execution \
  --http --http.api=eth,net,web3,engine,admin \
  --http.addr=0.0.0.0 --http.vhosts=* --http.corsdomain=* \
  --authrpc.addr=127.0.0.1 --authrpc.port=8551 --authrpc.vhosts=* \
  --authrpc.jwtsecret=$HOME/zugchain-data/secrets/jwt.hex \
  --bootnodes="enode://50ab841049b54f70874c6be9100e7a3d0e91329dda27cf09cecc4143b409d1c69d5787c885cf2735037ceda84b79998dfa52ce093a2a3dfec5dec4781dd50c8e@20.229.0.153:30303" \
  --syncmode=full \
  --verbosity=3
```

**Expected logs:**
- `Looking for peers peercount=1` (connection to main node established)

Detach from screen: `Ctrl+A`, then `D`

### Step 11: Start Consensus Client (Beacon Chain)

Open a new screen session:

```bash
screen -S beacon_node
```

Run Beacon Chain with checkpoint sync:

```bash
beacon-chain \
  --datadir=$HOME/zugchain-data/consensus \
  --chain-config-file=$HOME/zugchain-data/config/config.yml \
  --genesis-state=$HOME/zugchain-data/config/genesis.ssz \
  --execution-endpoint=http://127.0.0.1:8551 \
  --jwt-secret=$HOME/zugchain-data/secrets/jwt.hex \
  --p2p-tcp-port=13000 --p2p-udp-port=12000 \
  --min-sync-peers=0 \
  --bootstrap-node="enr:-Mq4QH3lH6OeuOM4DLIUjmF74N5zJbJUlXrbNiwX_qn0jditVTM8QdC7V0rshBY4fJUAm6f55J7KF2qVc6DpQ4MzVNiGAZxFLtW6h2F0dG5ldHOIAAAAAAAABgCEZXRoMpCBoWmuIAAABf__________gmlkgnY0gmlwhBTlAJmEcXVpY4IyyIlzZWNwMjU2azGhAzGPnxoCHYFpsbXFMplsnbjhvmNw_jmxiMt04N_hXAdwiHN5bmNuZXRzD4N0Y3CCMsiDdWRwgi7g" \
  --checkpoint-sync-url=http://20.229.0.153:3500 \
  --genesis-beacon-api-url=http://20.229.0.153:3500 \
  --accept-terms-of-use
```

**Expected logs:**
- `Synced to head of chain` (full sync achieved)
- `Synced new block slot=XXX` (receiving blocks)

Detach from screen: `Ctrl+A`, then `D`

### Step 12: Start Validator Client

Open a new screen session:

```bash
screen -S validator_node
```

Run the validator:

```bash
validator \
  --datadir=$HOME/zugchain-data/consensus \
  --wallet-dir=$HOME/zugchain-data/consensus/wallet \
  --chain-config-file=$HOME/zugchain-data/config/config.yml \
  --beacon-rpc-provider=127.0.0.1:4000 \
  --accept-terms-of-use
```

Enter your wallet password when prompted.

**Expected logs:**
- `Validator activated` (your validator is recognized)
- `Attestation sent` (actively participating in consensus)

Detach from screen: `Ctrl+A`, then `D`

---

## Monitoring and Management

### Screen Session Management

View all running screens:
```bash
screen -ls
```

Reattach to a screen:
```bash
screen -r geth_node      # Geth logs
screen -r beacon_node    # Beacon logs
screen -r validator_node # Validator logs
```

Terminate a screen session:
```bash
screen -X -S geth_node quit
```

### Health Checks

**Check Geth peers:**
```bash
geth attach http://localhost:8545 --exec 'admin.peers.length'
```

**Check Beacon sync status:**
```bash
curl -s http://localhost:3500/eth/v1/node/syncing | jq
```

**View validator status:**
```bash
validator accounts list --wallet-dir=$HOME/zugchain-data/consensus/wallet
```

---

## Security Best Practices

1. **Backup Critical Files:**
   - Mnemonic phrase (offline, secure storage)
   - Validator keystores (`~/validator_keys/`)
   - Wallet password (encrypted password manager)

2. **Firewall Configuration:**
   - Only expose P2P ports (30303, 13000, 12000)
   - Block RPC access from external networks

3. **System Hardening:**
   - Keep system packages updated
   - Use SSH key authentication only
   - Enable UFW or iptables firewall

4. **Monitoring:**
   - Set up alerting for validator downtime
   - Monitor disk space and CPU usage
   - Track attestation performance

---

## Troubleshooting

### Problem: Geth shows "Looking for peers" but peercount=0

**Solution:** Verify firewall rules allow port 30303 (TCP/UDP). Check that the main node (20.229.0.153) is reachable.

### Problem: Beacon shows "Waiting for suitable peers"

**Solution:** Ensure port 13000 (TCP) and 12000 (UDP) are open. Verify the ENR bootstrap node is accessible.

### Problem: Validator shows "DeadlineExceeded" errors

**Solution:** Beacon node is not synced. Wait for beacon to reach `Synced to head of chain` status.

### Problem: "Running on Ethereum Mainnet" warning during key import

**Solution:** This is a cosmetic warning from Prysm. The actual network is determined by `config.yml` during node runtime, not during key import.

---

## Support and Community

- **GitHub Issues:** [ZugChainLabs/zugchain-validator-configs](https://github.com/ZugChainLabs/zugchain-validator-configs/issues)
- **Documentation:** [docs.zugchain.org](https://docs.zugchain.org)
- **Discord:** [discord.gg/zugchain](https://discord.gg/zugchain)

---

## License

This repository is licensed under the MIT License. See [LICENSE](LICENSE) for details.

---

## Acknowledgments

Built on top of:
- [Geth](https://github.com/ethereum/go-ethereum)
- [Prysm](https://github.com/prysmaticlabs/prysm)
- Ethereum Foundation specifications
