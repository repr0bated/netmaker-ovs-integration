#!/bin/bash
set -euo pipefail

# Interactive Netmaker OVS Integration Installer
# Auto-detects system configuration and provides guided setup

SCRIPT_VERSION="1.0.0"
INTERACTIVE_LOG="/tmp/netmaker-ovs-interactive-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration variables (will be populated)
declare -A CONFIG
declare -A DETECTED
declare -A CHOICES

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$INTERACTIVE_LOG"
}

# Colored output functions
error() {
    echo -e "${RED}ERROR: $1${NC}" | tee -a "$INTERACTIVE_LOG"
}

warning() {
    echo -e "${YELLOW}WARNING: $1${NC}" | tee -a "$INTERACTIVE_LOG"
}

info() {
    echo -e "${BLUE}INFO: $1${NC}" | tee -a "$INTERACTIVE_LOG"
}

success() {
    echo -e "${GREEN}SUCCESS: $1${NC}" | tee -a "$INTERACTIVE_LOG"
}

prompt() {
    echo -e "${CYAN}$1${NC}"
}

highlight() {
    echo -e "${PURPLE}$1${NC}"
}

# Display banner
show_banner() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║        Netmaker OVS Integration Interactive Installer        ║"
    echo "║                    with Mild Obfuscation                     ║"
    echo "║                                                              ║"
    echo "║                      Version $SCRIPT_VERSION                            ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
}

# Check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root. Please use sudo."
        exit 1
    fi
}

# Check if pre-install was run
check_preinstall() {
    if [ ! -d /tmp/netmaker-ovs-backup-* ] 2>/dev/null; then
        warning "Pre-installation script has not been run."
        echo
        prompt "It is STRONGLY recommended to run './pre-install.sh' first to:"
        echo "  • Check for conflicts and backup configurations"
        echo "  • Clean up existing installations"  
        echo "  • Validate system readiness"
        echo
        
        local choice
        while true; do
            prompt "Do you want to:"
            echo "  1) Exit and run pre-install.sh first (RECOMMENDED)"
            echo "  2) Continue with installation anyway"
            echo "  3) Run pre-install.sh now"
            echo
            read -p "Enter choice (1-3): " choice
            
            case $choice in
                1)
                    info "Please run './pre-install.sh' and then restart this installer."
                    exit 0
                    ;;
                2)
                    warning "Proceeding without pre-installation checks..."
                    break
                    ;;
                3)
                    if [ -f "./pre-install.sh" ]; then
                        info "Running pre-installation script..."
                        if ./pre-install.sh; then
                            success "Pre-installation completed successfully!"
                            echo
                            prompt "Press Enter to continue with installation..."
                            read
                            break
                        else
                            error "Pre-installation failed. Please fix issues and retry."
                            exit 1
                        fi
                    else
                        error "pre-install.sh not found in current directory."
                        exit 1
                    fi
                    ;;
                *)
                    warning "Invalid choice. Please enter 1, 2, or 3."
                    ;;
            esac
        done
    else
        success "Pre-installation appears to have been run."
    fi
}

