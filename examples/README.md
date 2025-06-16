# Configuration Examples

This directory contains reference configuration files and examples for various deployment scenarios of the Netmaker OVS Integration.

## Available Examples

### 🔗 **interfaces-ovs-corrected**
**Corrected OpenVSwitch Network Interfaces Configuration**

A properly formatted `/etc/network/interfaces` file that follows official Debian OVS guidelines for OpenVSwitch integration.

**Key Features:**
- Correct `allow-ovs` stanza usage instead of `auto` for OVS bridges
- Proper port declarations with `allow-<bridge>` format
- Fixed case sensitivity (`OVSPort` not `OVSport`)
- Clear bridge-to-port relationships
- MTU consistency across related interfaces

**Use Cases:**
- Reference for proper OVS interfaces syntax
- Template for Proxmox VE OVS network configuration
- Troubleshooting guide for common OVS configuration errors
- Basis for automated network setup scripts

**Integration Points:**
- Compatible with Netmaker mesh networking
- Supports VLAN obfuscation features
- Designed for Proxmox VE environments
- Follows systemd/ifupdown best practices

---

### 🌉 **interfaces-standard**  
**Standard Linux Bridge Network Configuration**

A traditional Linux bridge configuration using standard kernel bridges instead of OpenVSwitch.

**Key Features:**
- Standard Linux bridge configuration syntax
- Compatible with bridge-utils
- Simpler setup for basic networking needs
- Lower resource overhead compared to OVS

**Use Cases:**
- Alternative to OVS for simpler deployments
- Fallback configuration for systems without OVS
- Comparison reference for OVS vs standard bridges
- Educational example of Linux networking fundamentals

**Integration Notes:**
- Limited obfuscation capabilities compared to OVS
- May require different Netmaker integration approach
- Suitable for resource-constrained environments

## Configuration Comparison

| Feature | OVS (interfaces-ovs-corrected) | Standard (interfaces-standard) |
|---------|--------------------------------|--------------------------------|
| **VLAN Support** | Advanced (802.1Q, QinQ) | Basic (802.1Q only) |
| **Obfuscation** | Full support | Limited |
| **Performance** | Higher overhead | Lower overhead |
| **Flexibility** | Very high | Moderate |
| **Complexity** | Higher | Lower |
| **Resource Usage** | More CPU/Memory | Less CPU/Memory |

## Usage Instructions

### 🔧 **Deploying OVS Configuration**

```bash
# Backup current configuration
sudo cp /etc/network/interfaces /etc/network/interfaces.backup

# Copy OVS configuration
sudo cp examples/interfaces-ovs-corrected /etc/network/interfaces

# Restart networking (use with caution on remote systems)
sudo systemctl restart networking

# Verify OVS bridges
ovs-vsctl show
```

### 🌉 **Deploying Standard Configuration**

```bash
# Backup current configuration  
sudo cp /etc/network/interfaces /etc/network/interfaces.backup

# Copy standard configuration
sudo cp examples/interfaces-standard /etc/network/interfaces

# Install bridge utilities if needed
sudo apt install bridge-utils

# Restart networking
sudo systemctl restart networking

# Verify bridges
brctl show
```

## Customization Guidelines

### 🎯 **Adapting for Your Environment**

#### **IP Address Ranges**
Update IP addresses to match your network:
```bash
# In the configuration files, change:
address 10.0.0.101/24    # To your desired IP
gateway 10.0.0.1         # To your gateway IP
```

#### **Interface Names**
Modify interface names to match your hardware:
```bash
# Change physical interface names:
eth0     # To your actual interface (e.g., ens18, enp0s3)
eth1     # To your secondary interface if applicable
```

#### **Bridge Names**
Customize bridge names for your deployment:
```bash
# OVS bridges
ovsbr0   # Primary bridge for Netmaker
ovsbr1   # Secondary bridge for management

# Standard bridges  
br0      # Primary bridge
br1      # Secondary bridge
```

### ⚙️ **VLAN Configuration**

For the OVS configuration, you can add VLAN support:
```bash
# Add VLAN interface example
allow-ovsbr0 vlan100
iface vlan100 inet static
    address 192.168.100.1/24
    ovs_bridge ovsbr0
    ovs_type OVSIntPort
    ovs_options tag=100
```

### 🔐 **Security Considerations**

#### **Network Isolation**
- Use separate bridges for different security zones
- Implement proper VLAN segmentation
- Configure firewall rules appropriately

#### **Management Access**
- Ensure management interfaces remain accessible
- Test configuration changes on non-production systems
- Always maintain console access during network changes

## Integration with Netmaker OVS

### 🔗 **Bridge Selection**

The Netmaker OVS integration will use the bridge specified in `/etc/netmaker/ovs-config`:

```bash
# For OVS configuration
BRIDGE_NAME=ovsbr0

# For standard bridge configuration  
BRIDGE_NAME=br0  # Note: Limited obfuscation features
```

### 🛡️ **Obfuscation Compatibility**

| Configuration | VLAN Rotation | MAC Randomization | Timing Obfuscation | Traffic Shaping |
|---------------|---------------|-------------------|-------------------|-----------------|
| **OVS Corrected** | ✅ Full Support | ✅ Full Support | ✅ Full Support | ✅ Full Support |
| **Standard Bridge** | ❌ Not Available | ⚠️ Limited | ❌ Not Available | ⚠️ Basic |

## Troubleshooting Examples

### 🔍 **Common Issues and Solutions**

#### **OVS Configuration Issues**
```bash
# Check OVS service status
systemctl status openvswitch-switch

# Verify bridge configuration
ovs-vsctl show

# Check for syntax errors
ifup --all --dry-run
```

#### **Standard Bridge Issues**
```bash
# Check bridge status
brctl show

# Verify bridge utilities installation
dpkg -l | grep bridge-utils

# Test interface configuration
ip addr show
```

### 📝 **Validation Scripts**

Check the `tools/` directory for validation scripts:
- `configure-ovs-proxmox.sh` - OVS setup validation
- `working-ovs-config.sh` - Configuration testing

## Best Practices

### 📋 **Pre-Deployment**
1. **Always backup** existing network configuration
2. **Test changes** in a lab environment first
3. **Verify hardware** interface names before deployment
4. **Plan IP addressing** to avoid conflicts

### 🔄 **Post-Deployment**
1. **Verify connectivity** to all required services
2. **Test Netmaker integration** with the chosen bridge
3. **Monitor performance** for any degradation
4. **Document changes** for future reference

### 🚨 **Emergency Recovery**
1. **Keep backup configuration** accessible
2. **Maintain console access** during changes
3. **Have rollback plan** ready
4. **Test recovery procedures** beforehand

These examples provide a solid foundation for deploying Netmaker OVS integration across various network configurations while maintaining compatibility with different deployment scenarios and requirements.