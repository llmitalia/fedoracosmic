#!/usr/bin/env bash
set -euo pipefail

# --- Auto-elevate with sudo if not already root ---
if [[ $EUID -ne 0 ]]; then
    exec sudo -E bash "$0" "$@"
fi

# ANSI color codes
GREEN="\033[0;32m"
RED="\033[0;31m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
NC="\033[0m" # No Color

# URLs
NORDVPN_INSTALL_URL="https://downloads.nordcdn.com/apps/linux/install.sh"
DENO_INSTALL_URL="https://deno.land/install.sh"
BUN_INSTALL_URL="https://bun.sh/install"

# Log file setup
LOG_FILE="$(dirname "$0")/debloat_install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Packages to remove
DEBLOAT_PKGS=(libreoffice-core libreoffice-* vim)
# Essential packages (added tealdeer and fastfetch)
ESSENTIAL_PKGS=(curl wget htop chromium tealdeer fastfetch)
# Flatpak apps
FLATPAK_PKGS=(com.spotify.Client com.bitwarden.desktop dev.vencord.Vesktop)

# Ask user function with colored prompt
ask() {
    local prompt="$1" default="${2:-}"
    local answer
    while true; do
        if [[ "$default" == "s" ]]; then
            printf "${YELLOW}%s [S/n]: ${NC}" "$prompt"
        elif [[ "$default" == "n" ]]; then
            printf "${YELLOW}%s [s/N]: ${NC}" "$prompt"
        else
            printf "${YELLOW}%s [s/n]: ${NC}" "$prompt"
        fi
        read -r answer
        answer="${answer:-$default}"
        case "${answer,,}" in
            s|si|sì|y|yes) return 0 ;;
            n|no) return 1 ;;
            *) echo "Risposta non valida" ;;
        esac
    done
}

# Check if package is installed
is_pkg_installed() {
    [[ "$1" == *"*"* ]] && rpm -qa | grep -q "^${1//\*/.*}$" || rpm -q "$1" &>/dev/null
}

# DEV packages installer
install_dev_pkgs() {
    echo -e "\n${BLUE}Dev tools installation:${NC}"
    # Always install git
    dnf -q -y install git && echo -e "${GREEN}[OK] git${NC}" || echo -e "${RED}[ERR] git${NC}"
    # IDE: VSCode via Flatpak codium
    if ask "Installare VSCode (Codium) come Flatpak?" "n"; then
        flatpak install -y flathub com.vscodium.codium && echo -e "${GREEN}[OK] com.vscodium.codium${NC}" || echo -e "${RED}[ERR] com.vscodium.codium${NC}"
    fi
    # Ask for runtime choice
    echo -e "${YELLOW}Scegli un runtime da installare:${NC}"
    echo -e "${YELLOW}1) nodejs\n2) deno\n3) bun${NC}"
    # Prompt selection
    printf "${YELLOW}Scelta [1-3]: ${NC}"
    read -r choice
    case "$choice" in
        1)
            dnf -q -y install nodejs && echo -e "${GREEN}[OK] nodejs${NC}" || echo -e "${RED}[ERR] nodejs${NC}"
            ;;
        2)
            curl -fsSL "$DENO_INSTALL_URL" | sh && echo -e "${GREEN}[OK] deno${NC}" || echo -e "${RED}[ERR] deno${NC}"
            ;;
        3)
            curl -fsSL "$BUN_INSTALL_URL" | bash && echo -e "${GREEN}[OK] bun${NC}" || echo -e "${RED}[ERR] bun${NC}"
            ;;
        *)
            echo "Scelta non valida"
            ;;
    esac
}

# Install NVIDIA drivers
install_nvidia() {
    echo "Installazione driver NVIDIA..."
    for repo in \
        https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
        https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm; do
        dnf -q -y install "$repo" && echo -e "${GREEN}[OK] $(basename $repo)${NC}" || echo -e "${RED}[ERR] $(basename $repo)${NC}"
    done
    for pkg in akmod-nvidia xorg-x11-drv-nvidia-cuda; do
        dnf -q -y install "$pkg" && echo -e "${GREEN}[OK] $pkg${NC}" || echo -e "${RED}[ERR] $pkg${NC}"
    done
    dnf -q mark installed akmod-nvidia && echo -e "${GREEN}[OK] mark akmod-nvidia${NC}" || echo -e "${RED}[ERR] mark akmod-nvidia${NC}"
}

