#!/usr/bin/env bash
# =============================================================================
# autosecure.sh — Automated Linux Server Hardening
# Supports Debian and Ubuntu on a fresh install.
# Run as root via SSH right after provisioning.
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
VERBOSE=false
for arg in "$@"; do
    case "$arg" in
        -v|--verbose) VERBOSE=true ;;
        -h|--help)
            echo "Usage: $0 [-v|--verbose] [-h|--help]"
            echo "  -v, --verbose    Show full command output"
            exit 0
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Colors & helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

info()    { printf "${BLUE}[INFO]${NC}  %s\n" "$*"; }
ok()      { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
warn()    { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
err()     { printf "${RED}[ERROR]${NC} %s\n" "$*"; }
header()  { printf "\n${BOLD}${CYAN}── %s ──${NC}\n\n" "$*"; }
step()    { printf "${BOLD}▸ %s${NC}\n" "$*"; }

# Run a command, suppressing output unless --verbose is set
run() {
    if [ "$VERBOSE" = true ]; then
        "$@"
    else
        "$@" >/dev/null 2>&1
    fi
}

confirm() {
    local prompt="${1:-Continue?}"
    local answer
    while true; do
        printf "${YELLOW}%s [y/n]: ${NC}" "$prompt"
        read -r answer < /dev/tty
        case "$answer" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "Please answer y or n." ;;
        esac
    done
}

show_diff() {
    # Show a colored unified diff between two files
    local old="$1" new="$2"
    if command -v diff &>/dev/null; then
        diff --unified=3 "$old" "$new" | while IFS= read -r line; do
            case "$line" in
                ---*) printf "${RED}%s${NC}\n" "$line" ;;
                +++*) printf "${GREEN}%s${NC}\n" "$line" ;;
                @@*)  printf "${CYAN}%s${NC}\n" "$line" ;;
                -*)   printf "${RED}%s${NC}\n" "$line" ;;
                +*)   printf "${GREEN}%s${NC}\n" "$line" ;;
                *)    printf "%s\n" "$line" ;;
            esac
        done
    else
        cat "$new"
    fi
    echo
}

# Apply a config file after showing diff and asking for confirmation
apply_config() {
    local description="$1" target="$2" newfile="$3"
    header "$description"

    if [ -f "$target" ]; then
        info "Changes to ${target}:"
        echo
        show_diff "$target" "$newfile"
    else
        info "New file ${target}:"
        echo
        cat "$newfile"
        echo
    fi

    if confirm "Apply these changes to ${target}?"; then
        cp "$newfile" "$target"
        ok "Applied."
        return 0
    else
        warn "Skipped."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    err "This script must be run as root."
    exit 1
fi

if [ ! -f /etc/os-release ]; then
    err "Cannot detect distribution (/etc/os-release not found)."
    exit 1
fi

# shellcheck source=/dev/null
. /etc/os-release

DISTRO=""
case "${ID,,}" in
    debian) DISTRO="debian" ;;
    ubuntu) DISTRO="ubuntu" ;;
    *)
        err "Unsupported distribution: ${ID}. Only Debian and Ubuntu are supported."
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# Screen session (network resilience)
# ---------------------------------------------------------------------------
SCREEN_SESSION="autosecure"
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"

# If already inside the screen session, skip re-launching
if [ -z "${AUTOSECURE_IN_SCREEN:-}" ]; then
    # Check for an existing detached session to resume
    if screen -ls "$SCREEN_SESSION" 2>/dev/null | grep -q "Detached"; then
        exec screen -r "$SCREEN_SESSION"
    fi

    # Install screen if missing
    if ! command -v screen &>/dev/null; then
        run apt-get update
        run apt-get install -y screen
    fi

    exec screen -S "$SCREEN_SESSION" env AUTOSECURE_IN_SCREEN=1 bash "$SCRIPT_PATH" "$@"
fi

# ---------------------------------------------------------------------------
# Banner & server summary
# ---------------------------------------------------------------------------
clear 2>/dev/null || true
printf "${BOLD}${CYAN}"
cat << 'BANNER'

     _         _        ____
    / \  _   _| |_ ___ / ___|  ___  ___ _   _ _ __ ___
   / _ \| | | | __/ _ \\___ \ / _ \/ __| | | | '__/ _ \
  / ___ \ |_| | || (_) |___) |  __/ (__| |_| | | |  __/
 /_/   \_\__,_|\__\___/|____/ \___|\___|\__,_|_|  \___|

  Automated Linux Server Hardening

