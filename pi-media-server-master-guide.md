# Raspberry Pi 4 — Offline Mobile Media Server (Master Build Guide)
 
A self-contained, **fully offline** media box for road trips. It broadcasts its own Wi-Fi and serves three media apps to the kids' tablets (and optionally a hotel TV). No internet required once it's built.
 
- **Jellyfin** — video
- **Audiobookshelf** — audiobooks & podcasts
- **Navidrome** — music (Subsonic-compatible)
```
                 ┌─────────────────────────────┐
                 │  Raspberry Pi 4 (4GB)        │
   Boys' tablets │   • Jellyfin        :8096    │
       ●   ●  ───┤   • Audiobookshelf  :13378   │
   (+ hotel TV)  │   • Navidrome       :4533    │
                 │   • Homepage        :80 (opt)│
                 │                              │
                 │  Built-in Wi-Fi (wlan0)     │
                 │   = access point "RoadTrip"  │
                 │   5GHz, 192.168.4.1          │
                 └─────────────────────────────┘
   USB Wi-Fi adapter: NOT used in this offline design — leave it unplugged.
```
 
> **Important sequencing:** the *build* needs internet (apt updates, Docker install, pulling the app images, first-run metadata). Do all of that **over Ethernet** if you can — that way configuring the built-in Wi-Fi as an access point later won't cut off your connection mid-setup. After it's built, it runs with no internet at all.
 
**Quick reference**
 
| Thing | Value |
|---|---|
| Pi address (on its own Wi-Fi) | `192.168.4.1` |
| Jellyfin | `http://192.168.4.1:8096` |
| Audiobookshelf | `http://192.168.4.1:13378` |
| Navidrome | `http://192.168.4.1:4533` |
| Homepage (optional) | `http://192.168.4.1` |
| Wi-Fi network | SSID `RoadTrip`, 5GHz channel 36 |
| Tablet DHCP range | `192.168.4.10`–`192.168.4.50` |
 
---
 
## Hardware
 
- Raspberry Pi 4 (4GB) + a case **with a fan or large heatsink** (a summer car is hot; the Pi 4 throttles)
- A quality **5V/3A USB-C** power source (car PD adapter or a big power bank)
- A blank **microSD card** (32GB is plenty for OS + Docker + app config)
- A separate drive for the media library (storage "isn't an issue" — keep media off the OS card)
- Optional later: a **USB SSD** to clone the OS onto for durability (see Part 7)
---
 
## Part 1 — Operating System
 
### 1.1 Which OS
 
Use **Raspberry Pi OS Lite (64-bit)**.
 
- **Lite** (no desktop): it's a headless server run entirely over SSH, so a GUI is wasted RAM/storage/background processes.
- **64-bit**: the Pi 4 is a 64-bit chip; the Docker images for all three apps run on arm64, and memory handling beats 32-bit on a 4GB board.
In Raspberry Pi Imager it's under **"Raspberry Pi OS (other)" → Raspberry Pi OS Lite (64-bit)**. The current default is now **Trixie (Debian 13)** — fine for this build; everything here works identically on it. Bookworm is still selectable as "Legacy" if you ever want the more conservative option.
 
### 1.2 Flash with Raspberry Pi Imager
 
Before writing, open **Imager's gear / advanced options** (Ctrl+Shift+X) and set:
 
- **Hostname** (e.g. `mediapi`)
- **Enable SSH** (password or key)
- **Username & password** — note these; examples below assume user `pi` (adjust `PUID`/paths if different)
- **Set Wireless LAN country** — required, or Wi-Fi stays disabled
- (Optional) home Wi-Fi, only if you can't use Ethernet for setup
### 1.3 First boot
 
SSH in (over Ethernet ideally):
 
```bash
ssh pi@mediapi.local      # or the Pi's IP
```
 
Update and set basics:
 
```bash
sudo apt update && sudo apt full-upgrade -y
sudo timedatectl set-timezone America/New_York   # your timezone
sudo raspi-config nonint do_wifi_country US        # your country code
sudo reboot
```
 
---
 
## Part 2 — Identify the Wi-Fi interfaces
 
```bash
nmcli device status
for d in /sys/class/net/wlan*; do echo "$d -> $(basename $(readlink $d/device/driver))"; done
```
 
