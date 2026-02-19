# ⚡ ZugChain Validator Deployment Suite (Enterprise Edition)

**ZugChain** is a high-performance, EVM-compatible Proof-of-Stake (PoS) blockchain designed for institutional-grade reliability and scalability. This repository provides the essential binaries, configurations, and automated deployment tools required to join the ZugChain network as a **Validator Node**.

This suite features **Auto-Architecture Detection**, ensuring seamless deployment on both **x86_64** (Intel/AMD) and **ARM64** (Apple Silicon, AWS Graviton) infrastructures by automatically utilizing the appropriate optimized binaries.

---

## 📋 Table of Contents
1. [System Requirements](#-system-requirements)
2. [Repository Architecture](#-repository-architecture)
3. [Validator Setup Guide](#-validator-setup-guide)
4. [Key Management & Activation](#-key-management--activation)
5. [Operations & Monitoring](#-operations--monitoring)
6. [Troubleshooting](#-troubleshooting)

---

## 🖥️ System Requirements

Ideally suited for high-availability environments, ZugChain validators require robust hardware to ensure network stability and maximize uptime rewards.

| Component | Minimum Specification | Recommended (Production) |
| :--- | :--- | :--- |
| **CPU** | 4 Cores | 8 Cores (AMD Ryzen 7000+ / Intel Xeon / Apple M-Series) |
| **RAM** | 16 GB | 32 GB+ DDR5 |
| **Storage** | 500 GB SSD | 2 TB NVMe SSD (High IOPS required) |
| **OS** | Ubuntu 22.04 LTS | Ubuntu 24.04 LTS |
| **Network** | 100 Mbps Up/Down | 1 Gbps Fiber (Static IP Required) |

---

## 📂 Repository Architecture

This repository is streamlined for validator operations only. Chain genesis and master node configurations are managed upstream.

* **`validator/`**: Scripts and configuration templates for node deployment.
* **`bin/`**: Pre-compiled, optimized core binaries (`geth`, `beacon-chain`, `validator`).
    * `bin/x86`: For standard Intel/AMD servers.
    * `bin/arm64`: For ARM-based infrastructure.
* **`config/`**: Network genesis and consensus configuration files.

---

## 🚀 Validator Setup Guide

Follow these steps to deploy your node and sync with the ZugChain network.

### Prerequisites
Ensure you have the following information from the Network Administrator or Documentation:
*   **Bootnode ENODE:** The entry point for the execution layer P2P network.
*   **Bootstrap ENR:** The entry point for the consensus layer P2P network.

### Step 1: Clone the Repository
Clone this repository to your dedicated validator server.

```bash
git clone https://github.com/ZugChainLabs/zugchain-validator-configs.git
cd zugchain-validator-configs
```

### Step 2: Initialize the Node
The initialization script will detect your system architecture and configure the execution and consensus clients.

```bash
cd validator
chmod +x join_network.sh
sudo ./join_network.sh
```
*Follow the on-screen prompts to input the Bootnode and Bootstrap ENR information.*

---

## 🔐 Key Management & Activation

To participate in the network, you must generate validator keys and import them into the lighthouse validator client. The validator service **does not** read raw JSON files directly; it requires an encrypted wallet database created through the import process.

### Step 1: Generate Keys
Use the official **ZugChain Deposit CLI** to generate your validator keys (`keystore-m...json`) and `deposit_data...json`.
*   **Tool:** [ZugChain Deposit CLI](https://github.com/ZugChainLabs/zugchain-deposit-cli)
*   **Action:** Follow the instructions in the CLI repository to generate your keys. You will need the `keystore` JSON file and the password you used to encrypt it.

### Step 2: Prepare Keys on Server
You need to get your `keystore` file and your password onto the validator server. Choose **one** of the following methods:

#### Option A: File Transfer (SCP/SFTP)
If you can transfer files to your server:
1.  Create a temporary directory: `mkdir -p ~/zug_keys`
2.  Upload your `keystore-m_....json` file to `~/zug_keys`.
3.  Create a password file: `echo "YOUR_KEYSTORE_PASSWORD" > ~/zug_keys/password.txt`

#### Option B: Manual Creation (Copy-Paste)
If you only have terminal access:
1.  Create the directory: `mkdir -p ~/zug_keys`
2.  Create the keystore file:
    ```bash
    nano ~/zug_keys/keystore-m_12381_3600_0_0_0-1771503650.json  # (IMPORTANT: Use your actual keystore filename!)
    # Paste the content of your keystore JSON here. Save (Ctrl+O) and Exit (Ctrl+X).
    ```
3.  Create the password file:
    ```bash
    echo "YOUR_KEYSTORE_PASSWORD" > ~/zug_keys/password.txt
    ```

### Step 3: Import Keys (Critical)
Regardless of how you uploaded the files, you **must** run the import command. This encrypts your keys into the validator's native wallet database.

**Run the Import Command:**
```bash
/usr/local/bin/validator accounts import \
    --keys-dir=~/zug_keys \
    --wallet-dir=/opt/zugchain/data/validators \
    --account-password-file=~/zug_keys/password.txt
```

**During this process:**
1.  The tool will ask you to create a **Wallet Password** (this is different from your keystore password).
2.  **IMMEDIATELY** save this new wallet password to the server, as the service needs it to auto-start:

```bash
# Replace 'YOUR_NEW_WALLET_PASSWORD' with the password you just created
echo "YOUR_NEW_WALLET_PASSWORD" > /opt/zugchain/data/validators/wallet-password.txt
```

> **⚠️ Why is this necessary?**
> The `zugchain-validator` service is configured to read from the encrypted database at `/opt/zugchain/data/validators`. If you skip this import step or fail to save the `wallet-password.txt`, the service will fail with a "No accounts found" error.

### Step 4: Start the Validator Service
Once the keys are imported and the password file is in place, start the service:

```bash
sudo systemctl start zugchain-validator
```

---

## 🛠 Operations & Monitoring

We recommend proactively monitoring your node to avoid slashing penalties due to downtime.

### Service Status
Check the status of the three core services:

```bash
# Execution Layer (Geth)
systemctl status zugchain-geth

# Consensus Layer (Beacon Chain)
systemctl status zugchain-beacon

# Validator Client
systemctl status zugchain-validator
```

### Real-time Logs
View live logs to debug issues or verify synchronization.

```bash
# Execution Logs
journalctl -fu zugchain-geth

# Consensus Logs (Check Peer Count & Sync Status)
journalctl -fu zugchain-beacon

# Validator Logs (Check Attestations & Proposals)
journalctl -fu zugchain-validator
```

### Service Management
To restart the entire stack safely:

```bash
sudo systemctl restart zugchain-geth zugchain-beacon zugchain-validator
```

---

## ❓ Troubleshooting

### 1. Peer Count is Zero or Low
*   Ensure firewall ports are open:
    *   **30303** (TCP/UDP) - Execution P2P
    *   **13000** (TCP) - Consensus P2P
    *   **12000** (UDP) - Consensus P2P
*   Verify the `Bootnode` address in `/opt/zugchain/config/config.toml`.

### 2. "Genesis Hash Mismatch"
*   This indicates your configuration files are outdated.
*   **Solution**: Pull the latest changes from the repository (`git pull`) and re-run the setup script.

### 3. Validator "Waiting for beacon chain to sync"
*   The validator client cannot operate until the Beacon Chain is fully synchronized.
*   Check sync status via `journalctl -fu zugchain-beacon`. Once synced, the validator will automatically begin its duties.

---

**ZugChain Labs** - *Powering the Future of Decentralized Finance.*
