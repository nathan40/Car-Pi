#!/usr/bin/env bash
#
# setup.sh — Car-Pi one-shot installer
#
# Turns a FRESH Raspberry Pi OS Lite (64-bit, Debian 13 "Trixie") image on a
# Raspberry Pi 4 into the fully-offline car media server described in
# pi-media-server-master-guide.md:
#
#   * Jellyfin (:8096), Audiobookshelf (:13378), Navidrome (:4533) in Docker
#   * Homepage dashboard + games arcade (:80)
#   * Own Wi-Fi access point (hostapd + dnsmasq) — no internet needed after build
#   * Auto-shuffle music out the 3.5mm aux jack (MPD) + web control API (:8088)
#   * Dashboard power-off button service (:8097)
#
# HOW TO USE
#   First time on a fresh Pi (no local copy of this repo yet)? Run this one
#   line over SSH and skip straight to step 4:
#     curl -fsSL https://raw.githubusercontent.com/nathan40/Car-Pi/main/setup.sh | sudo bash -s -- --bootstrap
#
#   Already have the repo?
#   1. Flash Pi OS Lite 64-bit with Raspberry Pi Imager (set hostname/user/SSH,
#      set the Wi-Fi COUNTRY in the imager options).
#   2. Connect the Pi to your network with an ETHERNET cable (internet needed
#      for the build only), SSH in, copy this whole car-pi folder over.
#   3. Run:  sudo ./setup.sh
#   4. Answer the questions (all asked up front), confirm, walk away.
#
# The script is safe to re-run: every step is idempotent.
#
set -Eeuo pipefail

REPO_URL="https://github.com/nathan40/Car-Pi.git"

# --------------------------------------------------------------- bootstrap --
# Lets a brand-new Pi go from nothing to a running installer with one curl
# command (see HOW TO USE above: `curl ... | sudo bash -s -- --bootstrap`).
# When piped straight into `bash` this script has no on-disk path and no
# terminal on stdin (the pipe occupies it as the script's own source), so it
# can't run interactively as-is: clone the real repo instead, then re-exec
# ITS setup.sh with stdin reconnected to the terminal.
if [[ "${1:-}" == "--bootstrap" ]]; then
    if [[ $EUID -ne 0 ]]; then
        echo "Run with sudo: curl -fsSL https://raw.githubusercontent.com/nathan40/Car-Pi/main/setup.sh | sudo bash -s -- --bootstrap" >&2
        exit 1
    fi
    command -v git >/dev/null 2>&1 || { apt-get update && apt-get install -y git; }
    DEST="${SUDO_USER:+/home/$SUDO_USER}"; DEST="${DEST:-$HOME}/Car-Pi"
    if [[ -d "$DEST/.git" ]]; then
        echo "==> $DEST already exists, pulling latest..."
        git -C "$DEST" pull --ff-only
    else
        echo "==> Cloning $REPO_URL to $DEST ..."
        git clone --depth 1 "$REPO_URL" "$DEST"
    fi
    [[ -n "${SUDO_USER:-}" ]] && chown -R "$SUDO_USER:$SUDO_USER" "$DEST"
    exec bash "$DEST/setup.sh" < /dev/tty
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/car-pi-setup.log"