# Auto-detect system configuration
detect_system_config() {
    info "Detecting system configuration..."
    
    # Detect existing OVS bridges
    local existing_bridges=$(ovs-vsctl list-br 2>/dev/null || echo "")
    DETECTED[existing_bridges]="$existing_bridges"
    
    # Detect Netmaker interfaces
    local netmaker_interfaces=$(ip link show | grep -o 'nm-[^:@]*' 2>/dev/null || echo "")
    DETECTED[netmaker_interfaces]="$netmaker_interfaces"
    
    # Detect Netmaker services
    local netmaker_services=""
    for service in netmaker netclient netmaker.service netclient.service; do
        if systemctl list-unit-files | grep -q "$service"; then
            netmaker_services="$netmaker_services $service"
        fi
    done
    DETECTED[netmaker_services]="$(echo $netmaker_services | xargs)"
    
    # Detect existing network configuration
    DETECTED[network_interfaces]=$(ip link show | grep -E '^[0-9]+:' | cut -d':' -f2 | tr -d ' ' | grep -v lo)
    
    # Detect VLAN usage
    local used_vlans=""
    for vlan in 100 200 300 400 500; do
        if ip link show | grep -q "\.${vlan}@" || ovs-vsctl show 2>/dev/null | grep -q "tag.*$vlan"; then
            used_vlans="$used_vlans $vlan"
        fi
    done
    DETECTED[used_vlans]="$(echo $used_vlans | xargs)"
    
    # Detect system resources
    DETECTED[memory_mb]=$(free -m | awk 'NR==2{print $2}')
    DETECTED[cpu_cores]=$(nproc)
    DETECTED[disk_space_gb]=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    
    # Detect network namespace information
    DETECTED[netns_count]=$(ip netns list 2>/dev/null | wc -l || echo "0")
    
    # Detect container runtime
    local container_runtime=""
    if command -v docker >/dev/null 2>&1; then
        container_runtime="$container_runtime docker"
    fi
    if command -v podman >/dev/null 2>&1; then
        container_runtime="$container_runtime podman"
    fi
    if [ -f /usr/bin/pct ]; then
        container_runtime="$container_runtime proxmox-lxc"
    fi
    DETECTED[container_runtime]="$(echo $container_runtime | xargs)"
    
    # Detect if running in container/VM
    DETECTED[virtualization]="bare-metal"
    if [ -f /.dockerenv ]; then
        DETECTED[virtualization]="docker"
    elif [ -d /proc/vz ]; then
        DETECTED[virtualization]="openvz"
    elif grep -q "QEMU\|VMware\|VirtualBox" /proc/cpuinfo 2>/dev/null; then
        DETECTED[virtualization]="vm"
    elif [ -f /proc/xen/version ] 2>/dev/null; then
        DETECTED[virtualization]="xen"
    fi
    
    # Detect Proxmox if present
    if [ -f /etc/pve/local/pve-ssl.pem ]; then
        DETECTED[proxmox_version]=$(pveversion 2>/dev/null | cut -d'/' -f2 || echo "unknown")
    else
        DETECTED[proxmox_version]=""
    fi
    
    success "System detection completed"
}

# Display detected configuration
show_detected_config() {
    highlight "╔═══ DETECTED SYSTEM CONFIGURATION ═══╗"
    echo
    
    echo -e "${CYAN}System Information:${NC}"
    echo "  • CPU Cores: ${DETECTED[cpu_cores]}"
    echo "  • Memory: ${DETECTED[memory_mb]} MB"
    echo "  • Available Disk Space: ${DETECTED[disk_space_gb]} GB"
    echo "  • Virtualization: ${DETECTED[virtualization]}"
    if [ -n "${DETECTED[proxmox_version]}" ]; then
        echo "  • Proxmox Version: ${DETECTED[proxmox_version]}"
    fi
    echo
    
    echo -e "${CYAN}Network Configuration:${NC}"
    echo "  • Network Interfaces: $(echo ${DETECTED[network_interfaces]} | wc -w)"
    echo "  • Network Namespaces: ${DETECTED[netns_count]}"
    if [ -n "${DETECTED[container_runtime]}" ]; then
        echo "  • Container Runtime: ${DETECTED[container_runtime]}"
    fi
    echo
    
    echo -e "${CYAN}OpenVSwitch Status:${NC}"
    if [ -n "${DETECTED[existing_bridges]}" ]; then
        echo "  • Existing OVS Bridges:"
        for bridge in ${DETECTED[existing_bridges]}; do
            local ports=$(ovs-vsctl list-ports "$bridge" 2>/dev/null | wc -l)
            echo "    - $bridge ($ports ports)"
        done
    else
        echo "  • No existing OVS bridges found"
    fi
    echo
    
    echo -e "${CYAN}Netmaker Status:${NC}"
    if [ -n "${DETECTED[netmaker_services]}" ]; then
        echo "  • Detected Services: ${DETECTED[netmaker_services]}"
    else
        echo "  • No Netmaker services detected"
    fi
    
    if [ -n "${DETECTED[netmaker_interfaces]}" ]; then
        echo "  • Active Interfaces:"
        for iface in ${DETECTED[netmaker_interfaces]}; do
            local status=$(ip link show "$iface" 2>/dev/null | grep -o 'state [A-Z]*' | cut -d' ' -f2 || echo "UNKNOWN")
            echo "    - $iface ($status)"
        done
    else
        echo "  • No active Netmaker interfaces found"
    fi
    echo
    
    if [ -n "${DETECTED[used_vlans]}" ]; then
        warning "VLANs currently in use: ${DETECTED[used_vlans]}"
        echo
    fi
    
    echo -e "${PURPLE}════════════════════════════════════════${NC}"
    echo
}