# Install NordVPN
install_nordvpn() {
    echo "Installazione NordVPN..."
    bash <(curl -sSf "$NORDVPN_INSTALL_URL") <<EOF
y
EOF
    [[ $? -eq 0 ]] && echo -e "${GREEN}[OK] NordVPN install script${NC}" || echo -e "${RED}[ERR] NordVPN install script${NC}"
    nordvpn set technology nordlynx && echo -e "${GREEN}[OK] nordvpn set technology nordlynx${NC}" || echo -e "${RED}[ERR] nordvpn set technology nordlynx${NC}"
}

# Pacchetti da rimuovere
echo -e "${BLUE}Pacchetti da rimuovere:${NC}"
INSTALLED_BLOAT=()
for pkg in "${DEBLOAT_PKGS[@]}"; do
    if rpm -qa | grep -q "${pkg//\*/.*}"; then
        echo -e "${YELLOW}- $pkg${NC}"
        [[ "$pkg" == *"*"* ]] && mapfile -t found_pkgs < <(rpm -qa | grep "${pkg//\*/.*}") && INSTALLED_BLOAT+=("${found_pkgs[@]}") || INSTALLED_BLOAT+=("$pkg")
    fi
done

# Pacchetti da installare
echo -e "\n${BLUE}Pacchetti da installare:${NC}"
MISSING_PKGS=()
for pkg in "${ESSENTIAL_PKGS[@]}"; do
    if ! is_pkg_installed "$pkg"; then
        echo -e "${YELLOW}- $pkg${NC}"
        MISSING_PKGS+=("$pkg")
    fi
done

# App Flatpak da installare
echo -e "\n${BLUE}App Flatpak da installare:${NC}"
for pkg in "${FLATPAK_PKGS[@]}"; do
    echo -e "${YELLOW}- $pkg${NC}"
done

# Detect NVIDIA GPU
HAS_NVIDIA=$(lspci | grep -i nvidia || echo "no")
[[ "$HAS_NVIDIA" != "no" ]] && echo -e "\nScheda NVIDIA rilevata: si possono installare i driver"

echo -e "\n------------------------"
echo "Procedendo con le operazioni individuali..."

# Debloat
if [[ ${#INSTALLED_BLOAT[@]} -gt 0 ]] && ask "Rimuovere i pacchetti di bloatware (LibreOffice, ecc)?" "s"; then
    for pkg in "${INSTALLED_BLOAT[@]}"; do
        dnf -q -y remove "$pkg" && echo -e "${GREEN}[OK] $pkg${NC}" || echo -e "${RED}[ERR] $pkg${NC}"
    done
fi

# Essentials
if [[ ${#MISSING_PKGS[@]} -gt 0 ]] && ask "Installare i pacchetti essenziali?" "s"; then
    for pkg in "${MISSING_PKGS[@]}"; do
        dnf -q -y install "$pkg" && echo -e "${GREEN}[OK] $pkg${NC}" || echo -e "${RED}[ERR] $pkg${NC}"
    done
fi

# Flatpak
if ask "Installare le applicazioni Flatpak?" "s"; then
    dnf -q -y install flatpak
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    for pkg in "${FLATPAK_PKGS[@]}"; do
        if flatpak list --app | grep -q "^$pkg"; then
            echo -e "${GREEN}[OK] $pkg${NC}"
        else
            flatpak install -y --noninteractive flathub "$pkg" && echo -e "${GREEN}[OK] $pkg${NC}" || echo -e "${RED}[ERR] $pkg${NC}"
        fi
    done
fi

# NVIDIA drivers
if [[ "$HAS_NVIDIA" != "no" ]] && ask "Installare i driver NVIDIA?" "s"; then
    install_nvidia
fi

# NordVPN
if ask "Installare NordVPN?" "s"; then
    install_nordvpn
fi

# Dev tools
if ask "Installare gli strumenti di sviluppo (git + runtime + IDE)?" "n"; then
    install_dev_pkgs
fi

# Messaggio finale in giallo
echo -e "\n${YELLOW}Operazioni completate - Log: $LOG_FILE${NC}"
if ask "Riavviare ora?" "n"; then
    reboot
fi