# ---------------------------------------------------------------- output ----
if [[ -t 1 ]]; then
    RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'; CYN=$'\e[36m'
    BLD=$'\e[1m'; RST=$'\e[0m'
else
    RED=""; GRN=""; YLW=""; CYN=""; BLD=""; RST=""
fi

info() { echo "${CYN}==>${RST} $*"; }
ok()   { echo "${GRN}   ok${RST} $*"; }
warn() { echo "${YLW} warn${RST} $*"; }
die()  { echo "${RED} FAIL${RST} $*" >&2; exit 1; }

CURRENT_STEP="preflight"
step() {
    CURRENT_STEP="$1"
    echo
    echo "${BLD}${CYN}===== $1 =====${RST}"
}
trap 'echo; echo "${RED}Setup failed during: ${CURRENT_STEP} (line ${LINENO}).${RST}"; echo "Full log: ${LOG_FILE}"; echo "Fix the problem and re-run: sudo ./setup.sh (finished steps are safe to repeat)."' ERR

# ------------------------------------------------------------- preflight ----
[[ $EUID -eq 0 ]]  || die "This script must run as root. Use: sudo ./setup.sh"
[[ -t 0 ]]         || die "This script is interactive — run it from a terminal."

for f in docker-compose.yml homepage/index.html car-music-web.py shutdown-server.py; do
    [[ -e "$SCRIPT_DIR/$f" ]] || die "Missing $SCRIPT_DIR/$f — run setup.sh from a complete copy of the car-pi folder."
done

OS_WARNINGS=()
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    [[ "${VERSION_CODENAME:-}" == "trixie" ]] || OS_WARNINGS+=("OS is '${PRETTY_NAME:-unknown}', not Debian 13 (Trixie) — this script is tested on Pi OS Lite Trixie.")
fi
[[ "$(uname -m)" == "aarch64" ]] || OS_WARNINGS+=("Architecture is $(uname -m), not aarch64 — expected 64-bit Pi OS on a Pi 4.")

# Built-in Wi-Fi = the interface on the brcmfmac driver (guide Part 2).
WLAN=""
for d in /sys/class/net/wlan*; do
    [[ -e "$d" ]] || continue
    drv="$(basename "$(readlink -f "$d/device/driver" 2>/dev/null)" 2>/dev/null || true)"
    if [[ "$drv" == "brcmfmac" ]]; then WLAN="$(basename "$d")"; break; fi
done
if [[ -z "$WLAN" && -e /sys/class/net/wlan0 ]]; then
    WLAN="wlan0"
    OS_WARNINGS+=("Could not confirm the brcmfmac (built-in) radio; falling back to wlan0.")
fi
[[ -n "$WLAN" ]] || die "No Wi-Fi interface found. Is this a Pi 4? Was the Wi-Fi country set in Raspberry Pi Imager?"

# Subnets currently in use on OTHER interfaces (the AP must not clash with
# the wired network; the AP's own interface is excluded so re-runs work).
mapfile -t USED_PREFIXES < <(ip -o -4 addr show scope global 2>/dev/null \
    | awk -v wl="$WLAN" '$2!=wl {split($4,a,"/"); n=split(a[1],o,"."); if (n==4) print o[1]"."o[2]"."o[3]}' | sort -u)

info "Checking internet access (the build needs it; the finished box does not)..."
curl -fsSL --max-time 15 -o /dev/null https://deb.debian.org \
    || die "No internet access. Connect the Pi via Ethernet to a network with internet, then re-run."
ok "online"
ok "built-in Wi-Fi interface: $WLAN"

# ---------------------------------------------------------- ask helpers -----
ask() {                       # ask VAR "Prompt" "default" [validator]
    local -n _out="$1"; local prompt="$2" def="$3" validator="${4:-}" ans
    while true; do
        if [[ -n "$def" ]]; then
            read -rp "  $prompt [$def]: " ans; ans="${ans:-$def}"
        else
            read -rp "  $prompt: " ans
        fi
        if [[ -z "$validator" ]] || "$validator" "$ans"; then _out="$ans"; return 0; fi
    done
}

ask_yn() {                    # ask_yn "Prompt" "Y|N" -> sets REPLY_YN=yes|no
    local prompt="$1" def="$2" ans hint
    [[ "$def" == "Y" ]] && hint="Y/n" || hint="y/N"
    while true; do
        read -rp "  $prompt [$hint]: " ans; ans="${ans:-$def}"
        case "${ans,,}" in
            y|yes) REPLY_YN="yes"; return 0 ;;
            n|no)  REPLY_YN="no";  return 0 ;;
            *) echo "    Please answer y or n." ;;
        esac
    done
}

err() { echo "    ${RED}x${RST} $*"; return 1; }