# Get bridge configuration
configure_bridge() {
    highlight "╔═══ BRIDGE CONFIGURATION ═══╗"
    echo
    
    # Suggest bridge name based on existing bridges
    local suggested_bridge="ovsbr0"
    if [ -n "${DETECTED[existing_bridges]}" ]; then
        local bridge_count=$(echo ${DETECTED[existing_bridges]} | wc -w)
        if echo "${DETECTED[existing_bridges]}" | grep -q "ovsbr0"; then
            suggested_bridge="ovsbr$((bridge_count))"
        fi
    fi
    
    while true; do
        prompt "OVS Bridge Configuration:"
        echo "  Current OVS bridges: ${DETECTED[existing_bridges]:-none}"
        echo "  Suggested name: $suggested_bridge"
        echo
        
        read -p "Enter bridge name [$suggested_bridge]: " bridge_input
        CONFIG[bridge_name]="${bridge_input:-$suggested_bridge}"
        
        # Validate bridge name
        if [[ ! "${CONFIG[bridge_name]}" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
            error "Invalid bridge name. Use letters, numbers, underscore, and dash only."
            continue
        fi
        
        # Check if bridge already exists
        if echo "${DETECTED[existing_bridges]}" | grep -q "^${CONFIG[bridge_name]}$"; then
            warning "Bridge '${CONFIG[bridge_name]}' already exists."
            
            local choice
            prompt "Do you want to:"
            echo "  1) Use existing bridge"
            echo "  2) Choose different name"
            read -p "Enter choice (1-2): " choice
            
            case $choice in
                1)
                    info "Will use existing bridge: ${CONFIG[bridge_name]}"
                    break
                    ;;
                2)
                    continue
                    ;;
                *)
                    warning "Invalid choice. Please try again."
                    continue
                    ;;
            esac
        else
            info "Will create new bridge: ${CONFIG[bridge_name]}"
            break
        fi
    done
    
    CONFIG[create_bridge]="true"
    if echo "${DETECTED[existing_bridges]}" | grep -q "^${CONFIG[bridge_name]}$"; then
        CONFIG[create_bridge]="false"
    fi
    
    echo
}

# Configure Netmaker interface detection
configure_netmaker_interfaces() {
    highlight "╔═══ NETMAKER INTERFACE CONFIGURATION ═══╗"
    echo
    
    # Analyze existing interfaces for pattern suggestion
    local suggested_pattern="nm-*"
    if [ -n "${DETECTED[netmaker_interfaces]}" ]; then
        # Try to detect pattern from existing interfaces
        local first_interface=$(echo ${DETECTED[netmaker_interfaces]} | awk '{print $1}')
        if [[ "$first_interface" =~ ^netmaker- ]]; then
            suggested_pattern="netmaker-*"
        elif [[ "$first_interface" =~ ^wg- ]]; then
            suggested_pattern="wg-*"
        fi
    fi
    
    prompt "Netmaker Interface Pattern:"
    if [ -n "${DETECTED[netmaker_interfaces]}" ]; then
        echo "  Currently detected interfaces:"
        for iface in ${DETECTED[netmaker_interfaces]}; do
            echo "    - $iface"
        done
        echo "  Suggested pattern: $suggested_pattern"
    else
        echo "  No Netmaker interfaces currently active"
        echo "  Default pattern: $suggested_pattern"
    fi
    echo
    
    read -p "Enter interface pattern [$suggested_pattern]: " pattern_input
    CONFIG[interface_pattern]="${pattern_input:-$suggested_pattern}"
    
    info "Will detect interfaces matching: ${CONFIG[interface_pattern]}"
    echo
}

