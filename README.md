# Netmaker OpenVSwitch Integration with Mild Obfuscation

Automatically integrates Netmaker interfaces with OpenVSwitch and includes mild obfuscation features for enhanced privacy protection. This setup is particularly useful for systems like Proxmox VE where OpenVSwitch is commonly used.

## Features
- Automatic detection and integration of Netmaker interfaces
- OpenVSwitch bridge management
- **Mild obfuscation for privacy protection** (best gain/cost ratio)
  - VLAN tag rotation every 5 minutes
  - MAC address randomization every 30 minutes  
  - Basic timing obfuscation (max 50ms delay)
  - Traffic shaping for pattern disruption
- Systemd service for automatic operation on boot and Netmaker client start
- Clean installation and removal process
- Minimal performance impact (~15% overhead)

## Prerequisites
- OpenVSwitch installed and running
- Netmaker client (e.g., `netclient`) installed and configured
- Root/sudo access for installation

## Repository Structure

```
netmaker-ovs-integration/
├── 📄 README.md                              # Main documentation
├── 📄 DEPLOYMENT-GUIDE.md                    # Comprehensive deployment guide
├── 📄 INTERACTIVE-FEATURES.md                # Interactive installer features
├── 📄 README-OBFUSCATION.md                  # Technical obfuscation details
├── 📄 PROJECT-STRUCTURE.md                   # Complete project overview
├── 📄 .gitignore                             # Git ignore patterns
│
├── 🔧 Installation Scripts
│   ├── 📄 install-interactive.sh             # Interactive installer (RECOMMENDED)
│   ├── 📄 install.sh                         # Standard installer
│   ├── 📄 pre-install.sh                     # Pre-installation validation
│   └── 📄 uninstall.sh                       # Complete uninstaller
│
├── ⚙️ config/
│   └── 📄 ovs-config                         # Configuration with obfuscation settings
│
├── 🔨 scripts/
│   ├── 📄 netmaker-ovs-bridge-add.sh         # Enhanced with obfuscation
│   ├── 📄 netmaker-ovs-bridge-remove.sh      # Enhanced with cleanup
│   └── 📄 obfuscation-manager.sh             # Core obfuscation management
│
├── 🏃 systemd/
│   ├── 📄 netmaker-ovs-bridge.service        # Main integration service
│   └── 📄 netmaker-obfuscation-daemon.service # Obfuscation daemon
│
├── 📚 docs/                                  # Technical documentation
│   ├── 📄 DETECTION-RESISTANCE-DEEP-DIVE.md  # Advanced evasion techniques
│   ├── 📄 OVERHEAD-COST-ANALYSIS.md          # Performance impact analysis
│   ├── 📄 OVS-OBFUSCATION-ANALYSIS.md        # Comprehensive obfuscation analysis
│   └── 📄 PROXMOX-SPECIFIC-ANALYSIS.md       # Proxmox VE integration specifics
│
├── 💡 examples/                              # Configuration examples
│   ├── 📄 interfaces-ovs-corrected           # Corrected OVS interfaces
│   └── 📄 interfaces-standard                # Standard interfaces example
│
├── 🛠️ tools/                                 # Helper utilities
│   ├── 📄 configure-ovs-proxmox.sh           # Proxmox OVS configuration
│   ├── 📄 fix-mosquitto-lxc.sh               # Mosquitto LXC fixes
│   ├── 📄 reconfigure-container-networking.sh # Container networking
│   └── 📄 working-ovs-config.sh              # OVS configuration helper
│
└── 📖 reference/                             # Background materials
    ├── 📄 GHOSTBRIDGE-PROJECT-CONTEXT.md     # Original project context
    └── 📄 enhanced-integration-analysis.md   # Integration analysis
```

## Installation

**Three installation methods available:**

### Method 1: Interactive Installation (RECOMMENDED)
Guided setup with auto-detection and configuration assistance:
```bash
sudo ./install-interactive.sh
```

### Method 2: Manual Installation with Pre-checks
Traditional approach with pre-installation validation:

1.  **Clone the repository:**
    ```bash
    git clone <your-repository-url>
    cd netmaker-ovs-integration
    ```

2.  **Make scripts executable:**
    ```bash
    chmod +x pre-install.sh install.sh uninstall.sh
    ```

3.  **Run pre-installation cleanup and validation:**
    ```bash
    sudo ./pre-install.sh
    ```
    
    This script will:
    - Check for conflicts with existing installations
    - Backup current configuration
    - Clean up any conflicting network state
    - Validate system readiness
    - Generate a detailed report

4.  **Run the installer (requires sudo privileges):**
    ```bash
    sudo ./install.sh
    ```
    
    The installer will warn if pre-install wasn't run and offer to continue anyway.

### Method 3: Quick Installation
Direct installation (not recommended for production):
```bash
sudo ./install.sh
```

**Note:** The quick method will warn about missing pre-checks and suggest using the interactive installer.

## Quick Start

For immediate deployment with auto-detection:

```bash
# Clone and deploy in one command
git clone <repository-url>
cd netmaker-ovs-integration
sudo ./install-interactive.sh
```