The interface on the **`brcmfmac`** driver is the **built-in** radio → this is the access point, assumed **`wlan0`** below. (The USB adapter isn't used in this offline build.) If your name differs, substitute throughout.
 
---
 
## Part 3 — Media services (Docker)
 
### 3.1 Install Docker
 
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker     # or log out and back in
```
 
> If the install script ever balks at the OS version on a brand-new Debian release, install Docker's repo manually instead — note this as an open item if it happens.
 
### 3.2 Folder layout
 
Adjust paths if your media lives on a separate mounted drive.
 
```bash
sudo mkdir -p /srv/media/{movies,tv,audiobooks,podcasts,music}
sudo mkdir -p /srv/config/{jellyfin,navidrome}
sudo mkdir -p /srv/config/audiobookshelf/{config,metadata}
sudo mkdir -p /srv/homepage
sudo chown -R 1000:1000 /srv      # match your user; check with: id
```
 
### 3.3 docker-compose.yml
 
```bash
nano /srv/docker-compose.yml
```
 
```yaml
services:
  jellyfin:
    image: lscr.io/linuxserver/jellyfin:latest
    container_name: jellyfin
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
    volumes:
      - /srv/config/jellyfin:/config
      - /srv/media/movies:/data/movies
      - /srv/media/tv:/data/tvshows
    ports:
      - "8096:8096"
    restart: unless-stopped
 
  audiobookshelf:
    image: ghcr.io/advplyr/audiobookshelf:latest
    container_name: audiobookshelf
    environment:
      - TZ=America/New_York
    volumes:
      - /srv/config/audiobookshelf/config:/config
      - /srv/config/audiobookshelf/metadata:/metadata
      - /srv/media/audiobooks:/audiobooks
      - /srv/media/podcasts:/podcasts
    ports:
      - "13378:80"
    restart: unless-stopped
 
  navidrome:
    image: deluan/navidrome:latest
    container_name: navidrome
    user: "1000:1000"
    environment:
      - ND_SCANSCHEDULE=1h
      - ND_LOGLEVEL=info
      - ND_SESSIONTIMEOUT=24h
      - TZ=America/New_York
    volumes:
      - /srv/config/navidrome:/data
      - /srv/media/music:/music:ro
    ports:
      - "4533:4533"
    restart: unless-stopped
 
  # OPTIONAL one-tap landing page for the kids (see 3.5)
  homepage:
    image: nginx:alpine
    container_name: homepage
    volumes:
      - /srv/homepage:/usr/share/nginx/html:ro
    ports:
      - "80:80"
    restart: unless-stopped
```
 
### 3.4 Start and do first-run setup
 
```bash
cd /srv
docker compose up -d
docker compose ps      # all should be running
```
 
While you still have internet, set each one up so it can fetch metadata:
 
- **Jellyfin** → `http://<pi-ip>:8096` — create admin, add libraries for `/data/movies` and `/data/tvshows`.
- **Audiobookshelf** → `http://<pi-ip>:13378` — create admin, add libraries for `/audiobooks` and `/podcasts`.
- **Navidrome** → `http://<pi-ip>:4533` — create admin; it auto-scans `/music`.
`restart: unless-stopped` brings everything back on every power-up.
 
### 3.5 Optional kid-friendly homepage
 
```bash
nano /srv/homepage/index.html
```
 
```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Road Trip Media</title>
<style>
  :root { color-scheme: dark; }
  body { margin:0; min-height:100vh; display:flex; flex-direction:column;
         align-items:center; justify-content:center; gap:1.5rem;
         font-family: system-ui, sans-serif; background:#0f1320; color:#fff; padding:2rem; }
  h1 { font-size:1.6rem; opacity:.85; margin:0 0 .5rem; }
  .grid { display:grid; gap:1.25rem; width:100%; max-width:480px; }
  a.card { display:flex; align-items:center; gap:1rem; text-decoration:none;
           padding:1.4rem 1.6rem; border-radius:1rem; color:#fff;
           font-size:1.35rem; font-weight:600; transition:transform .08s ease; }
  a.card:active { transform:scale(.97); }
  .video { background:#5a4fff; } .books { background:#1f8f6f; } .music { background:#c2563b; }
  .emoji { font-size:1.8rem; }
</style>
</head>
<body>
  <h1>What do you want to do?</h1>
  <div class="grid">
    <a class="card video" href="http://192.168.4.1:8096"><span class="emoji">🎬</span> Watch (Jellyfin)</a>
    <a class="card books" href="http://192.168.4.1:13378"><span class="emoji">🎧</span> Audiobooks</a>
    <a class="card music" href="http://192.168.4.1:4533"><span class="emoji">🎵</span> Music</a>
  </div>
</body>
</html>
```
 
`http://192.168.4.1` now shows three big buttons.
 
---
 
## Part 4 — Offline Wi-Fi access point (hostapd + dnsmasq, 5GHz)
 
No uplink, no NAT — just an access point handing out addresses.
 
### 4.1 Install
 
```bash
sudo apt update
sudo apt install -y hostapd dnsmasq
sudo systemctl stop hostapd dnsmasq
```
 
### 4.2 Tell NetworkManager to leave wlan0 alone
 
```bash
sudo tee /etc/NetworkManager/conf.d/99-unmanaged-wlan0.conf >/dev/null <<'EOF'
[keyfile]
unmanaged-devices=interface-name:wlan0
EOF
sudo systemctl reload NetworkManager
```
 
(NetworkManager still manages `eth0`, so you can keep SSHing in over Ethernet.)
 
### 4.3 Static IP for wlan0 at boot
 
```bash
sudo tee /etc/systemd/system/wlan0-static.service >/dev/null <<'EOF'
[Unit]
Description=Static IP for wlan0 access point
After=sys-subsystem-net-devices-wlan0.device
Wants=sys-subsystem-net-devices-wlan0.device
Before=hostapd.service dnsmasq.service
 
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=-/sbin/ip addr flush dev wlan0
ExecStart=/sbin/ip addr add 192.168.4.1/24 dev wlan0
ExecStart=/sbin/ip link set wlan0 up
 
[Install]
WantedBy=multi-user.target
EOF
```
 
### 4.4 hostapd — 5GHz / 802.11ac (change SSID, password, country)
 
This pins the AP to **channel 36 at 80MHz**, which is the reliably-working 5GHz AP channel on the Pi 4's onboard radio.
 
```bash
sudo tee /etc/hostapd/hostapd.conf >/dev/null <<'EOF'
country_code=US
ieee80211d=1
interface=wlan0
driver=nl80211
ssid=RoadTrip
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
wpa_passphrase=ChangeThisPassword
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF
```
 
Point the service at the file:
 
```bash
sudo sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
```
 
Notes:
- `vht_oper_centr_freq_seg0_idx=42` is the correct center index **for channel 36** — don't change it unless you change the channel.
- There is deliberately **no `ap_isolate`** line, so tablets and a TV device on this network can see each other (needed if you ever cast).
- **Reality check:** the Pi 4's single-antenna radio tops out around ~130 Mbps real-world even at 80MHz — still 5–10× a 1080p stream, fine for several tablets, just not gigabit.
- **2.4GHz fallback** (if you ever need range over speed): set `hw_mode=g`, `channel=6`, and delete the three `ieee80211ac`/`vht_*` lines.
### 4.5 dnsmasq — DHCP for the tablets
 
```bash
sudo tee /etc/dnsmasq.d/ap.conf >/dev/null <<'EOF'
interface=wlan0
bind-dynamic
dhcp-range=192.168.4.10,192.168.4.50,255.255.255.0,24h
dhcp-option=option:router,192.168.4.1
dhcp-option=option:dns-server,192.168.4.1
domain-needed
bogus-priv
no-resolv
address=/media.lan/192.168.4.1
EOF
```
 
### 4.6 Enable, reboot, verify
 
```bash
sudo rfkill unblock wlan
sudo systemctl unmask hostapd
sudo systemctl enable wlan0-static hostapd dnsmasq
sudo reboot
```
 
After reboot:
 
```bash
sudo systemctl status hostapd dnsmasq   # both active (running)
ip addr show wlan0                        # shows 192.168.4.1/24
iw dev wlan0 info                         # confirm: channel 36, width 80 MHz
```
 
Tablets should now see **RoadTrip**, connect, get a `192.168.4.x` address, and reach the apps at `192.168.4.1` — all offline.
 
---
 
## Part 5 — Getting a TV/screen working in a hotel
 
**A plain, cast-only Chromecast is the wrong tool for an offline setup**, for two reasons: setup needs internet, and — the real blocker — when you cast, the Chromecast downloads the receiver app from the internet *at cast time*, so with no connection the cast fails even on the same LAN.
 
**What works offline: a device that runs the Jellyfin app itself** (Fire TV Stick, Chromecast *with Google TV*, Android TV box, Apple TV, or a smart TV with a Jellyfin app):
 
1. Set it up on **home Wi-Fi** and install **Jellyfin** (and optionally VLC) while you have internet.
2. With the Pi powered on nearby, add the **RoadTrip** network to the device's Wi-Fi list (accept the "no internet" warning).
3. At the hotel it auto-joins RoadTrip; open Jellyfin → `http://192.168.4.1:8096`. It streams straight from the Pi — no casting, no internet.
**Fallback trick** for a stubborn device that won't join a no-internet network: set the Pi's AP SSID/password to **match the home network you set the device up on**, so it auto-joins thinking it's home.
 
**Simplest fallback of all:** an HDMI cable from a tablet with video-out, or just watch on the tablets. Worth keeping one in the bag.
 
---
 
## Part 6 — Preparing your video library (encode for "direct play")
 
Jellyfin streams effortlessly **as long as it doesn't transcode**. Convert video to **H.264 (8-bit) + AAC in MP4** ahead of time so the Pi just sends the file. Avoid handing it 4K/HEVC/10-bit and expecting on-the-fly transcoding.
 
Do this **on a real computer before the trip**, then copy the results into `/srv/media/movies` (or `tv`). The script below remuxes (copies, seconds) anything already compatible and only re-encodes what needs it. It's also saved as `batch-encode.sh`.
 
```bash
#!/usr/bin/env bash
# batch-encode.sh — convert a folder of videos to Jellyfin "direct play"
# (H.264 8-bit yuv420p + AAC stereo MP4). Already-compatible files are remuxed.
# Run on a normal computer (macOS/Linux/WSL), NOT the Pi. Needs ffmpeg + ffprobe.
# Usage: ./batch-encode.sh /path/to/source /path/to/output   (defaults: ./input ./output)
 
set -uo pipefail
INPUT_DIR="${1:-./input}"
OUTPUT_DIR="${2:-./output}"
CRF=20; PRESET=medium; MAXHEIGHT=1080; ABITRATE=192k
 
command -v ffmpeg  >/dev/null || { echo "ffmpeg not found";  exit 1; }
command -v ffprobe >/dev/null || { echo "ffprobe not found"; exit 1; }
[[ -d "$INPUT_DIR" ]] || { echo "input dir not found: $INPUT_DIR"; exit 1; }
mkdir -p "$OUTPUT_DIR"
total=0; remuxed=0; encoded=0; skipped=0; failed=0
 
while IFS= read -r -d '' f; do
  total=$((total+1))
  rel="${f#"$INPUT_DIR"/}"; out="$OUTPUT_DIR/${rel%.*}.mp4"
  mkdir -p "$(dirname "$out")"
  if [[ -f "$out" ]]; then echo "SKIP   (exists): $rel"; skipped=$((skipped+1)); continue; fi
 
  vcodec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$f" 2>/dev/null)
  acodec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$f" 2>/dev/null)
  pixfmt=$(ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt   -of csv=p=0 "$f" 2>/dev/null)
 
  if [[ "$vcodec" == "h264" && "$pixfmt" == "yuv420p" ]]; then
    if [[ "$acodec" == "aac" ]]; then
      echo "REMUX  (copy A+V): $rel"
      ffmpeg -nostdin -loglevel error -stats -i "$f" -map 0:v:0 -map 0:a:0? \
        -c copy -movflags +faststart "$out" \
        && remuxed=$((remuxed+1)) || { echo "  ^ FAILED"; rm -f "$out"; failed=$((failed+1)); }
    else
      echo "REMUX  (copy video, AAC audio): $rel"
      ffmpeg -nostdin -loglevel error -stats -i "$f" -map 0:v:0 -map 0:a:0? \
        -c:v copy -c:a aac -b:a "$ABITRATE" -ac 2 -movflags +faststart "$out" \
        && remuxed=$((remuxed+1)) || { echo "  ^ FAILED"; rm -f "$out"; failed=$((failed+1)); }
    fi
  else
    echo "ENCODE (-> H.264/AAC): $rel"
    ffmpeg -nostdin -loglevel error -stats -i "$f" -map 0:v:0 -map 0:a:0? \
      -c:v libx264 -preset "$PRESET" -crf "$CRF" -profile:v high -level 4.1 -pix_fmt yuv420p \
      -vf "scale=-2:'min($MAXHEIGHT,ih)'" -c:a aac -b:a "$ABITRATE" -ac 2 \
      -movflags +faststart "$out" \
      && encoded=$((encoded+1)) || { echo "  ^ FAILED"; rm -f "$out"; failed=$((failed+1)); }
  fi
done < <(find "$INPUT_DIR" -type f \( \
      -iname '*.mkv'  -o -iname '*.mp4'  -o -iname '*.m4v'  -o -iname '*.avi'  \
   -o -iname '*.mov'  -o -iname '*.wmv'  -o -iname '*.flv'  -o -iname '*.ts'   \
   -o -iname '*.webm' -o -iname '*.mpg'  -o -iname '*.mpeg' -o -iname '*.m2ts' \
   \) -print0)
 
echo; echo "Done. $total found -> $remuxed remuxed, $encoded re-encoded, $skipped skipped, $failed failed."
```
 
Make it executable and run it:
 
```bash
chmod +x batch-encode.sh
./batch-encode.sh /path/to/source /path/to/output
```
 
Notes:
- Drops embedded subtitles to keep MP4s clean. Drop a matching `MovieName.srt` next to `MovieName.mp4` and Jellyfin still uses it.
- GUI alternative: HandBrake with the **"Fast 1080p30"** preset.
---
 
## Part 7 — Heat, power, and the SD card
 
- **Cooling:** fan or large heatsink. Check throttling: `vcgencmd get_throttled` (`0x0` = good).
- **Power:** a genuine 5V/3A supply. Cheap car USB ports often can't hold 3A and cause under-volt instability (same command flags it).
- **SD card durability:** an SD card in a hot car with the occasional yanked power cable is the single most likely failure point. Mitigate by shutting down cleanly (`sudo poweroff`) and keeping media on a separate drive. For belt-and-suspenders, **clone the finished card onto a USB SSD and boot from that** — identical setup, far more resilient.
---
 
## Part 8 — Day-to-day usage
 
- **Tablets:** join Wi-Fi **RoadTrip**, then use the apps. Works in the car with zero internet.
- **Best experience = native apps**, each pointed at the Pi:
  - Jellyfin app (or Findroid) → `http://192.168.4.1:8096`
  - Audiobookshelf app → `http://192.168.4.1:13378`
  - Any Subsonic client (Symfonium, Substreamer, DSub) → `http://192.168.4.1:4533`
- **Administering the Pi:** SSH over Ethernet, or connect a device to RoadTrip and `ssh pi@192.168.4.1`.
- **Restart services:** `cd /srv && docker compose restart` (or a single one, e.g. `... restart jellyfin`).
---
 
## Troubleshooting
 
- **Wi-Fi won't enable / no AP:** Wi-Fi country not set → `sudo raspi-config nonint do_wifi_country US`, reboot.
- **hostapd won't start on 5GHz:** check `sudo journalctl -u hostapd -b --no-pager | tail -30`. Fall back to 40MHz (set `vht_oper_chwidth=0`, delete the `vht_oper_centr_freq_seg0_idx` line), or drop the three `ac`/`vht` lines for plain 5GHz 802.11n.
- **Tablets connect but get no IP:** confirm `dnsmasq` is active and `ip addr show wlan0` shows `192.168.4.1/24`.
- **dnsmasq fails on port 53:** that's `systemd-resolved`; `bind-dynamic` normally avoids it — note as an open item if it recurs.
- **Service won't load:** `cd /srv && docker compose logs <name>`.
- **Permission errors:** `sudo chown -R 1000:1000 /srv`; confirm your user is `1000` with `id`.
- **Playback stutters:** check `vcgencmd get_throttled` (heat/power) and confirm Jellyfin shows "Direct Play," not "Transcode" (Dashboard → Active Devices).
- **Interface names swapped after reboot:** pin by MAC with `.link` files, or rebuild the config against the current names from `nmcli device status`.
---
 
## Open items / future updates
 
- [ ] Set the real SSID, Wi-Fi password, and `country_code` (currently placeholders / `US`).
- [ ] Decide on the hotel-TV device (Fire TV Stick etc.) and pre-install Jellyfin on it at home.
- [ ] Populate the media library and run `batch-encode.sh` over the video.
- [ ] Decide whether to clone the OS to a USB SSD for durability.
- [ ] Optional: add a small RTC module if clock drift (no internet = no NTP) ever becomes annoying.
- [ ] Note any Docker-repo or hostapd quirks encountered during the actual build here.