# Configure obfuscation settings
configure_obfuscation() {
    highlight "╔═══ OBFUSCATION CONFIGURATION ═══╗"
    echo
    
    prompt "Obfuscation provides privacy protection with minimal performance impact (~15% overhead)."
    echo
    
    # Check system resources for recommendations
    local memory_mb=${DETECTED[memory_mb]}
    local cpu_cores=${DETECTED[cpu_cores]}
    
    local recommended_level="balanced"
    if [ "$memory_mb" -lt 1024 ] || [ "$cpu_cores" -lt 2 ]; then
        recommended_level="conservative"
        warning "Limited resources detected. Conservative settings recommended."
    elif [ "$memory_mb" -gt 4096 ] && [ "$cpu_cores" -gt 4 ]; then
        recommended_level="aggressive"
        info "Ample resources detected. Aggressive settings available."
    fi
    
    while true; do
        prompt "Select obfuscation level:"
        echo "  1) Disabled - No obfuscation (0% overhead)"
        echo "  2) Conservative - Minimal impact (5% overhead, 20% protection)"
        echo "  3) Balanced - Good protection (15% overhead, 30% protection) [DEFAULT]"
        echo "  4) Aggressive - Maximum protection (25% overhead, 40% protection)"
        echo "  5) Custom - Configure manually"
        echo
        echo "  Recommended for your system: $recommended_level"
        echo
        
        read -p "Enter choice (1-5) [3]: " obfs_choice
        obfs_choice=${obfs_choice:-3}
        
        case $obfs_choice in
            1)
                CONFIG[enable_obfuscation]="false"
                info "Obfuscation disabled"
                break
                ;;
            2)
                CONFIG[enable_obfuscation]="true"
                CONFIG[vlan_obfuscation]="true"
                CONFIG[vlan_rotation_interval]="600"
                CONFIG[mac_randomization]="false"
                CONFIG[timing_obfuscation]="false"
                CONFIG[traffic_shaping]="false"
                CONFIG[shaping_rate_mbps]="200"
                CONFIG[max_delay_ms]="25"
                info "Conservative obfuscation configured"
                break
                ;;
            3)
                CONFIG[enable_obfuscation]="true"
                CONFIG[vlan_obfuscation]="true"
                CONFIG[vlan_rotation_interval]="300"
                CONFIG[mac_randomization]="true"
                CONFIG[mac_rotation_interval]="1800"
                CONFIG[timing_obfuscation]="true"
                CONFIG[traffic_shaping]="true"
                CONFIG[shaping_rate_mbps]="100"
                CONFIG[max_delay_ms]="50"
                info "Balanced obfuscation configured"
                break
                ;;
            4)
                CONFIG[enable_obfuscation]="true"
                CONFIG[vlan_obfuscation]="true"
                CONFIG[vlan_rotation_interval]="120"
                CONFIG[mac_randomization]="true"
                CONFIG[mac_rotation_interval]="900"
                CONFIG[timing_obfuscation]="true"
                CONFIG[traffic_shaping]="true"
                CONFIG[shaping_rate_mbps]="50"
                CONFIG[max_delay_ms]="100"
                info "Aggressive obfuscation configured"
                break
                ;;
            5)
                configure_custom_obfuscation
                break
                ;;
            *)
                warning "Invalid choice. Please enter 1-5."
                ;;
        esac
    done
    
    if [ "${CONFIG[enable_obfuscation]}" = "true" ]; then
        configure_vlan_pool
    fi
    
    echo
}

# Configure custom obfuscation
configure_custom_obfuscation() {
    CONFIG[enable_obfuscation]="true"
    
    echo
    highlight "Custom Obfuscation Configuration:"
    echo
    
    # VLAN obfuscation
    local vlan_choice
    prompt "Enable VLAN rotation? (Disrupts traffic flow analysis)"
    read -p "Enable VLAN obfuscation? (y/N): " vlan_choice
    if [[ $vlan_choice =~ ^[Yy] ]]; then
        CONFIG[vlan_obfuscation]="true"
        read -p "VLAN rotation interval in seconds [300]: " vlan_interval
        CONFIG[vlan_rotation_interval]="${vlan_interval:-300}"
    else
        CONFIG[vlan_obfuscation]="false"
    fi
    
    # MAC randomization
    local mac_choice
    prompt "Enable MAC address randomization? (Prevents device fingerprinting)"
    read -p "Enable MAC randomization? (y/N): " mac_choice
    if [[ $mac_choice =~ ^[Yy] ]]; then
        CONFIG[mac_randomization]="true"
        read -p "MAC rotation interval in seconds [1800]: " mac_interval
        CONFIG[mac_rotation_interval]="${mac_interval:-1800}"
    else
        CONFIG[mac_randomization]="false"
    fi
    
    # Timing obfuscation
    local timing_choice
    prompt "Enable timing obfuscation? (Disrupts timing correlation attacks)"
    read -p "Enable timing obfuscation? (y/N): " timing_choice
    if [[ $timing_choice =~ ^[Yy] ]]; then
        CONFIG[timing_obfuscation]="true"
        read -p "Maximum delay in milliseconds [50]: " max_delay
        CONFIG[max_delay_ms]="${max_delay:-50}"
    else
        CONFIG[timing_obfuscation]="false"
    fi
    
    # Traffic shaping
    local shaping_choice
    prompt "Enable traffic shaping? (Normalizes traffic patterns)"
    read -p "Enable traffic shaping? (y/N): " shaping_choice
    if [[ $shaping_choice =~ ^[Yy] ]]; then
        CONFIG[traffic_shaping]="true"
        read -p "Traffic shaping rate in Mbps [100]: " shaping_rate
        CONFIG[shaping_rate_mbps]="${shaping_rate:-100}"
    else
        CONFIG[traffic_shaping]="false"
    fi
}