The interactive installer will guide you through:
- ✅ System detection and validation
- ✅ Intelligent configuration recommendations  
- ✅ Obfuscation level selection
- ✅ Complete installation with verification

## Configuration
The main configuration file is installed at `/etc/netmaker/ovs-config`. You can edit this file to change:

### Basic Settings
-   `BRIDGE_NAME`: The name of the OpenVSwitch bridge to use (default: `ovsbr0`)
-   `NM_INTERFACE_PATTERN`: The pattern to identify Netmaker interfaces (default: `nm-*`)

### Obfuscation Settings
-   `ENABLE_OBFUSCATION`: Enable/disable obfuscation features (default: `true`)
-   `VLAN_OBFUSCATION`: Enable VLAN tag rotation (default: `true`)
-   `VLAN_POOL`: Available VLAN tags for rotation (default: `"100,200,300,400,500"`)
-   `VLAN_ROTATION_INTERVAL`: Seconds between VLAN changes (default: `300`)
-   `MAC_RANDOMIZATION`: Enable MAC address rotation (default: `true`)
-   `MAC_ROTATION_INTERVAL`: Seconds between MAC changes (default: `1800`)
-   `TIMING_OBFUSCATION`: Enable basic timing delays (default: `true`)
-   `MAX_DELAY_MS`: Maximum delay in milliseconds (default: `50`)
-   `TRAFFIC_SHAPING`: Enable traffic rate limiting (default: `true`)
-   `SHAPING_RATE_MBPS`: Rate limit in Mbps (default: `100`)

After changing the configuration, restart the services:
```bash
sudo systemctl restart netmaker-ovs-bridge
sudo systemctl restart netmaker-obfuscation-daemon
```

## Usage
The integration service runs automatically with obfuscation daemon. You can manage both services using standard `systemctl` commands:

* Check status:
    ```bash
    systemctl status netmaker-ovs-bridge
    systemctl status netmaker-obfuscation-daemon
    ```

* Restart services:
    ```bash
    sudo systemctl restart netmaker-ovs-bridge
    sudo systemctl restart netmaker-obfuscation-daemon
    ```

* View logs:
    ```bash
    journalctl -u netmaker-ovs-bridge
    journalctl -u netmaker-obfuscation-daemon
    ```

* Manual obfuscation control:
    ```bash
    # Apply obfuscation to interface
    sudo /usr/local/bin/obfuscation-manager.sh apply nm-example ovsbr0
    
    # Remove obfuscation from interface
    sudo /usr/local/bin/obfuscation-manager.sh remove nm-example ovsbr0
    
    # Force rotation of obfuscation parameters
    sudo /usr/local/bin/obfuscation-manager.sh rotate nm-example ovsbr0
    ```

## Uninstallation

**Automated Uninstallation (Recommended):**

```bash
sudo ./uninstall.sh
```

The uninstall script will:
- Stop and disable all services
- Remove obfuscation from active interfaces
- Clean up OVS integration
- Remove all installed files
- Optionally restore original configuration from backup
- Generate uninstallation report

**Manual Uninstallation:**

If you prefer manual removal, key steps involve:

1.  Stopping and disabling the systemd services:
    ```bash
    sudo systemctl stop netmaker-ovs-bridge
    sudo systemctl stop netmaker-obfuscation-daemon
    sudo systemctl disable netmaker-ovs-bridge
    sudo systemctl disable netmaker-obfuscation-daemon
    ```
2.  Removing the installed files:
    ```bash
    sudo rm -f /usr/local/bin/netmaker-ovs-bridge-add.sh
    sudo rm -f /usr/local/bin/netmaker-ovs-bridge-remove.sh
    sudo rm -f /usr/local/bin/obfuscation-manager.sh
    sudo rm -f /etc/systemd/system/netmaker-ovs-bridge.service
    sudo rm -f /etc/systemd/system/netmaker-obfuscation-daemon.service
    sudo rm -f /etc/netmaker/ovs-config
    sudo rm -rf /var/lib/netmaker/obfuscation-state
    # Consider removing /etc/netmaker directory if it's empty and no longer needed
    # sudo rmdir /etc/netmaker 2>/dev/null || true
    ```
3.  Reloading systemd:
    ```bash
    sudo systemctl daemon-reload
    ```
4.  (Optional) Removing the Netmaker interface from the OVS bridge if it's still there (the `ExecStop` script should handle this if the service was stopped gracefully).

## Troubleshooting
* Verify OVS is installed and running:
    ```bash
    ovs-vsctl show
    ```
* Check if the OVS bridge exists (replace `<BRIDGE_NAME>` with your actual bridge name):
    ```bash
    ovs-vsctl br-exists <BRIDGE_NAME>
    # e.g., ovs-vsctl br-exists ovsbr0
    ```
* Check service status and logs (as shown in the Usage section).
* Ensure Netmaker interface is up:
    ```bash
    ip link show
    # Look for an interface matching NM_INTERFACE_PATTERN.
    ```

## License
MIT License (You can replace this with your preferred license)
netmaker-ovs-integration