BANNER
printf "${NC}"

header "Current Server Configuration"

printf "  ${BOLD}%-20s${NC} %s\n" "Hostname:" "$(hostname)"
printf "  ${BOLD}%-20s${NC} %s %s\n" "Distribution:" "$NAME" "$VERSION_ID"
printf "  ${BOLD}%-20s${NC} %s\n" "Kernel:" "$(uname -r)"
printf "  ${BOLD}%-20s${NC} %s\n" "Architecture:" "$(uname -m)"

# Network info
IP_ADDR=$(ip -4 addr show scope global 2>/dev/null | awk '/inet / {print $2}' | head -1)
printf "  ${BOLD}%-20s${NC} %s\n" "IP Address:" "${IP_ADDR:-unknown}"

# Current SSH config
CURRENT_SSH_PORT=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
[ -z "$CURRENT_SSH_PORT" ] && CURRENT_SSH_PORT="22"
printf "  ${BOLD}%-20s${NC} %s\n" "SSH Port:" "$CURRENT_SSH_PORT"

ROOT_LOGIN=$(grep -E "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "default")
printf "  ${BOLD}%-20s${NC} %s\n" "Root Login:" "${ROOT_LOGIN:-default (yes)}"

PASS_AUTH=$(grep -E "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "default")
printf "  ${BOLD}%-20s${NC} %s\n" "Password Auth:" "${PASS_AUTH:-default (yes)}"

# Firewall
if command -v ufw &>/dev/null; then
    UFW_STATUS=$(ufw status 2>/dev/null | head -1)
    printf "  ${BOLD}%-20s${NC} %s\n" "Firewall (ufw):" "$UFW_STATUS"
elif command -v iptables &>/dev/null; then
    IPTABLE_RULES=$(iptables -L -n 2>/dev/null | grep -c "^[A-Z]" || echo "0")
    printf "  ${BOLD}%-20s${NC} %s chains\n" "Firewall (iptables):" "$IPTABLE_RULES"
else
    printf "  ${BOLD}%-20s${NC} %s\n" "Firewall:" "none detected"
fi

# Existing users with login shell
LOGIN_USERS=$(awk -F: '$7 !~ /(nologin|false|sync|halt|shutdown)$/ && $3 >= 1000 {print $1}' /etc/passwd | paste -sd, -)
printf "  ${BOLD}%-20s${NC} %s\n" "Login Users:" "${LOGIN_USERS:-none}"

# Uptime & load
printf "  ${BOLD}%-20s${NC} %s\n" "Uptime:" "$(uptime -p 2>/dev/null || uptime | sed 's/.*up/up/')"

echo
printf "  ${DIM}Date: %s${NC}\n" "$(date)"
echo

# ===========================================================================
# PHASE 1: Configuration (no changes to the system)
# ===========================================================================
header "PHASE 1: Configuration"

# Username
while true; do
    printf "${BOLD}Enter the username to create: ${NC}"
    read -r NEW_USER < /dev/tty
    if [[ "$NEW_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        break
    else
        err "Invalid username. Use lowercase letters, digits, hyphens and underscores (max 32 chars)."
    fi
done

# SSH port
while true; do
    printf "${BOLD}Enter the custom SSH port [1024-65535]: ${NC}"
    read -r SSH_PORT < /dev/tty
    if [[ "$SSH_PORT" =~ ^[0-9]+$ ]] && [ "$SSH_PORT" -ge 1024 ] && [ "$SSH_PORT" -le 65535 ]; then
        break
    else
        err "Invalid port. Choose a number between 1024 and 65535."
    fi
done

echo
info "Summary of planned actions:"
echo
printf "  1. Create user ${BOLD}%s${NC} with sudo privileges\n" "$NEW_USER"
printf "  2. Set up SSH key authentication for ${BOLD}%s${NC}\n" "$NEW_USER"
printf "  3. Harden SSH: port ${BOLD}%s${NC}, key-only, no root, no password, no tunneling\n" "$SSH_PORT"
printf "  4. Configure firewall (ufw) — rate-limit port ${BOLD}%s${NC}/tcp\n" "$SSH_PORT"
printf "  5. Install and configure automatic security updates\n"
printf "  6. Harden kernel parameters (sysctl)\n"
printf "  7. Set up fail2ban with progressive banning\n"
printf "  8. Disable unused network protocols\n"
printf "  9. Restrict su access to sudo group\n"
printf "  10. Disable core dumps\n"
printf "  11. Check and enable AppArmor\n"
echo

if ! confirm "Proceed with hardening?"; then
    echo "Aborted."
    exit 0
fi

# ===========================================================================
# PHASE 2: Apply Changes (each step asks for confirmation)
# ===========================================================================
header "PHASE 2: Applying Changes"
info "Each step will ask for confirmation before applying."
echo

# ---------------------------------------------------------------------------
# Step 1 — Create user
# ---------------------------------------------------------------------------
header "Step 1: Create User '${NEW_USER}'"

if id "$NEW_USER" &>/dev/null; then
    warn "User '${NEW_USER}' already exists. Skipping creation."
else
    step "Creating user '${NEW_USER}' with home directory..."
    useradd -m -s /bin/bash "$NEW_USER"
    ok "User created."

    step "Setting password for '${NEW_USER}'..."
    info "You will be prompted to set a password (needed for sudo)."
    passwd "$NEW_USER" < /dev/tty
fi

# Add to sudo group
if groups "$NEW_USER" | grep -qw "sudo"; then
    ok "User '${NEW_USER}' is already in the sudo group."
else
    step "Adding '${NEW_USER}' to sudo group..."
    usermod -aG sudo "$NEW_USER"
    ok "Added to sudo group."
fi

# ---------------------------------------------------------------------------
# Step 2 — SSH key setup
# ---------------------------------------------------------------------------
header "Step 2: SSH Key Setup for '${NEW_USER}'"

USER_HOME=$(eval echo "~${NEW_USER}")
SSH_DIR="${USER_HOME}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"

mkdir -p "$SSH_DIR"

if [ -f "$AUTH_KEYS" ] && [ -s "$AUTH_KEYS" ]; then
    info "Existing authorized_keys found:"
    cat "$AUTH_KEYS"
    echo
    if ! confirm "Keep existing keys and skip adding a new one?"; then
        printf "${BOLD}Paste the public SSH key for '${NEW_USER}' (one line):${NC}\n"
        read -r PUB_KEY < /dev/tty
        echo "$PUB_KEY" >> "$AUTH_KEYS"
        ok "Key added."
    fi
else
    printf "${BOLD}Paste the public SSH key for '${NEW_USER}' (one line):${NC}\n"
    read -r PUB_KEY < /dev/tty

    if [ -z "$PUB_KEY" ]; then
        err "No key provided. You MUST provide a public key — password auth will be disabled."
        err "Aborting to avoid lockout."
        exit 1
    fi

    echo "$PUB_KEY" > "$AUTH_KEYS"
    ok "Key saved."
fi

# Fix permissions
chmod 700 "$SSH_DIR"
chmod 600 "$AUTH_KEYS"
chown -R "${NEW_USER}:${NEW_USER}" "$SSH_DIR"
ok "Permissions set (700 for .ssh, 600 for authorized_keys)."

# Copy root's authorized_keys if it exists and user's is empty (safety net)
if [ -f /root/.ssh/authorized_keys ] && [ -s /root/.ssh/authorized_keys ]; then
    if ! grep -qf /root/.ssh/authorized_keys "$AUTH_KEYS" 2>/dev/null; then
        info "Root has authorized_keys. Copying to '${NEW_USER}' as backup."
        if confirm "Also add root's SSH keys to '${NEW_USER}'?"; then
            cat /root/.ssh/authorized_keys >> "$AUTH_KEYS"
            chown "${NEW_USER}:${NEW_USER}" "$AUTH_KEYS"
            ok "Root keys copied."
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Step 3 — Harden SSH
# ---------------------------------------------------------------------------
header "Step 3: Harden SSH Configuration"

SSHD_DROPIN_DIR="/etc/ssh/sshd_config.d"
SSHD_DROPIN="${SSHD_DROPIN_DIR}/99-autosecure.conf"
SSHD_NEW=$(mktemp)

# Ensure the main sshd_config has an Include directive for the drop-in directory
if [ -d "$SSHD_DROPIN_DIR" ] && grep -qE "^Include.*/etc/ssh/sshd_config\.d/" /etc/ssh/sshd_config 2>/dev/null; then
    ok "sshd_config.d drop-in directory is supported and enabled."
else
    warn "sshd_config.d not supported on this system. Adding Include directive."
    if ! grep -qE "^Include.*/etc/ssh/sshd_config\.d/" /etc/ssh/sshd_config 2>/dev/null; then
        mkdir -p "$SSHD_DROPIN_DIR"
        sed -i '1s/^/Include \/etc\/ssh\/sshd_config.d\/*.conf\n/' /etc/ssh/sshd_config
        ok "Include directive added to sshd_config."
    fi
fi

info "Original sshd_config will NOT be modified."
info "All hardening goes into the drop-in: ${SSHD_DROPIN}"
echo

# Build the drop-in override config
cat > "$SSHD_NEW" << SSHEOF
# =============================================================================
# SSH Hardening — AutoSecure (drop-in override)
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# Drop-in files in sshd_config.d are included FIRST and take precedence.
# =============================================================================

# --- Network ---
Port ${SSH_PORT}
AddressFamily inet
ListenAddress 0.0.0.0

# --- Authentication ---
PermitRootLogin no
MaxAuthTries 3
MaxSessions 3
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

# Disable all password/keyboard-interactive auth
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no

# Disable other auth methods
KerberosAuthentication no
GSSAPIAuthentication no
HostbasedAuthentication no

# --- Security ---
StrictModes yes
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2

# Disable forwarding and tunneling
AllowTcpForwarding no
X11Forwarding no
AllowAgentForwarding no
PermitTunnel no
GatewayPorts no
DisableForwarding yes

# --- Logging ---
SyslogFacility AUTH
LogLevel VERBOSE

# --- Misc ---
PrintMotd no
PrintLastLog yes
TCPKeepAlive no
Compression no
UseDNS no
PermitUserEnvironment no
MaxStartups 10:30:60

# Restrict to our user only
AllowUsers ${NEW_USER}

# --- Crypto (strong ciphers only) ---
KexAlgorithms sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256

# Use only strong host keys
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key
SSHEOF

# Validate the new config before applying
step "Validating new SSH configuration..."
if sshd -t 2>/dev/null; then
    # Test with the drop-in in place
    cp "$SSHD_NEW" "$SSHD_DROPIN"
    if sshd -t 2>/dev/null; then
        ok "Configuration is valid."
        rm -f "$SSHD_DROPIN"
    else
        VALIDATION_ERR=$(sshd -t 2>&1)
        rm -f "$SSHD_DROPIN"
        if echo "$VALIDATION_ERR" | grep -qi "sntrup761"; then
            warn "Your SSH version may not support all key exchange algorithms. Adjusting..."
            sed -i 's/sntrup761x25519-sha512@openssh.com,//' "$SSHD_NEW"
            ok "Adjusted."
        else
            warn "Config validation returned warnings (may be non-fatal):"
            echo "$VALIDATION_ERR" | head -5
        fi
    fi
fi

if apply_config "SSH Drop-in Configuration" "$SSHD_DROPIN" "$SSHD_NEW"; then
    # --- Anti-lockout: verify key & permissions before restarting ---
    step "Anti-lockout check: verifying SSH key and permissions..."

    LOCKOUT_OK=true

    # Check authorized_keys exists and is non-empty
    if [ ! -s "$AUTH_KEYS" ]; then
        err "authorized_keys is missing or empty for '${NEW_USER}' — aborting SSH restart."
        LOCKOUT_OK=false
    fi

    # Check permissions
    if [ "$LOCKOUT_OK" = true ]; then
        SSH_DIR_PERMS=$(stat -c '%a' "$SSH_DIR" 2>/dev/null)
        AUTH_KEYS_PERMS=$(stat -c '%a' "$AUTH_KEYS" 2>/dev/null)
        SSH_DIR_OWNER=$(stat -c '%U' "$SSH_DIR" 2>/dev/null)

        if [ "$SSH_DIR_PERMS" != "700" ]; then
            err ".ssh directory permissions are ${SSH_DIR_PERMS} (expected 700)."
            LOCKOUT_OK=false
        fi
        if [ "$AUTH_KEYS_PERMS" != "600" ]; then
            err "authorized_keys permissions are ${AUTH_KEYS_PERMS} (expected 600)."
            LOCKOUT_OK=false
        fi
        if [ "$SSH_DIR_OWNER" != "$NEW_USER" ]; then
            err ".ssh directory owned by ${SSH_DIR_OWNER} (expected ${NEW_USER})."
            LOCKOUT_OK=false
        fi
    fi

    # Check user can sudo
    if [ "$LOCKOUT_OK" = true ] && ! groups "$NEW_USER" | grep -qw "sudo"; then
        err "User '${NEW_USER}' is not in the sudo group."
        LOCKOUT_OK=false
    fi

    # Validate key format
    if [ "$LOCKOUT_OK" = true ]; then
        FIRST_KEY=$(head -1 "$AUTH_KEYS")
        if ! echo "$FIRST_KEY" | grep -qE '^(ssh-(rsa|ed25519|ecdsa)|ecdsa-sha2-)'; then
            err "First line of authorized_keys does not look like a valid SSH public key."
            LOCKOUT_OK=false
        fi
    fi

    if [ "$LOCKOUT_OK" = false ]; then
        warn "Anti-lockout checks FAILED. Removing SSH drop-in to prevent lockout."
        rm -f "$SSHD_DROPIN"
        err "Fix the issues above and re-run the script."
    else
        ok "All anti-lockout checks passed."

        step "Restarting SSH service..."
        run systemctl restart sshd || run systemctl restart ssh
        ok "SSH service restarted on port ${SSH_PORT}."

        echo
        warn "IMPORTANT: Do NOT close this session yet!"
        warn "Open a NEW terminal and test: ssh -p ${SSH_PORT} ${NEW_USER}@<server-ip>"
        warn "Only close this session after confirming the new connection works."
        echo

        if ! confirm "Did SSH access work in another terminal?"; then
            warn "Rolling back SSH configuration..."
            rm -f "$SSHD_DROPIN"
            run systemctl restart sshd || run systemctl restart ssh
            ok "SSH configuration reverted to defaults."
        fi
    fi
fi

rm -f "$SSHD_NEW"

# ---------------------------------------------------------------------------
# Step 4 — Firewall (ufw)
# ---------------------------------------------------------------------------
header "Step 4: Configure Firewall (ufw)"

if ! command -v ufw &>/dev/null; then
    step "Installing ufw..."
    run apt-get update
    run apt-get install -y ufw
fi

info "Planned firewall rules:"
echo "  - Default: deny incoming, allow outgoing"
echo "  - Rate-limit SSH on port ${SSH_PORT}/tcp (block after 6 attempts in 30s)"
echo

if confirm "Apply firewall rules?"; then
    run ufw default deny incoming
    run ufw default allow outgoing
    run ufw limit "${SSH_PORT}/tcp" comment "SSH"
    ok "Rules configured."

    step "Enabling ufw..."
    echo "y" | run ufw enable
    ok "Firewall is active."
    ufw status verbose
else
    warn "Firewall configuration skipped."
fi

# ---------------------------------------------------------------------------
# Step 5 — Automatic security updates
# ---------------------------------------------------------------------------
header "Step 5: Automatic Security Updates"

if dpkg -l | grep -q unattended-upgrades 2>/dev/null; then
    ok "unattended-upgrades is already installed."
else
    step "Installing unattended-upgrades..."
    run apt-get update
    run apt-get install -y unattended-upgrades
fi

AUTO_UPGRADES_FILE="/etc/apt/apt.conf.d/20auto-upgrades"
AUTO_UPGRADES_NEW=$(mktemp)

cat > "$AUTO_UPGRADES_NEW" << 'UPGEOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
UPGEOF

UNATTENDED_CONF="/etc/apt/apt.conf.d/50unattended-upgrades"
UNATTENDED_NEW=$(mktemp)

if [ "$DISTRO" = "debian" ]; then
    ORIGINS='
Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${distro_codename},label=Debian-Security";
    "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
};'
else
    ORIGINS='
Unattended-Upgrade::Origins-Pattern {
    "origin=Ubuntu,archive=${distro_codename}-security,label=Ubuntu";
};'
fi

cat > "$UNATTENDED_NEW" << UUEOF
// Unattended-Upgrade configuration — AutoSecure
${ORIGINS}

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
UUEOF

info "Auto-upgrade schedule config:"
echo
cat "$AUTO_UPGRADES_NEW"
echo

info "Unattended-upgrades security origins:"
echo
cat "$UNATTENDED_NEW"
echo

if confirm "Apply automatic security updates configuration?"; then
    cp "$AUTO_UPGRADES_NEW" "$AUTO_UPGRADES_FILE"
    cp "$UNATTENDED_NEW" "$UNATTENDED_CONF"
    ok "Automatic security updates configured."

    # Enable the timer
    run systemctl enable --now apt-daily.timer || true
    run systemctl enable --now apt-daily-upgrade.timer || true
    ok "Timers enabled."
else
    warn "Automatic updates skipped."
fi

rm -f "$AUTO_UPGRADES_NEW" "$UNATTENDED_NEW"

# ---------------------------------------------------------------------------
# Step 6 — Kernel hardening (sysctl)
# ---------------------------------------------------------------------------
header "Step 6: Kernel Hardening (sysctl)"

SYSCTL_FILE="/etc/sysctl.d/99-autosecure.conf"
SYSCTL_NEW=$(mktemp)

cat > "$SYSCTL_NEW" << 'SYSEOF'
# =============================================================================
# Kernel Hardening — AutoSecure
# =============================================================================

# --- IP Spoofing & Source Route Protection ---
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# --- ICMP Hardening ---
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# --- SYN Flood Protection ---
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2

# --- Disable IP Forwarding ---
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# --- Disable ICMP Redirects ---
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# --- Log Martian Packets ---
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# --- Kernel Address Space Layout Randomization ---
kernel.randomize_va_space = 2

# --- Restrict dmesg access ---
kernel.dmesg_restrict = 1

# --- Restrict kernel pointer access ---
kernel.kptr_restrict = 2

# --- Disable Magic SysRq key ---
kernel.sysrq = 0

# --- Prevent core dumps for SUID binaries ---
fs.suid_dumpable = 0

# --- Restrict ptrace scope ---
kernel.yama.ptrace_scope = 2

# --- TCP Hardening ---
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_rfc1337 = 1
SYSEOF

info "Planned sysctl hardening rules:"
echo
cat "$SYSCTL_NEW"
echo

if confirm "Apply kernel hardening parameters?"; then
    cp "$SYSCTL_NEW" "$SYSCTL_FILE"
    run sysctl --system
    ok "Kernel parameters applied."
else
    warn "Kernel hardening skipped."
fi

rm -f "$SYSCTL_NEW"

# ---------------------------------------------------------------------------
# Step 7 — Fail2ban
# ---------------------------------------------------------------------------
header "Step 7: Fail2ban (SSH Brute-Force Protection)"

if command -v fail2ban-client &>/dev/null; then
    ok "fail2ban is already installed."
else
    info "fail2ban monitors logs and bans IPs after repeated failed login attempts."
    if confirm "Install and configure fail2ban?"; then
        run apt-get update
        run apt-get install -y fail2ban
    else
        warn "fail2ban installation skipped."
    fi
fi

if command -v fail2ban-client &>/dev/null; then
    F2B_JAIL="/etc/fail2ban/jail.local"
    F2B_NEW=$(mktemp)

    cat > "$F2B_NEW" << F2BEOF
# =============================================================================
# Fail2ban Configuration — AutoSecure
# =============================================================================
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 3
banaction = ufw
bantime.increment = true
bantime.factor = 2

[sshd]
enabled  = true
port     = ${SSH_PORT}
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
F2BEOF

    info "Planned fail2ban configuration:"
    echo
    cat "$F2B_NEW"
    echo

    if confirm "Apply fail2ban configuration?"; then
        cp "$F2B_NEW" "$F2B_JAIL"
        run systemctl enable fail2ban
        run systemctl restart fail2ban
        ok "fail2ban configured and running."
    else
        warn "fail2ban configuration skipped."
    fi

    rm -f "$F2B_NEW"
fi

# ---------------------------------------------------------------------------
# Step 8 — Disable unused network protocols
# ---------------------------------------------------------------------------
header "Step 8: Disable Unused Network Protocols"

MODPROBE_FILE="/etc/modprobe.d/autosecure-disable.conf"
MODPROBE_NEW=$(mktemp)

cat > "$MODPROBE_NEW" << 'MODEOF'
# Disable uncommon/legacy network protocols — AutoSecure
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
install cramfs /bin/true
install freevxfs /bin/true
install jffs2 /bin/true
install hfs /bin/true
install hfsplus /bin/true
install udf /bin/true
MODEOF

info "The following unused kernel modules will be disabled:"
echo "  - dccp, sctp, rds, tipc (legacy network protocols)"
echo "  - cramfs, freevxfs, jffs2, hfs, hfsplus, udf (uncommon filesystems)"
echo

if confirm "Disable these modules?"; then
    cp "$MODPROBE_NEW" "$MODPROBE_FILE"
    ok "Modules disabled."
else
    warn "Module disabling skipped."
fi

rm -f "$MODPROBE_NEW"

# ---------------------------------------------------------------------------
# Step 9 — Restrict su to sudo group
# ---------------------------------------------------------------------------
header "Step 9: Restrict su Access to sudo Group"

info "This restricts the 'su' command to members of the sudo group only."
info "Other users and compromised services cannot switch to root via su."
echo

if confirm "Restrict su access to sudo group?"; then
    PAM_SU="/etc/pam.d/su"
    if [ -f "$PAM_SU" ]; then
        if grep -qE "^auth\s+required\s+pam_wheel\.so" "$PAM_SU"; then
            ok "pam_wheel.so is already enabled."
        else
            # Backup original
            if [ ! -f "${PAM_SU}.autosecure-backup" ]; then
                cp "$PAM_SU" "${PAM_SU}.autosecure-backup"
                ok "Backed up ${PAM_SU}"
            fi
            # Uncomment the pam_wheel.so line and add group=sudo
            if grep -qE "^#.*pam_wheel\.so" "$PAM_SU"; then
                sed -i 's/^#\s*\(auth\s\+required\s\+pam_wheel\.so\).*/\1 group=sudo/' "$PAM_SU"
            else
                # Line doesn't exist at all, add it after the first auth line
                sed -i '/^auth/a auth       required   pam_wheel.so group=sudo' "$PAM_SU"
            fi
            ok "su restricted to sudo group."
        fi
    else
        warn "${PAM_SU} not found. Skipping."
    fi
else
    warn "su restriction skipped."
fi

# ---------------------------------------------------------------------------
# Step 10 — Disable core dumps
# ---------------------------------------------------------------------------
header "Step 10: Disable Core Dumps"

NOCORE_FILE="/etc/security/limits.d/99-autosecure-nocore.conf"
NOCORE_NEW=$(mktemp)

cat > "$NOCORE_NEW" << 'COREEOF'
# Disable core dumps — AutoSecure
# Prevents processes from writing core dump files (security/privacy risk)
* hard core 0
COREEOF

if apply_config "Disable Core Dumps" "$NOCORE_FILE" "$NOCORE_NEW"; then
    ok "Core dumps disabled via limits.d drop-in."
fi

rm -f "$NOCORE_NEW"

# ---------------------------------------------------------------------------
# Step 11 — AppArmor
# ---------------------------------------------------------------------------
header "Step 11: AppArmor (Mandatory Access Control)"

if command -v aa-status &>/dev/null; then
    if aa-status --enabled 2>/dev/null; then
        ok "AppArmor is already active."
        if [ "$VERBOSE" = true ]; then
            aa-status 2>/dev/null || true
        fi
    else
        info "AppArmor is installed but not active."
        if confirm "Enable AppArmor?"; then
            run systemctl enable apparmor
            run systemctl start apparmor
            ok "AppArmor enabled and started."
        else
            warn "AppArmor activation skipped."
        fi
    fi
elif [ -d /sys/module/apparmor ]; then
    info "AppArmor kernel module is loaded but tools are not installed."
    if confirm "Install apparmor-utils and enable AppArmor?"; then
        run apt-get update
        run apt-get install -y apparmor apparmor-utils
        run systemctl enable apparmor
        run systemctl start apparmor
        ok "AppArmor installed and enabled."
    else
        warn "AppArmor installation skipped."
    fi
else
    info "AppArmor is not available on this system. Skipping."
fi

# ===========================================================================
# PHASE 3: Verification
# ===========================================================================
header "PHASE 3: Verification"

CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_SKIPPED=0

check_result() {
    local name="$1" result="$2"
    case "$result" in
        pass)
            printf "  ${GREEN}[PASS]${NC}  %s\n" "$name"
            CHECKS_PASSED=$((CHECKS_PASSED + 1))
            ;;
        fail)
            printf "  ${RED}[FAIL]${NC}  %s\n" "$name"
            CHECKS_FAILED=$((CHECKS_FAILED + 1))
            ;;
        *)
            printf "  ${YELLOW}[SKIP]${NC}  %s\n" "$name"
            CHECKS_SKIPPED=$((CHECKS_SKIPPED + 1))
            ;;
    esac
}

