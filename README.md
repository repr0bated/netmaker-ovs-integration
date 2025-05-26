# Netmaker OpenVSwitch Integration

Automatically integrates Netmaker interfaces with OpenVSwitch. This setup is particularly useful for systems like Proxmox VE where OpenVSwitch is commonly used.

## Features
- Automatic detection and integration of Netmaker interfaces.
- OpenVSwitch bridge management.
- Systemd service for automatic operation on boot and Netmaker client start.
- Clean installation and removal process.

## Prerequisites
- OpenVSwitch installed and running.
- Netmaker client (e.g., `netclient`) installed and configured.

## Repository Structure

```
netmaker-ovs-integration/
├── .gitignore
├── README.md
├── config/
│   └── ovs-config
├── install.sh
├── scripts/
│   ├── netmaker-ovs-bridge-add.sh
│   └── netmaker-ovs-bridge-remove.sh
└── systemd/
    └── netmaker-ovs-bridge.service
```

## Installation

1.  **Clone the repository:**
    ```bash
    git clone <your-repository-url>
    cd netmaker-ovs-integration
    ```

2.  **Make the installer executable:**
    ```bash
    chmod +x install.sh
    ```

3.  **Run the installer (requires sudo privileges):**
    ```bash
    sudo ./install.sh
    ```

## Configuration
The main configuration file is installed at `/etc/netmaker/ovs-config`. You can edit this file to change:
-   `BRIDGE_NAME`: The name of the OpenVSwitch bridge to use (default: `ovsbr0`).
-   `NM_INTERFACE_PATTERN`: The pattern to identify Netmaker interfaces (default: `nm-*`).

After changing the configuration, you might need to restart the service:
```bash
sudo systemctl restart netmaker-ovs-bridge
```

## Usage
The integration service runs automatically. You can manage it using standard `systemctl` commands:

* Check status:
    ```bash
    systemctl status netmaker-ovs-bridge
    ```

* Restart service:
    ```bash
    sudo systemctl restart netmaker-ovs-bridge
    ```

* View logs:
    ```bash
    journalctl -u netmaker-ovs-bridge
    ```

## Uninstallation
To uninstall, you can adapt the removal steps from the `install.sh` script or use the following commands. Key steps involve:

1.  Stopping and disabling the systemd service:
    ```bash
    sudo systemctl stop netmaker-ovs-bridge
    sudo systemctl disable netmaker-ovs-bridge
    ```
2.  Removing the installed files:
    ```bash
    sudo rm -f /usr/local/bin/netmaker-ovs-bridge-add.sh
    sudo rm -f /usr/local/bin/netmaker-ovs-bridge-remove.sh
    sudo rm -f /etc/systemd/system/netmaker-ovs-bridge.service
    sudo rm -f /etc/netmaker/ovs-config # Use -f to avoid error if dir doesn't exist
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