# Configure VLAN pool
configure_vlan_pool() {
    echo
    prompt "VLAN Pool Configuration:"
    
    # Suggest VLANs not currently in use
    local available_vlans=""
    local default_vlans="100 200 300 400 500"
    
    for vlan in $default_vlans; do
        if ! echo "${DETECTED[used_vlans]}" | grep -q "$vlan"; then
            available_vlans="$available_vlans $vlan"
        fi
    done
    
    available_vlans=$(echo $available_vlans | xargs)
    
    if [ -n "${DETECTED[used_vlans]}" ]; then
        warning "VLANs currently in use: ${DETECTED[used_vlans]}"
    fi
    
    echo "  Available VLANs: $available_vlans"
    echo "  Default pool: 100,200,300,400,500"
    echo
    
    read -p "Enter VLAN pool (comma-separated) [$available_vlans]: " vlan_input
    local vlan_pool="${vlan_input:-$available_vlans}"
    
    # Convert spaces to commas if needed
    vlan_pool=$(echo "$vlan_pool" | tr ' ' ',')
    CONFIG[vlan_pool]="$vlan_pool"
    
    info "VLAN pool configured: ${CONFIG[vlan_pool]}"
}

# Show configuration summary
show_configuration_summary() {
    clear
    highlight "╔═══════════════════════════════════════════════════════════════╗"
    highlight "║                    CONFIGURATION SUMMARY                     ║"
    highlight "╚═══════════════════════════════════════════════════════════════╝"
    echo
    
    echo -e "${CYAN}Bridge Configuration:${NC}"
    echo "  • Bridge Name: ${CONFIG[bridge_name]}"
    echo "  • Create Bridge: ${CONFIG[create_bridge]}"
    echo
    
    echo -e "${CYAN}Netmaker Configuration:${NC}"
    echo "  • Interface Pattern: ${CONFIG[interface_pattern]}"
    echo
    
    echo -e "${CYAN}Obfuscation Configuration:${NC}"
    echo "  • Enabled: ${CONFIG[enable_obfuscation]}"
    
    if [ "${CONFIG[enable_obfuscation]}" = "true" ]; then
        echo "  • VLAN Rotation: ${CONFIG[vlan_obfuscation]} (every ${CONFIG[vlan_rotation_interval]:-N/A}s)"
        echo "  • MAC Randomization: ${CONFIG[mac_randomization]} (every ${CONFIG[mac_rotation_interval]:-N/A}s)"
        echo "  • Timing Obfuscation: ${CONFIG[timing_obfuscation]} (max ${CONFIG[max_delay_ms]:-N/A}ms)"
        echo "  • Traffic Shaping: ${CONFIG[traffic_shaping]} (${CONFIG[shaping_rate_mbps]:-N/A} Mbps)"
        if [ -n "${CONFIG[vlan_pool]}" ]; then
            echo "  • VLAN Pool: ${CONFIG[vlan_pool]}"
        fi
    fi
    echo
    
    echo -e "${CYAN}Installation Details:${NC}"
    echo "  • Target System: ${DETECTED[virtualization]}"
    if [ -n "${DETECTED[proxmox_version]}" ]; then
        echo "  • Proxmox Version: ${DETECTED[proxmox_version]}"
    fi
    echo "  • Available Resources: ${DETECTED[cpu_cores]} cores, ${DETECTED[memory_mb]} MB RAM"
    echo
    
    # Estimate performance impact
    local overhead="0%"
    if [ "${CONFIG[enable_obfuscation]}" = "true" ]; then
        local impact_score=0
        [ "${CONFIG[vlan_obfuscation]}" = "true" ] && impact_score=$((impact_score + 3))
        [ "${CONFIG[mac_randomization]}" = "true" ] && impact_score=$((impact_score + 2))
        [ "${CONFIG[timing_obfuscation]}" = "true" ] && impact_score=$((impact_score + 5))
        [ "${CONFIG[traffic_shaping]}" = "true" ] && impact_score=$((impact_score + 3))
        
        if [ $impact_score -le 3 ]; then
            overhead="~5%"
        elif [ $impact_score -le 8 ]; then
            overhead="~15%"
        else
            overhead="~25%"
        fi
    fi
    
    echo -e "${CYAN}Estimated Performance Impact: ${overhead}${NC}"
    echo
}

