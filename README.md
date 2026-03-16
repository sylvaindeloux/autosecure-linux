# AutoSecure

Automated hardening script for fresh Debian/Ubuntu servers. Run it right after your first SSH access.

## Quick Start

One-liner from your server (as root):

```bash
curl -sLO https://raw.githubusercontent.com/sylvaindeloux/autosecure-linux/main/autosecure.sh && bash autosecure.sh
```

This downloads the script first, then runs it — required because the script is interactive and needs terminal input.

For verbose output (see all command results):

```bash
curl -sLO https://raw.githubusercontent.com/sylvaindeloux/autosecure-linux/main/autosecure.sh && bash autosecure.sh -v
```

## What It Does

The script is fully interactive — it shows you every change and asks for confirmation before applying.

| Step | Description |
|------|-------------|
| 1 | Create a sudo user |
| 2 | Set up SSH key authentication |
| 3 | Harden SSH (custom port, key-only, no root, no password, no tunneling, strong ciphers) |
| 4 | Configure firewall (ufw — SSH port only) |
| 5 | Enable automatic security updates (unattended-upgrades) |
| 6 | Harden kernel parameters (sysctl) |
| 7 | Install fail2ban (SSH brute-force protection) |
| 8 | Disable unused network protocols and filesystems |

## Requirements

- Fresh Debian or Ubuntu server
- Root access via SSH
- A public SSH key ready to paste

## Network Resilience

The script automatically runs inside a `screen` session (installed if needed). If your SSH connection drops, just reconnect — the script detects the existing session and resumes where it left off.

## License

MIT
