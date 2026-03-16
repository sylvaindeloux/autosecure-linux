# AutoSecure

Automated hardening script for fresh Debian/Ubuntu servers. Run it right after your first SSH access.

## Quick Start

One-liner from your server (as root):

```bash
curl -sL https://raw.githubusercontent.com/sylvaindeloux/autosecure-linux/main/autosecure.sh | bash
```

Or if you prefer to review it first:

```bash
curl -sL -o autosecure.sh https://raw.githubusercontent.com/sylvaindeloux/autosecure-linux/main/autosecure.sh
less autosecure.sh
bash autosecure.sh
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
| 9 | Secure shared memory (/run/shm) |

## Requirements

- Fresh Debian or Ubuntu server
- Root access via SSH
- A public SSH key ready to paste

## License

MIT