# Confirm installation
confirm_installation() {
    highlight "═══════════════════════════════════════"
    echo
    
    while true; do
        prompt "Ready to proceed with installation?"
        echo "  1) Install with current configuration"
        echo "  2) Modify configuration"
        echo "  3) Save configuration and exit"
        echo "  4) Exit without installing"
        echo
        
        read -p "Enter choice (1-4): " choice
        
        case $choice in
            1)
                return 0
                ;;
            2)
                return 1
                ;;
            3)
                save_configuration
                exit 0
                ;;
            4)
                info "Installation cancelled by user."
                exit 0
                ;;
            *)
                warning "Invalid choice. Please enter 1-4."
                ;;
        esac
    done
}

# Save configuration to file
save_configuration() {
    local config_file="netmaker-ovs-config-$(date +%Y%m%d-%H%M%S).conf"
    
    {
        echo "# Netmaker OVS Integration Configuration"
        echo "# Generated on $(date)"
        echo "# System: ${DETECTED[virtualization]}"
        echo ""
        echo "# Bridge Configuration"
        echo "BRIDGE_NAME=${CONFIG[bridge_name]}"
        echo ""
        echo "# Interface Configuration"
        echo "NM_INTERFACE_PATTERN=\"${CONFIG[interface_pattern]}\""
        echo ""
        echo "# Obfuscation Settings"
        echo "ENABLE_OBFUSCATION=${CONFIG[enable_obfuscation]}"
        
        if [ "${CONFIG[enable_obfuscation]}" = "true" ]; then
            echo ""
            echo "# VLAN obfuscation"
            echo "VLAN_OBFUSCATION=${CONFIG[vlan_obfuscation]}"
            if [ "${CONFIG[vlan_obfuscation]}" = "true" ]; then
                echo "VLAN_POOL=\"${CONFIG[vlan_pool]}\""
                echo "VLAN_ROTATION_INTERVAL=${CONFIG[vlan_rotation_interval]}"
            fi
            echo ""
            echo "# MAC address randomization"
            echo "MAC_RANDOMIZATION=${CONFIG[mac_randomization]}"
            if [ "${CONFIG[mac_randomization]}" = "true" ]; then
                echo "MAC_ROTATION_INTERVAL=${CONFIG[mac_rotation_interval]}"
            fi
            echo ""
            echo "# Timing obfuscation"
            echo "TIMING_OBFUSCATION=${CONFIG[timing_obfuscation]}"
            if [ "${CONFIG[timing_obfuscation]}" = "true" ]; then
                echo "MAX_DELAY_MS=${CONFIG[max_delay_ms]}"
            fi
            echo ""
            echo "# Traffic shaping"
            echo "TRAFFIC_SHAPING=${CONFIG[traffic_shaping]}"
            if [ "${CONFIG[traffic_shaping]}" = "true" ]; then
                echo "SHAPING_RATE_MBPS=${CONFIG[shaping_rate_mbps]}"
            fi
        fi
        
    } > "$config_file"
    
    success "Configuration saved to: $config_file"
    echo "You can use this file for future installations or reference."
}

