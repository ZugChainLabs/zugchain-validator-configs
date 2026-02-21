# ⚡ ZugChain Validator Deployment Suite (Enterprise Edition)

> [!WARNING]  
> **Linux Exclusivity**  
> This deployment suite and its tools are designed **exclusively for Linux environments** (Ubuntu 22.04 LTS or 24.04 LTS recommended). Do not attempt to run these scripts on Windows or macOS.

Welcome to the **ZugChain** Validator Setup Guide! ZugChain is a high-performance, EVM-compatible Proof-of-Stake (PoS) blockchain designed for institutional-grade reliability.

This repository provides everything you need to easily join the ZugChain network as a **Validator Node**. Whether you are an experienced DevOps engineer or setting up a node for the very first time, this guide will walk you through the process step-by-step.

> [!TIP]
> **Auto-Architecture Detection:** This suite automatically detects your server's hardware architecture.** Just run the scripts, and it will deploy the optimized binaries for either **x86_64** (Intel/AMD) or **ARM64** (Apple Silicon, AWS Graviton).

---

## 📋 Table of Contents
1. [🖥️ System Requirements](#️-system-requirements)
2. [📛 Critical: Network & Firewall](#-critical-network--firewall)
3. [🚀 Step-by-Step Setup Guide](#-step-by-step-setup-guide)
4. [🔐 Key Management & Activation](#-key-management--activation)
5. [🛠️ Operations & Monitoring](#️-operations--monitoring)
6. [❓ Troubleshooting](#-troubleshooting)

---

## 🖥️ System Requirements

Ideally suited for high-availability environments, ZugChain validators require robust hardware to ensure network stability and maximize uptime rewards.

| Component | Minimum Specification | Recommended (Production) |
| :--- | :--- | :--- |
| **CPU** | 4 Cores | 8 Cores (AMD Ryzen 7000+ / Intel Xeon / ARM) |
| **RAM** | 8 GB | 32 GB+ DDR5 |
| **Storage** | 500 GB SSD | 2 TB NVMe SSD (High IOPS required) |
| **OS** | Ubuntu 22.04 LTS | Ubuntu 24.04 LTS (Strictly Linux) |
| **Network** | 100 Mbps Up/Down | 1 Gbps Fiber (Static IP Required) |

---

## � Critical: Network & Firewall

Before installing **ANYTHING**, you **MUST** open specific network ports. If these ports are closed, your node will have **zero peers** and will fail to synchronize with the blockchain.

You need to open these ports on your **Operating System Firewall** (e.g., `ufw` on Ubuntu) AND your **Cloud Provider's Firewall** (e.g., AWS Security Groups, Vultr Firewall rules).

| Port | Protocol | Service | Purpose |
| :--- | :--- | :--- | :--- |
| **30303** | `TCP` & `UDP` | Execution (Geth) | P2P Peering (Required for Sync) |
| **13000** | `TCP` | Consensus (Beacon) | P2P Peering (Required for Attestations) |
| **12000** | `UDP` | Consensus (Beacon) | P2P Discovery (Required for Sync) |
| **3500** | `TCP` | API (Lighthouse) | API (Required for Validator) |

### Quick Firewall Setup (Ubuntu UFW)

If you are using `ufw` on Ubuntu, copy and paste these commands one by one to configure your firewall correctly:

```bash
sudo ufw allow 30303
```
```bash
sudo ufw allow 13000/tcp
```
```bash
sudo ufw allow 3500/tcp
```
```bash
sudo ufw allow 12000/udp
```
```bash
sudo ufw enable
```

---

## 🚀 Step-by-Step Setup Guide

Follow these simple steps in order. Take your time and make sure each step completes successfully before moving to the next one.

### Step 1: Install Geth (Execution Client)

Before doing anything else, your Linux machine needs `geth` installed. Geth is the software that executes the smart contracts on the blockchain.

Add the official Ethereum repository:
```bash
sudo add-apt-repository -y ppa:ethereum/ethereum
```

Update your package lists:
```bash
sudo apt-get update
```

Install the Ethereum package:
```bash
sudo apt-get install ethereum -y
```

**Verify the Installation:**
Ensure `geth` was installed correctly by checking its version. It should return version details without any errors.
```bash
geth version
```

### Step 2: Clone the Repository

Next, download this automated setup repository to your server.

```bash
git clone https://github.com/ZugChainLabs/zugchain-validator-configs.git
```

Move into the downloaded directory:
```bash
cd zugchain-validator-configs
```

### Step 3: Initialize the Node

Now, you will run the initialization script. This script automatically configures the execution and consensus clients based on your server's hardware.

Navigate to the `validator` folder:
```bash
cd validator
```

Grant execution permissions to the script:
```bash
chmod +x join_network.sh
```

Run the script with administrator privileges:
```bash
sudo ./join_network.sh
```


---

## 🔐 Key Management & Activation

To earn rewards and participate in the network, you must generate validator keys and import them. The system needs these keys in a special encrypted wallet.

### Step 1: Generate Keys

You must generate your keys securely using the official CLI.

1. Go to the [ZugChain Deposit CLI Tool](https://github.com/ZugChainLabs/zugchain-deposit-cli).
2. Follow their instructions to generate your validator keys.
3. Keep the generated `keystore-m...json` file and the **password** you used for it very safe.

### Step 2: Transfer Keys to the Server

You need to put your `keystore` file and your password onto your Linux server.

> [!IMPORTANT]
> The exact filename of your keystore will look something like `keystore-m_12381_3600_0_0_0-1771503650.json`. Always use your actual filename.

Create a folder for your keys:
```bash
mkdir -p ~/zug_keys
```

**Choose ONE method to put your keys on the server:**

<details>
<summary><b>Option A: Copy & Paste via Terminal (Simplest)</b></summary>

Open a new empty file in the terminal, using the **EXACT name** of your generated keystore file:
```bash
nano ~/zug_keys/keystore-m_...json
```
*(Replace `keystore-m_...json` with your actual filename! Paste the contents of your physical keystore file inside. Then press `Ctrl+O`, hit `Enter` to save, and press `Ctrl+X` to exit.)*

Create your password file:
```bash
echo "YOUR_KEYSTORE_PASSWORD" > ~/zug_keys/password.txt
```
*(Make sure to replace `YOUR_KEYSTORE_PASSWORD` with your actual password!)*

</details>

<details>
<summary><b>Option B: File Transfer (Advanced)</b></summary>

Use SFTP or SCP to directly upload your `keystore-m_...json` file into the `~/zug_keys` directory on your server.

Then create your password file:
```bash
echo "YOUR_KEYSTORE_PASSWORD" > ~/zug_keys/password.txt
```
</details>

### Step 3: Import the Keys (Crucial Step)

Now, you will import the uploaded keys into the validator's secure wallet. **Do not skip this!**

Run this exact command (adjusting the filename if you uploaded it directly):
```bash
/usr/local/bin/validator accounts import \
    --keys-dir=$HOME/zug_keys \
    --wallet-dir=/opt/zugchain/data/validators \
    --account-password-file=$HOME/zug_keys/password.txt
```

**During this process:**
1. The terminal will ask you to create a **NEW Wallet Password**. (This can be the same or different from your keystore password).
2. **IMMEDIATELY** save this new wallet password to your server, so your validator can start automatically after reboots:

```bash
echo "YOUR_NEW_WALLET_PASSWORD" > /opt/zugchain/data/validators/wallet-password.txt
```

> [!CAUTION]
> If you fail to save the `wallet-password.txt` file exactly as shown above, your Validator service will fail to restart automatically and will display a "No accounts found" error.

### Step 4: Start the Validator Service

With your keys imported and password saved, you can officially start participating!

```bash
sudo systemctl start zugchain-validator
```

---

## 🛠️ Operations & Monitoring

It is your responsibility to keep your node online. Prolonged downtime can result in slashing penalties.

### Checking Service Status

Make sure everything is running smoothly with these commands:

Check the **Execution Layer (Geth)**:
```bash
systemctl status zugchain-geth
```

Check the **Consensus Layer (Beacon Chain)**:
```bash
systemctl status zugchain-beacon
```

Check the **Validator Client**:
```bash
systemctl status zugchain-validator
```

*(Press `Q` on your keyboard to exit the status screen).*

### Viewing Live Logs

Logs help you see what the node is doing right now in real-time.

Watch **Geth Logs**:
```bash
journalctl -fu zugchain-geth
```

Watch **Beacon Chain Logs** (Use this to check your Sync Status and Peer Count):
```bash
journalctl -fu zugchain-beacon
```

Watch **Validator Logs** (Use this to check if you are Attesting correctly):
```bash
journalctl -fu zugchain-validator
```

*(Press `Ctrl+C` to stop watching the logs).*

### Restarting the Entire Stack

If you make changes or need to refresh the whole node, run this combined restart command:
```bash
sudo systemctl restart zugchain-geth zugchain-beacon zugchain-validator
```

---

## ❓ Troubleshooting

### 1. "I have 0 Peers" or my peer count is very low
* Your firewall is almost certainly blocking connections.
* Double-check that ports **30303** (TCP/UDP), **13000** (TCP), and **12000** (UDP) are open on **both** Ubuntu `ufw` AND your cloud provider's web dashboard.
* Verify your `Bootnode` address is correct in `/opt/zugchain/config/config.toml`.

### 2. "Genesis Hash Mismatch" Error
* This means your configuration files are outdated compared to the rest of the network.
* **Fix**: Pull the latest code by running `git pull` from the `zugchain-validator-configs` directory, then re-run the `join_network.sh` script.

### 3. Validator logs say: "Waiting for beacon chain to sync"
* This is perfectly normal! The validator cannot do its job until the Beacon Chain has downloaded the entire history of the blockchain.
* Just be patient. Keep an eye on the beacon logs (`journalctl -fu zugchain-beacon`). Once the sync reaches 100%, your validator will automatically start working.

---

**ZugChain Labs** • *Powering the Future of Decentralized Finance.*