valid_hostname() {
    [[ "$1" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] \
        || err "Use 1-63 lowercase letters, digits, or hyphens (no leading/trailing hyphen)."
}
valid_ssid() {
    local s="$1"
    [[ ${#s} -ge 1 && ${#s} -le 32 ]] || { err "SSID must be 1-32 characters."; return 1; }
    LC_ALL=C command grep -q '^[[:print:]]\+$' <<< "$s" || { err "Use plain printable characters."; return 1; }
    [[ "$s" != " "* && "$s" != *" " ]] || { err "No leading/trailing spaces."; return 1; }
}
valid_pass() {
    local p="$1"
    [[ ${#p} -ge 8 && ${#p} -le 63 ]] || { err "WPA2 passwords must be 8-63 characters."; return 1; }
    LC_ALL=C command grep -q '^[[:print:]]\+$' <<< "$p" || { err "Use plain printable characters (letters, digits, punctuation)."; return 1; }
    [[ "$p" != " "* && "$p" != *" " ]] || { err "No leading/trailing spaces."; return 1; }
}
valid_country() {
    [[ "${1^^}" =~ ^[A-Z]{2}$ ]] || err "Use a 2-letter country code (US, GB, DE, ...)."
}
valid_tz() {
    [[ -f "/usr/share/zoneinfo/$1" ]] || err "Unknown timezone. Examples: America/Chicago, America/New_York, Europe/London."
}
valid_user() {
    id -u "$1" >/dev/null 2>&1 || err "No such user on this Pi. Use the account you created in Raspberry Pi Imager."
}
valid_volume() {
    { [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 <= 100 )); } || err "Enter a number from 0 to 100."
}
valid_subnet() {              # accepts 192.168.4 | 192.168.4.0 | 192.168.4.0/24
    local s="${1// /}" a b c d extra o used
    s="${s%/24}"
    IFS=. read -r a b c d extra <<< "$s"
    [[ -n "$a" && -n "$b" && -n "$c" && -z "${extra:-}" ]] \
        || { err "Enter the first three octets of a /24, e.g. 192.168.4"; return 1; }
    if [[ -n "${d:-}" && "$d" != "0" ]]; then
        err "Give the network itself (e.g. 192.168.4 or 192.168.4.0), not a host address."; return 1
    fi
    for o in "$a" "$b" "$c"; do
        { [[ "$o" =~ ^[0-9]{1,3}$ ]] && (( 10#$o <= 255 )); } || { err "'$o' is not a valid octet (0-255)."; return 1; }
    done
    (( 10#$a >= 1 && 10#$a <= 223 )) || { err "First octet must be 1-223."; return 1; }
    local prefix="$a.$b.$c"
    for used in "${USED_PREFIXES[@]:-}"; do
        [[ "$prefix" == "$used" ]] && { err "$prefix.x is already in use on this Pi's wired network — pick a different subnet so the AP doesn't clash."; return 1; }
    done
    if ! { [[ "$a" == "10" ]] || [[ "$prefix" == 192.168.* ]] || { [[ "$a" == "172" ]] && (( 10#$b >= 16 && 10#$b <= 31 )); }; }; then
        warn "  $prefix.x is not a private (RFC1918) range — it will work, but 192.168.x / 10.x is recommended."
    fi
    SUBNET_PREFIX="$prefix"
}

# --------------------------------------------------- media-drive candidates -
# Partitions NOT on the OS disk, with a filesystem, not currently mounted.
# (Queried one property at a time — lsblk's raw table shifts columns on
# empty fields, which silently corrupts the FSTYPE/MOUNTPOINT filter.)
ROOT_SRC="$(findmnt -no SOURCE / 2>/dev/null || true)"
ROOT_DISK="$(lsblk -no PKNAME "$ROOT_SRC" 2>/dev/null | head -n1 || true)"
MEDIA_CANDIDATES=()
while IFS= read -r part; do
    [[ -n "$part" ]] || continue
    pdisk="$(lsblk -no PKNAME "$part" 2>/dev/null | head -n1 || true)"
    pfstype="$(lsblk -no FSTYPE "$part" 2>/dev/null | head -n1 || true)"
    pmnt="$(lsblk -no MOUNTPOINT "$part" 2>/dev/null | head -n1 || true)"
    psize="$(lsblk -no SIZE "$part" 2>/dev/null | head -n1 || true)"
    [[ -n "$ROOT_DISK" && "$pdisk" == "$ROOT_DISK" ]] && continue   # skip the OS disk
    [[ -n "$pfstype" ]] || continue                                 # needs an existing filesystem
    [[ -z "$pmnt" ]]    || continue                                 # skip anything already mounted
    MEDIA_CANDIDATES+=("$part"$'\t'"$pfstype"$'\t'"$psize")
done < <(lsblk -rpno NAME,TYPE 2>/dev/null | awk '$2=="part"{print $1}')

# =================================================================== ask ====
echo
echo "${BLD}Car-Pi setup — answer these questions, confirm, then walk away.${RST}"
echo "  (Press Enter to accept the [default].)"
echo
echo "${BLD}-- Identity --${RST}"
ask DEVICE_NAME "Device name (hostname; also becomes the web address <name>.lan)" "carpi" valid_hostname

echo
echo "${BLD}-- Wi-Fi access point (what the tablets join in the car) --${RST}"
ask SSID "Wi-Fi network name (SSID)" "RoadTrip" valid_ssid
echo "    (Password is shown as you type so you can't typo it — it's the family car Wi-Fi.)"
ask WIFI_PASS "Wi-Fi password (8-63 chars)" "" valid_pass
echo "    5 GHz = faster, ideal in/around the car (default).  2.4 GHz = slower but longer range."
while true; do
    read -rp "  Wi-Fi band — 5 or 2.4 [5]: " WIFI_BAND; WIFI_BAND="${WIFI_BAND:-5}"
    case "$WIFI_BAND" in
        5|5ghz|5GHz)     WIFI_BAND="5";   break ;;
        2.4|2|24|2.4ghz) WIFI_BAND="2.4"; break ;;
        *) echo "    Enter 5 or 2.4." ;;
    esac
done
COUNTRY_DEFAULT="$(raspi-config nonint get_wifi_country 2>/dev/null || true)"
ask WIFI_COUNTRY "Wi-Fi country code (regulatory domain)" "${COUNTRY_DEFAULT:-US}" valid_country
WIFI_COUNTRY="${WIFI_COUNTRY^^}"

echo
echo "${BLD}-- Network addressing --${RST}"
echo "    The Pi takes .1 of this subnet; tablets get .100-.200 by DHCP (/24)."
ask SUBNET_IN "IP subnet for the car network (first three octets)" "192.168.4" valid_subnet
PI_IP="$SUBNET_PREFIX.1"
DHCP_START="$SUBNET_PREFIX.100"
DHCP_END="$SUBNET_PREFIX.200"

echo
echo "${BLD}-- System --${RST}"
TZ_DEFAULT="$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || true)"
ask TIMEZONE "Timezone (no internet in the car = no NTP, so set it right)" "${TZ_DEFAULT:-America/Chicago}" valid_tz
ask RUN_USER "Pi user account that owns the media/services" "${SUDO_USER:-pi}" valid_user
PUID="$(id -u "$RUN_USER")"
PGID="$(id -g "$RUN_USER")"

echo
echo "${BLD}-- Car audio --${RST}"
echo "    Music auto-shuffles out the 3.5mm aux jack on every boot (guide Part 9)."
ask MUSIC_VOLUME "Music volume at boot, 0-100 (the car's own knob stays the main control)" "80" valid_volume
MUSIC_VOLUME=$((10#$MUSIC_VOLUME))   # normalize e.g. "080" -> 80

echo
echo "${BLD}-- Media storage --${RST}"
MEDIA_DEV=""; MEDIA_FSTYPE=""; MEDIA_UUID=""
if (( ${#MEDIA_CANDIDATES[@]} > 0 )); then
    echo "    The guide recommends keeping media OFF the SD card. Found these unmounted partition(s):"
    echo "      0) SD card — keep media on the OS card at /srv/media"
    i=1
    for c in "${MEDIA_CANDIDATES[@]}"; do
        IFS=$'\t' read -r cname cfstype csize <<< "$c"
        echo "      $i) $cname — $csize, $cfstype  (will be mounted permanently at /srv/media)"
        i=$((i+1))
    done
    while true; do
        read -rp "  Where should media live? [0]: " pick; pick="${pick:-0}"
        if [[ "$pick" == "0" ]]; then break; fi
        if [[ "$pick" =~ ^[0-9]+$ ]] && (( pick >= 1 && pick <= ${#MEDIA_CANDIDATES[@]} )); then
            IFS=$'\t' read -r MEDIA_DEV MEDIA_FSTYPE _ <<< "${MEDIA_CANDIDATES[$((pick-1))]}"
            MEDIA_UUID="$(blkid -s UUID -o value "$MEDIA_DEV" 2>/dev/null || true)"
            [[ -n "$MEDIA_UUID" ]] || { echo "    Couldn't read a UUID from $MEDIA_DEV — pick another option."; MEDIA_DEV=""; continue; }
            break
        fi
        echo "    Enter a number from the list."
    done
else
    echo "    No extra drive detected — media will live on the SD card at /srv/media."
    echo "    (Plug in a USB drive and re-run this script later to move it, if you like.)"
fi

echo
echo "${BLD}-- Finish --${RST}"
ask_yn "Reboot automatically when setup finishes? (needed to bring the Wi-Fi AP up)" "Y"
AUTO_REBOOT="$REPLY_YN"

# ------------------------------------------------------------- summary ------
LAN_NAME="${DEVICE_NAME}.lan"
if [[ "$WIFI_BAND" == "5" ]]; then BAND_DESC="5 GHz, channel 36 (80 MHz)"; else BAND_DESC="2.4 GHz, channel 6"; fi

echo
echo "${BLD}================= Review =================${RST}"
echo "  Device name / hostname : $DEVICE_NAME"
echo "  Dashboard address      : http://$LAN_NAME  (also http://$PI_IP)"
echo "  Wi-Fi SSID             : $SSID"
echo "  Wi-Fi password         : $WIFI_PASS"
echo "  Wi-Fi band             : $BAND_DESC   country: $WIFI_COUNTRY"
echo "  Pi address on its AP   : $PI_IP   (DHCP $DHCP_START-$DHCP_END)"
echo "  Timezone               : $TIMEZONE"
echo "  Service user           : $RUN_USER (uid $PUID)"
echo "  Boot music volume      : $MUSIC_VOLUME"
if [[ -n "$MEDIA_DEV" ]]; then
    echo "  Media storage          : $MEDIA_DEV ($MEDIA_FSTYPE) mounted at /srv/media"
else
    echo "  Media storage          : SD card (/srv/media)"
fi
echo "  Reboot when done       : $AUTO_REBOOT"
if (( ${#OS_WARNINGS[@]} > 0 )); then
    echo
    for w in "${OS_WARNINGS[@]}"; do warn "$w"; done
fi
echo "${BLD}==========================================${RST}"
echo
echo "  Everything from here on is unattended (apt upgrade, Docker install,"
echo "  image pulls, AP + audio setup). Expect 15-40 minutes on a Pi 4."
ask_yn "Start the install now?" "Y"
[[ "$REPLY_YN" == "yes" ]] || { echo "  Nothing was changed. Re-run when ready."; exit 0; }

# From here on: unattended. Log everything.
exec > >(tee -a "$LOG_FILE") 2>&1
echo
info "Unattended install started $(date). Logging to $LOG_FILE"
export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

# ================================================================ steps =====
step "System identity (hostname, timezone, Wi-Fi country)"
hostnamectl set-hostname "$DEVICE_NAME"
if grep -q '^127\.0\.1\.1' /etc/hosts; then
    sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t$DEVICE_NAME/" /etc/hosts
else
    printf '127.0.1.1\t%s\n' "$DEVICE_NAME" >> /etc/hosts
fi
timedatectl set-timezone "$TIMEZONE"
if command -v raspi-config >/dev/null 2>&1; then
    raspi-config nonint do_wifi_country "$WIFI_COUNTRY" \
        || warn "raspi-config could not set the Wi-Fi country (continuing; hostapd sets it too)"
fi
rfkill unblock wlan 2>/dev/null || true
ok "hostname=$DEVICE_NAME timezone=$TIMEZONE wifi-country=$WIFI_COUNTRY"

if [[ -n "$MEDIA_DEV" ]]; then
    step "Media drive ($MEDIA_DEV -> /srv/media)"
    mkdir -p /srv/media
    # fat-family/ntfs get ownership via mount options and no fsck pass
    # (no reliable fsck helper on a Lite image); ext-family keeps fsck.
    case "$MEDIA_FSTYPE" in
        vfat|exfat) FSTAB_TYPE="$MEDIA_FSTYPE"; FSTAB_OPTS="defaults,noatime,nofail,x-systemd.device-timeout=10,uid=$PUID,gid=$PGID,umask=022"; FSCK_PASS=0 ;;
        ntfs)       FSTAB_TYPE="ntfs3";         FSTAB_OPTS="defaults,noatime,nofail,x-systemd.device-timeout=10,uid=$PUID,gid=$PGID,umask=022"; FSCK_PASS=0 ;;
        ext2|ext3|ext4) FSTAB_TYPE="$MEDIA_FSTYPE"; FSTAB_OPTS="defaults,noatime,nofail,x-systemd.device-timeout=10"; FSCK_PASS=2 ;;
        *)          FSTAB_TYPE="$MEDIA_FSTYPE"; FSTAB_OPTS="defaults,noatime,nofail,x-systemd.device-timeout=10"; FSCK_PASS=0 ;;
    esac
    if ! grep -q "UUID=$MEDIA_UUID" /etc/fstab; then
        if grep -q '[[:space:]]/srv/media[[:space:]]' /etc/fstab; then
            die "/etc/fstab already has a different /srv/media entry — resolve that first."
        fi
        printf 'UUID=%s  /srv/media  %s  %s  0  %s\n' \
            "$MEDIA_UUID" "$FSTAB_TYPE" "$FSTAB_OPTS" "$FSCK_PASS" >> /etc/fstab
    fi
    systemctl daemon-reload
    mountpoint -q /srv/media || mount /srv/media
    ok "$MEDIA_DEV mounted at /srv/media ('nofail' so boot never hangs on a missing drive)"
fi

step "System update + packages (hostapd, dnsmasq, mpd, mpc, ...)"
apt-get update
apt-get "${APT_OPTS[@]}" full-upgrade
apt-get "${APT_OPTS[@]}" install hostapd dnsmasq mpd mpc alsa-utils fake-hwclock avahi-daemon curl ca-certificates
systemctl stop hostapd dnsmasq mpd 2>/dev/null || true
ok "packages installed"

step "Docker engine"
if command -v docker >/dev/null 2>&1; then
    ok "docker already installed: $(docker --version)"
else
    info "Installing via get.docker.com..."
    if ! curl -fsSL https://get.docker.com | sh; then
        warn "get.docker.com failed — falling back to Docker's apt repo (guide §3.1 note)"
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc
        # shellcheck disable=SC1091
        . /etc/os-release
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${VERSION_CODENAME:-trixie} stable" \
            > /etc/apt/sources.list.d/docker.list
        apt-get update
        apt-get "${APT_OPTS[@]}" install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
fi
systemctl enable --now docker
docker compose version >/dev/null 2>&1 || die "docker compose plugin missing after install"
usermod -aG docker "$RUN_USER" || true
ok "docker ready; $RUN_USER added to the docker group"

step "Folder layout under /srv"
mkdir -p /srv/media/{movies,tv,audiobooks,podcasts,music}
mkdir -p /srv/config/{jellyfin,navidrome}
mkdir -p /srv/config/audiobookshelf/{config,metadata}
mkdir -p /srv/homepage/bingo
chown -R "$PUID:$PGID" /srv/config /srv/homepage 2>/dev/null || true
chown -R "$PUID:$PGID" /srv/media 2>/dev/null || true   # no-op on vfat/exfat/ntfs (uid= mount option rules there)
ok "/srv layout created and owned by $RUN_USER"

step "App files (docker-compose.yml, homepage + games arcade)"
install -m 0644 "$SCRIPT_DIR/docker-compose.yml" /srv/docker-compose.yml
sed -i -E \
    -e "s|PUID=[0-9]+|PUID=$PUID|" \
    -e "s|PGID=[0-9]+|PGID=$PGID|" \
    -e "s|user: \"[0-9]+:[0-9]+\"|user: \"$PUID:$PGID\"|" \
    -e "s|TZ=.+|TZ=$TIMEZONE|" \
    /srv/docker-compose.yml
cp -a "$SCRIPT_DIR/homepage/." /srv/homepage/
find /srv/homepage -name '*.md' -delete
if [[ "$LAN_NAME" != "media.lan" ]]; then
    sed -i "s|media\.lan|$LAN_NAME|g" /srv/homepage/index.html
fi
chown -R "$PUID:$PGID" /srv/homepage 2>/dev/null || true
chown -R 33:33 /srv/homepage/bingo   # 33 = www-data inside php:8-apache (Car Bingo shared state)
ok "dashboard + $(find /srv/homepage/games -name '*.html' | wc -l) game files deployed (URLs use $LAN_NAME)"

step "Media containers (pulls images — the long part)"
(cd /srv && docker compose up -d)
(cd /srv && docker compose ps)
ok "jellyfin / audiobookshelf / navidrome / homepage are up"

step "Offline Wi-Fi access point ($WLAN: SSID '$SSID', $BAND_DESC)"
if command -v nmcli >/dev/null 2>&1; then
    tee /etc/NetworkManager/conf.d/99-unmanaged-wlan.conf >/dev/null <<EOF
[keyfile]
unmanaged-devices=interface-name:$WLAN
EOF
    systemctl reload NetworkManager 2>/dev/null || true
    ok "NetworkManager told to leave $WLAN alone (Ethernet stays managed for SSH)"
fi

tee "/etc/systemd/system/${WLAN}-static.service" >/dev/null <<EOF
[Unit]
Description=Static IP for $WLAN access point
After=sys-subsystem-net-devices-${WLAN}.device
Wants=sys-subsystem-net-devices-${WLAN}.device
Before=hostapd.service dnsmasq.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=-/sbin/ip addr flush dev $WLAN
ExecStart=/sbin/ip addr add $PI_IP/24 dev $WLAN
ExecStart=/sbin/ip link set $WLAN up

[Install]
WantedBy=multi-user.target
EOF

if [[ "$WIFI_BAND" == "5" ]]; then
    tee /etc/hostapd/hostapd.conf >/dev/null <<EOF
country_code=$WIFI_COUNTRY
ieee80211d=1
interface=$WLAN
driver=nl80211
ssid=$SSID
hw_mode=a
channel=36
ieee80211n=1
ht_capab=[HT40+][SHORT-GI-20][SHORT-GI-40]
ieee80211ac=1
vht_capab=[SHORT-GI-80]
vht_oper_chwidth=1
vht_oper_centr_freq_seg0_idx=42
wmm_enabled=1
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$WIFI_PASS
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF
else
    tee /etc/hostapd/hostapd.conf >/dev/null <<EOF
country_code=$WIFI_COUNTRY
ieee80211d=1
interface=$WLAN
driver=nl80211
ssid=$SSID
hw_mode=g
channel=6
ieee80211n=1
ht_capab=[SHORT-GI-20]
wmm_enabled=1
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$WIFI_PASS
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF
fi
chmod 600 /etc/hostapd/hostapd.conf
sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

{
    echo "interface=$WLAN"
    echo "bind-dynamic"
    echo "dhcp-range=$DHCP_START,$DHCP_END,255.255.255.0,24h"
    echo "dhcp-option=option:router,$PI_IP"
    echo "dhcp-option=option:dns-server,$PI_IP"
    echo "domain-needed"
    echo "bogus-priv"
    echo "no-resolv"
    echo "address=/$LAN_NAME/$PI_IP"
    if [[ "$LAN_NAME" != "media.lan" ]]; then
        echo "address=/media.lan/$PI_IP"   # the guide's original name, kept as an alias
    fi
} > /etc/dnsmasq.d/ap.conf

systemctl unmask hostapd
systemctl daemon-reload
systemctl enable "${WLAN}-static" hostapd dnsmasq
ok "AP configured — it comes up at the final reboot (Ethernet/SSH unaffected)"

step "Car aux music player (MPD, fresh shuffle every boot)"
CONFIG_TXT="/boot/firmware/config.txt"
[[ -f "$CONFIG_TXT" ]] || CONFIG_TXT="/boot/config.txt"
grep -q '^dtparam=audio=on' "$CONFIG_TXT" || echo 'dtparam=audio=on' >> "$CONFIG_TXT"

if [[ -f /etc/mpd.conf && ! -f /etc/mpd.conf.bak ]]; then cp /etc/mpd.conf /etc/mpd.conf.bak; fi
tee /etc/mpd.conf >/dev/null <<'EOF'
music_directory     "/srv/media/music"
playlist_directory  "/var/lib/mpd/playlists"
db_file             "/var/lib/mpd/tag_cache"
state_file          "/var/lib/mpd/state"
sticker_file        "/var/lib/mpd/sticker.sql"

bind_to_address     "localhost"      # control API runs on the host; localhost is enough
port                "6600"

auto_update         "no"             # we scan at boot + on demand instead of watching files
restore_paused      "no"

audio_output {
    type        "alsa"
    name        "Aux jack"
    device      "plughw:CARD=Headphones"   # 'plug' prefix handles resampling
    mixer_type  "software"                  # lets the web buttons set volume reliably
}
EOF

tee /usr/local/bin/car-music-start.sh >/dev/null <<EOF
#!/usr/bin/env bash
# Build the queue, give it a fresh shuffle on EVERY start, loop forever, and play.
set -e
mpc -q clear
mpc -q update --wait      # refresh DB (slow only on first boot / after adding music)
mpc -q add /              # queue every track in natural order
mpc -q shuffle            # ONE fresh random order — re-runs on every boot/restart
mpc -q random off         # play straight through that order (no early repeats)
mpc -q repeat on          # loop the queue when it reaches the end
mpc -q volume $MUSIC_VOLUME
mpc -q play
EOF
chmod +x /usr/local/bin/car-music-start.sh

tee /etc/systemd/system/car-music-start.service >/dev/null <<'EOF'
[Unit]
Description=Shuffle-play the whole library on boot (aux jack)
After=mpd.service
Requires=mpd.service
RequiresMountsFor=/srv/media/music

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/sleep 2
ExecStart=/usr/local/bin/car-music-start.sh

[Install]
WantedBy=multi-user.target
EOF

install -m 0644 "$SCRIPT_DIR/car-music-web.py" /srv/car-music-web.py
tee /etc/systemd/system/car-music-web.service >/dev/null <<EOF
[Unit]
Description=Web music control API (MPD bridge)
After=mpd.service
Wants=mpd.service

[Service]
ExecStart=/usr/bin/python3 /srv/car-music-web.py
Restart=always
RestartSec=3
User=$RUN_USER

[Install]
WantedBy=multi-user.target
EOF

chmod -R a+rX /srv/media/music 2>/dev/null || true   # MPD runs as its own 'mpd' user and must read the library
systemctl daemon-reload
systemctl disable --now mpd.socket 2>/dev/null || true   # socket would override our bind address
systemctl enable mpd.service car-music-start.service car-music-web.service
ok "music starts by itself at boot, volume $MUSIC_VOLUME, controls on the dashboard (:8088)"

step "Dashboard power-off button (:8097)"
install -m 0644 "$SCRIPT_DIR/shutdown-server.py" /srv/shutdown-server.py
tee /etc/systemd/system/shutdown-server.service >/dev/null <<'EOF'
[Unit]
Description=Dashboard power-off button listener
After=network.target

[Service]
ExecStart=/usr/bin/python3 /srv/shutdown-server.py
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now shutdown-server.service
ok "power button live (runs as root on purpose — only reachable on the isolated car Wi-Fi)"

step "Writing the cheat-sheet"
RUN_HOME="$(getent passwd "$RUN_USER" | cut -d: -f6)"
SUMMARY_FILE="${RUN_HOME:-/root}/car-pi-info.txt"
tee "$SUMMARY_FILE" >/dev/null <<EOF
=====================================================================
 CAR-PI — $DEVICE_NAME            (built $(date '+%Y-%m-%d %H:%M'))
=====================================================================

WI-FI (in the car)
  Network:  $SSID
  Password: $WIFI_PASS
  Band:     $BAND_DESC
  Pi:       $PI_IP    (tablets get $DHCP_START-$DHCP_END by DHCP)

ON A TABLET JOINED TO "$SSID"
  Dashboard + music buttons ... http://$LAN_NAME    (or http://$PI_IP)
  Games arcade ................ http://$LAN_NAME/games/
  Jellyfin (video) ............ http://$LAN_NAME:8096
  Audiobookshelf .............. http://$LAN_NAME:13378
  Navidrome (music) ........... http://$LAN_NAME:4533
  Music control API ........... http://$PI_IP:8088/status
  Shutdown API ................ http://$PI_IP:8097  (POST /shutdown)

ADMIN
  Over Ethernet:  ssh $RUN_USER@$DEVICE_NAME.local
  Over car Wi-Fi: ssh $RUN_USER@$LAN_NAME
  Restart apps:   cd /srv && docker compose restart
  Setup log:      $LOG_FILE

STILL TO DO (one-time, in a browser; do it over Ethernet while the
Pi still has internet so metadata/artwork can download)
  1. Jellyfin  http://$DEVICE_NAME.local:8096 -> create admin, add
     libraries for /data/movies and /data/tvshows
  2. Audiobookshelf  http://$DEVICE_NAME.local:13378 -> create admin,
     add libraries for /audiobooks and /podcasts
  3. Navidrome  http://$DEVICE_NAME.local:4533 -> create admin
     (it scans /music automatically)
  4. Copy media in (pre-encode video per guide Part 6):
       /srv/media/movies   /srv/media/tv   /srv/media/music
       /srv/media/audiobooks   /srv/media/podcasts
  5. Hotel TV: install the Jellyfin app on a Fire TV / Google TV
     stick at home and pre-join it to "$SSID" (guide Part 5).

AFTER ADDING MUSIC LATER
  sudo chmod -R a+rX /srv/media/music
  mpc update --wait
  sudo systemctl restart car-music-start    # re-queue + fresh shuffle

HEALTH CHECKS
  systemctl status hostapd dnsmasq mpd car-music-start car-music-web shutdown-server
  cd /srv && docker compose ps
  iw dev $WLAN info               # AP channel/width
  vcgencmd get_throttled          # 0x0 = no heat/power trouble
  curl -s localhost:8088/status   # music API

NOTES
  * The car Wi-Fi has no internet (by design). No NTP means the clock
    drifts slowly; fake-hwclock keeps it roughly right across boots.
  * Shut down via the dashboard power button (or: sudo poweroff)
    before cutting power, to protect the SD card.
=====================================================================
EOF
chown "$PUID:$PGID" "$SUMMARY_FILE" 2>/dev/null || true
ok "cheat-sheet saved: $SUMMARY_FILE"

# ---------------------------------------------------------------- done ------
echo
echo "${BLD}${GRN}=====================================================${RST}"
echo "${BLD}${GRN} Car-Pi setup complete.${RST}"
echo "${BLD}${GRN}=====================================================${RST}"
cat "$SUMMARY_FILE"
echo
CURRENT_STEP="reboot"
if [[ "$AUTO_REBOOT" == "yes" ]]; then
    info "Rebooting in 10 seconds to bring up the '$SSID' access point..."
    info "(SSH over Ethernet keeps working after the reboot. See you at http://$LAN_NAME)"
    sleep 10
    reboot
else
    info "Reboot when ready to bring up the '$SSID' access point:  sudo reboot"
fi