# Generate dynamic configuration file
generate_config_file() {
    local config_dir="config"
    local config_file="$config_dir/ovs-config"
    
    # Backup original if it exists
    if [ -f "$config_file" ]; then
        cp "$config_file" "$config_file.backup-$(date +%Y%m%d-%H%M%S)"
    fi
    
    {
        echo "# OpenVSwitch bridge name"
        echo "# This is the bridge your Netmaker interface will be added to."
        echo "# Ensure this bridge exists or will be created by the install script."
        echo "BRIDGE_NAME=${CONFIG[bridge_name]}"
        echo ""
        echo "# Netmaker interface pattern"
        echo "# This pattern is used to identify the Netmaker network interface."
        echo "# Typically, Netmaker interfaces are named like 'nm-...' or 'netmaker-...'."
        echo "# Adjust if your Netmaker interface names follow a different pattern."
        echo "NM_INTERFACE_PATTERN=\"${CONFIG[interface_pattern]}\""
        echo ""
        echo "# Obfuscation Settings"
        echo "# Enable mild obfuscation for privacy protection (minimal performance impact)"
        echo "ENABLE_OBFUSCATION=${CONFIG[enable_obfuscation]}"
        
        if [ "${CONFIG[enable_obfuscation]}" = "true" ]; then
            echo ""
            echo "# VLAN obfuscation - randomly rotate VLAN tags"
            echo "VLAN_OBFUSCATION=${CONFIG[vlan_obfuscation]}"
            if [ "${CONFIG[vlan_obfuscation]}" = "true" ]; then
                echo "VLAN_POOL=\"${CONFIG[vlan_pool]}\"  # Available VLAN tags for rotation"
                echo "VLAN_ROTATION_INTERVAL=${CONFIG[vlan_rotation_interval]}        # Seconds between VLAN rotations"
            fi
            echo ""
            echo "# MAC address randomization"
            echo "MAC_RANDOMIZATION=${CONFIG[mac_randomization]}"
            if [ "${CONFIG[mac_randomization]}" = "true" ]; then
                echo "MAC_ROTATION_INTERVAL=${CONFIG[mac_rotation_interval]}        # Seconds between MAC changes"
            fi
            echo ""
            echo "# Basic timing obfuscation"
            echo "TIMING_OBFUSCATION=${CONFIG[timing_obfuscation]}"
            if [ "${CONFIG[timing_obfuscation]}" = "true" ]; then
                echo "MAX_DELAY_MS=${CONFIG[max_delay_ms]}                   # Maximum delay in milliseconds"
            fi
            echo ""
            echo "# Traffic pattern obfuscation"
            echo "TRAFFIC_SHAPING=${CONFIG[traffic_shaping]}"
            if [ "${CONFIG[traffic_shaping]}" = "true" ]; then
                echo "SHAPING_RATE_MBPS=${CONFIG[shaping_rate_mbps]}             # Rate limit for traffic shaping"
            fi
        fi
        
    } > "$config_file"
    
    info "Configuration file generated: $config_file"
}

# Run original installation with generated config
run_installation() {
    info "Starting installation with interactive configuration..."
    
    # Generate the configuration file
    generate_config_file
    
    # Run the original install script
    if [ -f "./install.sh" ]; then
        log "Executing install.sh with generated configuration"
        ./install.sh
    else
        error "install.sh not found in current directory"
        exit 1
    fi
}

# Main interactive configuration flow
interactive_configuration() {
    while true; do
        configure_bridge
        configure_netmaker_interfaces
        configure_obfuscation
        
        show_configuration_summary
        
        if confirm_installation; then
            break
        fi
        
        # If user wants to modify, continue loop
        clear
        show_detected_config
    done
}

# Main execution function
main() {
    show_banner
    log "Starting interactive installer v$SCRIPT_VERSION"
    
    check_root
    check_preinstall
    
    detect_system_config
    show_detected_config
    
    prompt "Press Enter to continue with interactive configuration..."
    read
    
    interactive_configuration
    
    clear
    highlight "╔═══════════════════════════════════════════════════════════════╗"
    highlight "║                      STARTING INSTALLATION                   ║"
    highlight "╚═══════════════════════════════════════════════════════════════╝"
    echo
    
    run_installation
    
    echo
    success "Interactive installation completed!"
    info "Configuration saved to: config/ovs-config"
    info "Installation log: $INTERACTIVE_LOG"
    
    echo
    highlight "Next steps:"
    echo "• Check service status: systemctl status netmaker-ovs-bridge"
    if [ "${CONFIG[enable_obfuscation]}" = "true" ]; then
        echo "• Check obfuscation: systemctl status netmaker-obfuscation-daemon"
    fi
    echo "• View logs: journalctl -u netmaker-ovs-bridge"
    echo "• Test Netmaker connectivity with your configured settings"
    echo
}

# Execute main function
main "$@"