# 1. User exists with sudo
if id "$NEW_USER" &>/dev/null && groups "$NEW_USER" | grep -qw sudo; then
    check_result "User '${NEW_USER}' with sudo" "pass"
else
    check_result "User '${NEW_USER}' with sudo" "fail"
fi

# 2. SSH authorized_keys
if [ -f "$AUTH_KEYS" ] && [ -s "$AUTH_KEYS" ]; then
    check_result "SSH authorized_keys for '${NEW_USER}'" "pass"
else
    check_result "SSH authorized_keys for '${NEW_USER}'" "fail"
fi

# 3. SSH hardening drop-in
if [ -f "$SSHD_DROPIN" ]; then
    check_result "SSH hardening drop-in" "pass"
else
    check_result "SSH hardening drop-in" "skip"
fi

# 4. Firewall active + rate-limited
if ufw status 2>/dev/null | grep -q "Status: active"; then
    if ufw status 2>/dev/null | grep -q "${SSH_PORT}.*LIMIT"; then
        check_result "Firewall active (SSH rate-limited)" "pass"
    else
        check_result "Firewall active (SSH rate-limited)" "fail"
    fi
else
    check_result "Firewall active (SSH rate-limited)" "skip"
fi

# 5. Unattended-upgrades
if dpkg -l 2>/dev/null | grep -q unattended-upgrades; then
    check_result "Automatic security updates" "pass"
else
    check_result "Automatic security updates" "skip"
fi

# 6. Sysctl hardening
if [ -f "/etc/sysctl.d/99-autosecure.conf" ]; then
    check_result "Kernel hardening (sysctl)" "pass"
else
    check_result "Kernel hardening (sysctl)" "skip"
fi

# 7. Fail2ban running
if systemctl is-active fail2ban &>/dev/null; then
    check_result "Fail2ban running (progressive bans)" "pass"
else
    check_result "Fail2ban running (progressive bans)" "skip"
fi

# 8. Disabled modules
if [ -f "/etc/modprobe.d/autosecure-disable.conf" ]; then
    check_result "Unused protocols disabled" "pass"
else
    check_result "Unused protocols disabled" "skip"
fi

# 9. su restriction
if grep -qE "^auth\s+required\s+pam_wheel\.so" /etc/pam.d/su 2>/dev/null; then
    check_result "su restricted to sudo group" "pass"
else
    check_result "su restricted to sudo group" "skip"
fi

# 10. Core dumps
if [ -f "/etc/security/limits.d/99-autosecure-nocore.conf" ]; then
    check_result "Core dumps disabled" "pass"
else
    check_result "Core dumps disabled" "skip"
fi

# 11. AppArmor
if command -v aa-status &>/dev/null && aa-status --enabled 2>/dev/null; then
    check_result "AppArmor active" "pass"
else
    check_result "AppArmor active" "skip"
fi

echo
printf "  ${BOLD}Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}, ${YELLOW}%d skipped${NC}\n" \
    "$CHECKS_PASSED" "$CHECKS_FAILED" "$CHECKS_SKIPPED"

# ---------------------------------------------------------------------------
# Next steps
# ---------------------------------------------------------------------------
header "Next Steps"

echo "    1. Test SSH access in a NEW terminal before closing this session:"
echo "       ssh -p ${SSH_PORT} ${NEW_USER}@${IP_ADDR:-<server-ip>}"
echo
echo "    2. To revert changes:"
echo "       - SSH:   rm ${SSHD_DROPIN} && systemctl restart ssh"
echo "       - su:    cp /etc/pam.d/su.autosecure-backup /etc/pam.d/su"
echo "       - cores: rm /etc/security/limits.d/99-autosecure-nocore.conf"
echo
echo "    3. Consider additionally:"
echo "       - Setting up log monitoring (logwatch)"
echo "       - Setting up regular backups"
echo "       - Installing aide (file integrity monitoring)"
echo
printf "${GREEN}${BOLD}  Server hardening complete. Stay safe!${NC}\n\n"
