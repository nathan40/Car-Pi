# Raspberry Pi 4 — Offline Mobile Media Server (Master Build Guide)
 
A self-contained, **fully offline** media box for road trips. It broadcasts its own Wi-Fi and serves media apps plus a kids' games arcade to the kids' tablets (or a device hooked up to a TV). No internet required once it's built.
 
- **Jellyfin** — video
- **Audiobookshelf** — audiobooks & podcasts
- **Navidrome** — music (Subsonic-compatible)
- **Homepage** — Web dashboard, car-aux music player controls, a 12-game offline arcade, and a power-off button (Parts 9–10)
```
                   ┌──────────────────────────────┐
                   │  Raspberry Pi 4 (4GB)        │
   kids' tablets   │   • Jellyfin        :8096    │
       ●   ●  ─────┤   • Audiobookshelf  :13378   │
(+ media devices)  │   • Navidrome       :4533    │
                   │   • Homepage        :80      │
                   │                              │
                   │  Built-in Wi-Fi (wlan0)      │
                   │   = access point "RoadTrip"  │
                   │   5GHz, 192.168.4.1          │
                   └──────────────────────────────┘
```
 
> **Important sequencing:** the *build* needs internet (apt updates, Docker install, pulling the app images, first-run metadata). Do all of that **over Ethernet** if you can — that way configuring the built-in Wi-Fi as an access point later won't cut off your connection mid-setup. After it's built, it runs with no internet at all.
 
**Quick reference**

Pi address (on its own Wi-Fi)   `192.168.4.1`
Pi URL (on its own Wi-Fi)       `media.lan`
Jellyfin                        `http://media.lan:8096`
Audiobookshelf                  `http://media.lan:13378`
Navidrome                       `http://media.lan:4533`
Homepage                        `http://media.lan`
Games arcade                    `http://media.lan/games/` (12 games, alphabetized by kids as they're added)
Music control API               `http://media.lan:8088` (Part 9)
Shutdown button API              `http://media.lan:8097` (Part 10)
Wi-Fi network                   SSID `RoadTrip`, 5GHz channel 36
Tablet DHCP range               `192.168.4.100`–`192.168.4.200`
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
see docker-compose.yml file in folder

Four services: `jellyfin`, `audiobookshelf`, `navidrome`, and `homepage` (`php:8-apache`, serves the dashboard + games arcade on port 80). `homepage` mounts `/srv/homepage` read-only at the web root, plus a second, **writable** mount at `/srv/config/arcade-state` → `/var/www/state` for any game's shared state (Car Bingo's `bingo.json`, the arcade profiles/stars `arcade.json`, and any future game's scores/stats — every PHP game just writes its own JSON file into this same folder) (Part 10) — create that folder before first `up`, see §3.5.
 
### 3.4 Start and do first-run setup
 
```bash
cd /srv
docker compose up -d
docker compose ps      # all should be running
```
 
`setup.sh` auto-creates the admin account **and** the media libraries for all three via each app's API, using the **same login everywhere** (`admin` / `carpi` — Jellyfin rejects a blank password, so a shared non-blank password is used for all three rather than mixing blank and non-blank): Jellyfin gets libraries `Movies` (`/data/movies`) and `TV Shows` (`/data/tvshows`); Audiobookshelf gets `Audiobooks` (`/audiobooks`) and `Podcasts` (`/podcasts`); Navidrome gets an immediate scan of `/music` right after its admin account is created (via the Subsonic `startScan` endpoint), then continues on its normal `ND_SCANSCHEDULE` (hourly). This is deliberately insecure — fine for a box that's offline and only reachable on its own isolated car Wi-Fi. While you still have internet, log in to each once so it can fetch metadata:
 
- **Jellyfin** → `http://<pi-url>:8096` — log in; libraries are already there.
- **Audiobookshelf** → `http://<pi-url>:13378` — log in; libraries are already there.
- **Navidrome** → `http://<pi-url>:4533` — log in; `/music` has already been scanned.

(If an admin account from before this feature existed is still in place with a different password, `setup.sh` can't log back in to add libraries/trigger a scan automatically — it warns and you do that step by hand once, same as a first-time install.)
`restart: unless-stopped` brings everything back on every power-up.
 
### 3.5 Optional kid-friendly homepage
 
```bash
nano /srv/homepage/index.html
```
see updated html file in homepage/index.html
 
`http://media.lan` now shows three big buttons (a fourth, **Games**, and a power-off button are added in Part 10; the music player panel is added in Part 9).

Create the writable bingo-state folder mentioned in §3.3 now, so `docker compose up -d` doesn't fail on a missing path:

```bash
sudo mkdir -p /srv/config/arcade-state
sudo chown -R 33:33 /srv/config/arcade-state   # 33 = www-data inside the php:8-apache image
```
 
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
dhcp-range=192.168.4.100,192.168.4.200,255.255.255.0,24h
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
3. At the hotel it auto-joins RoadTrip; open Jellyfin → `http://media.lan:8096`. It streams straight from the Pi — no casting, no internet.
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
  - Jellyfin app (or Findroid) → `http://media.lan:8096`
  - Audiobookshelf app → `http://media.lan:13378`
  - Any Subsonic client (Symfonium, Substreamer, DSub) → `http://media.lan:4533`
- **Administering the Pi:** SSH over Ethernet, or connect a device to RoadTrip and `ssh pi@media.lan`.
- **Restart services:** `cd /srv && docker compose restart` (or a single one, e.g. `... restart jellyfin`).
---

## Part 9 — Auto-shuffle music to the car aux + web control

Play your music library out the Pi's **3.5mm aux jack** into the car stereo. It starts automatically on power-up, gives every track a **fresh random order on every boot**, plays straight through that order (so nothing repeats until the whole library has played), and the kids get a few big buttons on the existing landing page.

This is separate from the per-tablet music: the **Music (Navidrome)** card still streams to headphones/tablets, while this aux stream drives the **car speakers**. MPD reads the same `/srv/media/music` folder Navidrome uses (both read-only), so they run at the same time without conflict.

> **Sequencing:** Step 1 needs internet (it installs packages) — do it over Ethernet like the rest of the build. Everything after that is offline. Run the steps top to bottom; the only reboot is at the very end (Step 10).

### What this changes on the Pi

- **Installs:** `mpd`, `mpc`
- **New files:**
  - `/etc/mpd.conf` (original backed up to `/etc/mpd.conf.bak`)
  - `/usr/local/bin/car-music-start.sh`
  - `/etc/systemd/system/car-music-start.service`
  - `/srv/car-music-web.py`
  - `/etc/systemd/system/car-music-web.service`
  - `/srv/homepage/index.html` (replaces the one from §3.5)
- **New services (enabled at boot):** `mpd`, `car-music-start`, `car-music-web`
- **Ensures** `dtparam=audio=on` in `/boot/firmware/config.txt`

### New quick reference

| Thing | Value |
|---|---|
| Car audio out | Pi 4 onboard **3.5mm aux jack** |
| Music engine | **MPD** on the host, `localhost:6600` |
| Web control API | `http://192.168.4.1:8088` |
| Player controls | on the homepage at `http://192.168.4.1` |

---

### Step 1 — Install MPD and the CLI client *(needs internet)*

```bash
sudo apt update
sudo apt install -y mpd mpc        # mpd = player daemon, mpc = CLI client
sudo systemctl stop mpd
```

### Step 2 — Make sure the analog audio device is enabled

Pi OS **Lite** has no desktop audio server, so MPD talks straight to ALSA. This makes sure the onboard DAC is on (takes effect at the Step 10 reboot):

```bash
grep -q '^dtparam=audio=on' /boot/firmware/config.txt \
  || echo 'dtparam=audio=on' | sudo tee -a /boot/firmware/config.txt
```

### Step 3 — Point MPD at the aux jack

```bash
sudo cp /etc/mpd.conf /etc/mpd.conf.bak
sudo tee /etc/mpd.conf >/dev/null <<'EOF'
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
```

### Step 4 — Make the music library readable by MPD

MPD runs as user `mpd`; this guarantees it can read your files no matter how they were copied in:

```bash
sudo chmod -R a+rX /srv/media/music
```

### Step 5 — Boot script: fresh shuffle every start

```bash
sudo tee /usr/local/bin/car-music-start.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
# Build the queue, give it a fresh shuffle on EVERY start, loop forever, and play.
set -e
mpc -q clear
mpc -q update --wait      # refresh DB (slow only on first boot / after adding music)
mpc -q add /              # queue every track in natural order
mpc -q shuffle            # ONE fresh random order — re-runs on every boot/restart
mpc -q random off         # play straight through that order (no early repeats)
mpc -q repeat on          # loop the queue when it reaches the end
mpc -q volume 80          # sane default level; car knob + buttons adjust from here
mpc -q play
EOF
sudo chmod +x /usr/local/bin/car-music-start.sh
```

### Step 6 — Service to run that script at boot

```bash
sudo tee /etc/systemd/system/car-music-start.service >/dev/null <<'EOF'
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
```

### Step 7 — Web control API and its service

The control server is ~30 lines of Python (stdlib only — nothing to install). It only ever runs a fixed set of `mpc` commands, so no user input reaches the shell.

```bash
sudo tee /srv/car-music-web.py >/dev/null <<'EOF'
#!/usr/bin/env python3
# car-music-web.py — minimal MPD control API for the kids' landing page.
# Serves JSON on :8088 and drives MPD on localhost:6600 via the `mpc` CLI.
import json
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

def mpc(*args):
    return subprocess.run(["mpc", *args], capture_output=True, text=True).stdout.strip()

def status():
    now = mpc("current")            # "Artist - Title"  ("" when stopped)
    raw = mpc("status")             # multiline status block
    state = ("playing" if "[playing]" in raw else
             "paused"  if "[paused]"  in raw else "stopped")
    volume = ""
    for line in raw.splitlines():
        if "volume:" in line:
            volume = line.split("volume:")[1].split()[0]   # e.g. "80%"
            break
    return {"state": state, "now": now, "volume": volume}

def handle(path):
    if   path == "/toggle":  mpc("toggle")
    elif path == "/next":    mpc("next")
    elif path == "/prev":    mpc("prev")
    elif path == "/volup":   mpc("volume", "+5")
    elif path == "/voldown": mpc("volume", "-5")
    elif path != "/status":  return None
    return status()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        result = handle(self.path.split("?")[0])
        body = json.dumps(result if result is not None else {"error": "not found"}).encode()
        self.send_response(200 if result is not None else 404)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")   # page is on :80, API on :8088
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *_):   # stay quiet in the journal
        pass

if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8088), Handler).serve_forever()
EOF
```

```bash
sudo tee /etc/systemd/system/car-music-web.service >/dev/null <<'EOF'
[Unit]
Description=Web music control API (MPD bridge)
After=mpd.service
Wants=mpd.service

[Service]
ExecStart=/usr/bin/python3 /srv/car-music-web.py
Restart=always
RestartSec=3
User=pi

[Install]
WantedBy=multi-user.target
EOF
```

> If your Pi username isn't `pi`, change `User=pi` above to match.

### Step 8 — Enable everything (starts at the Step 10 reboot)

```bash
sudo systemctl daemon-reload
sudo systemctl disable --now mpd.socket 2>/dev/null || true   # avoid socket overriding the bind address
sudo systemctl enable mpd.service car-music-start.service car-music-web.service
```

### Step 9 — Add the player to the homepage

This replaces the `index.html` from **§3.5** — it keeps your app cards and adds a player panel underneath. It's bind-mounted into the Apache container, so saving the file is enough; no container restart needed.

```bash
nano /srv/homepage/index.html
```
see updated file in homepage/index.html 

The panel shows the current track and refreshes every few seconds. The buttons control the **car-speaker** stream; the volume buttons nudge MPD's digital level ±5 (the car's own knob stays the main control).

### Step 10 — Reboot and verify

```bash
sudo reboot
```

After it comes back up — with the aux cable plugged into the car (or a test speaker):

1. Music should be **playing out the aux jack on its own**, no login.
2. On a tablet joined to **RoadTrip**, open `http://media.lan` — the player panel shows the current song and the buttons skip / pause / adjust volume.

Health checks if anything looks off:

```bash
systemctl status mpd car-music-start car-music-web --no-pager
mpc status                         # shows the track, random: off, repeat: on
curl -s localhost:8088/status      # -> {"state":"playing","now":"...","volume":"80%"}
```

> **First boot is slower:** `mpc update --wait` builds the library database the first time, so there's a short delay before the first track on the very first boot only. Subsequent boots are quick.

---

### Adding music later

Drop files into `/srv/media/music`, then either reboot, or without rebooting:

```bash
sudo chmod -R a+rX /srv/media/music   # keep new files readable by MPD
mpc update --wait
sudo systemctl restart car-music-start    # re-queue + fresh shuffle including the new tracks
```

Navidrome picks up the same new files on its own schedule (per §3.3).

### How the shuffle behaves (and a note on "random")

`mpc shuffle` physically reorders the queue, so you get a **brand-new order every boot or restart**, regardless of saved state. Because playback then runs straight through that order (`random off`) and only loops at the end (`repeat on`), **no song repeats until the entire library has played once**. The only way to hear a repeat is to drive longer than your whole library is long — hours and hours — and even then it replays the same shuffled order rather than picking favourites. This avoids the "same song keeps coming up" feel of roll-the-dice random.

If you ever wanted it to reshuffle *again* after each complete pass (instead of looping the same order), swap the two lines in `car-music-start.sh` to `mpc -q random on` and drop the `mpc -q shuffle` line. For a road trip, the version above is the better fit.

### Troubleshooting (Part 9)

- **No sound at all:** confirm `aplay -l` lists the **Headphones** card and that `/boot/firmware/config.txt` has `dtparam=audio=on` (reboot if you just added it). Check MPD's output is enabled: `mpc outputs` → if it shows disabled, `mpc enable 1`.
- **Sound goes out HDMI, not the jack:** set `device` in `/etc/mpd.conf` to the exact card name from `aplay -l`, then `sudo systemctl restart mpd`.
- **Library looks empty / `add /` queues nothing:** `mpc update --wait`, then `mpc add /`. If still empty, it's a permissions issue: `sudo chmod -R a+rX /srv/media/music` and update again.
- **Player panel says "(music control offline)":** on the Pi, `curl -s localhost:8088/status` and `systemctl status car-music-web`. Make sure `User=` in the service matches a real user.
- **Volume buttons do nothing:** confirm `mixer_type "software"` is in `/etc/mpd.conf`, then `sudo systemctl restart mpd`.
- **Want native phone control too:** add a second `bind_to_address "192.168.4.1"` line to `/etc/mpd.conf`, restart MPD, and point any MPD client at `192.168.4.1:6600`.

---

## Part 10 — Games arcade + dashboard power-off button

Two more additions on top of the homepage from Parts 3 and 9: a **Games** tile leading to a 12-game offline arcade, and a subtle **power-off button** on the dashboard so the kids (or a hotel room) can shut the Pi down safely without SSH.

### What this changes on the Pi

- **New files:**
  - `/srv/homepage/games/` — one self-contained `.html` per game, plus `games/index.html` (the arcade hub), `games/bingo.html`, and `games/bingo-api.php`
  - `/srv/shutdown-server.py`
  - `/etc/systemd/system/shutdown-server.service`
  - `/srv/homepage/index.html` (adds the **Games** card and the power button; replaces the one from Part 9)
- **New service (enabled at boot):** `shutdown-server`
- **Uses the existing** `/srv/config/arcade-state` → `/var/www/state` mount from §3.3/§3.5 (no new volume)

### New quick reference

| Thing | Value |
|---|---|
| Games hub | `http://media.lan/games/` |
| Shutdown API | `http://192.168.4.1:8097` (`GET /` = health check, `POST /shutdown` = power off) |
| Games state (Bingo) | `/srv/config/arcade-state/bingo.json`, mounted read/write into the `homepage` container at `/var/www/state` |

### 10.1 The games hub

`games/index.html` is a grid of 12 tiles, each linking to one self-contained game file — no build step, no shared JS engine, just static HTML/CSS/JS served by the existing `homepage` (`php:8-apache`) container:

| Tile | File | Notes |
|---|---|---|
| 🫧 Bubbles | `bubbles.html` | |
| 🎆 Fireworks | `fireworks.html` | |
| 🎵 Xylophone | `xylophone.html` | |
| 🐶 Animal Sounds | `animals.html` | |
| 🖍️ Paint | `paint.html` | |
| 👾 Feed Me! | `monster.html` | |
| 🐹 Bonk! | `whack.html` | |
| 🔷 Shapes | `shapes.html` | |
| 🚗 Vroom! | `racer.html` | |
| 🃏 Memory | `memory.html` | |
| 🚌 Car Bingo | `bingo.html` + `bingo-api.php` | the only game with server-side shared state |
| 🔤 Spell It! | `words.html` | |

```bash
sudo mkdir -p /srv/homepage/games
# copy each game .html into /srv/homepage/games/, index.html into /srv/homepage/games/,
# and bingo.html + bingo-api.php into /srv/homepage/games/ (flat, same folder as every other game)
```

Everything under `/srv/homepage` is served read-only (per the `homepage` service's `:ro` mount in §3.3), so no extra permissions are needed for the static game files themselves.

**Car Bingo's shared state.** `bingo-api.php` is a small stdlib-only PHP API (`state | claim | mark | newgame | reset`) that deals a 4×16 tile "Minnesota road trip" card per player and tracks marks/wins in a flock-locked JSON file at `/var/www/state/bingo.json` — i.e. the `/srv/config/arcade-state` folder created in §3.5. Up to 4 tablets can claim a player slot and mark tiles independently; the server itself detects bingo lines (4 rows, 4 columns, 2 diagonals) so kids can't fudge a win. The tile pool (deer, tractors, rest stops, etc.) is a plain PHP array at the top of the file — edit it to match wherever you're actually driving.

### 10.2 Dashboard power-off button

`shutdown-server.py` is a ~35-line stdlib Python service, run **as root** by systemd so it can actually halt the host:

```bash
sudo tee /srv/shutdown-server.py >/dev/null <<'EOF'
#!/usr/bin/env python3
# /srv/shutdown-server.py
# Listener for the dashboard "Power off" button.
#   GET  /          -> health check (does nothing)
#   POST /shutdown  -> cleanly powers off the Pi
# Runs as root via systemd so it can actually halt the host.

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import subprocess, threading, time

PORT = 8097

def poweroff():
    time.sleep(1)                      # let the reply reach the tablet first
    subprocess.run(["systemctl", "poweroff"])

class Handler(BaseHTTPRequestHandler):
    def reply(self, code, body=b""):
        self.send_response(code)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):     self.reply(200, b"shutdown-button: ok\n")
    def do_OPTIONS(self): self.reply(204)

    def do_POST(self):
        if self.path.rstrip("/") == "/shutdown":
            self.reply(200, b"Shutting down\n")
            threading.Thread(target=poweroff, daemon=True).start()
        else:
            self.reply(404, b"not found\n")

    def log_message(self, *a):         # stay quiet in the journal
        pass

ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
EOF
```

```bash
sudo tee /etc/systemd/system/shutdown-server.service >/dev/null <<'EOF'
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
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now shutdown-server.service
```

> Runs as root deliberately (only `systemctl poweroff` needs it) — the API has no auth of its own, which is fine since it's only reachable on the isolated RoadTrip AP.

### 10.3 Homepage changes

`/srv/homepage/index.html` gains:
- A **Games** card (4th card, alongside Watch/Audiobooks/Music) linking to `/games/`.
- A subtle, low-opacity **⏻ power button** in the top-left corner (`title="System Settings"`, opacity 0.25 until tapped/hovered) — deliberately unobtrusive so it isn't mashed by accident.
- An **adult-verification gate**: tapping ⏻ opens a dialog with a randomly generated addition problem (two numbers 11–25); only a correct answer reveals the "Shut down" confirm button. Wrong answers show an inline error and reset the input; the dialog can be cancelled or dismissed by tapping outside it.
- On confirm, it `POST`s to `http://<pi-ip>:8097/shutdown` and shows a "Shutting down… wait for the green light to stop blinking" message. If the shutdown-server is unreachable, it shows a fallback message instead of hanging.
- The existing "open in native app, fall back to web" logic (`openMedia()`) for Jellyfin/Audiobookshelf/Navidrome cards is unchanged from Part 3/9.

```bash
nano /srv/homepage/index.html
```
see updated file in homepage/index.html

### 10.4 Verify

```bash
curl -s http://192.168.4.1:8097/            # -> shutdown-button: ok
systemctl status shutdown-server --no-pager
```

On a tablet joined to RoadTrip:
1. Open `http://media.lan` → tap **Games** → hub loads with all 12 tiles.
2. Tap **Car Bingo**, claim a player slot, mark a tile — reload on a second tablet and confirm the mark synced (shared state via `bingo-api.php`).
3. Tap the faint ⏻ in the top-left → solve the addition prompt → **Shut down** → Pi's green activity LED should stop blinking within ~20 seconds.

### Troubleshooting (Part 10)

- **"Games" card 404s:** confirm files landed under `/srv/homepage/games/` (not `/srv/games/`) — the container only serves `/srv/homepage`.
- **Bingo marks don't sync between tablets:** check `/srv/config/arcade-state` is owned by `33:33` (www-data) and writable; `bingo-api.php` returns an explicit `cannot open state file` error in its JSON if the mount is missing or read-only.
- **Power button does nothing / "Couldn't reach the media box":** `systemctl status shutdown-server`, and confirm port 8097 isn't blocked — there's no firewall in this build, so this is almost always the service not running.
- **Pi doesn't actually power off:** `shutdown-server` must run as **root** (`User=root` in the unit) — `systemctl poweroff` fails silently otherwise; check `journalctl -u shutdown-server`.

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
- [ ] **Games backlog** (from `homepage/games/educational-games-build-plan.md`): `monster.html` (Feed Me!) is considered pointless and a candidate for replacement; `animals.html`'s sounds are inaccurate and need fixing or swapping for a different game; the games hub (`games/index.html`) is hand-maintained and not alphabetized — a longstanding ask is to auto-discover games and sort the hub alphabetically so new games don't require memorizing a grid position.
- [ ] **Wave 2 educational games** (same build-plan doc): a fully scoped but unbuilt plan for ~18 additional games split into a Kindergarten wing and a 3rd-grade wing, plus shared infrastructure (player profiles, a star ledger, a parent page for spelling/word lists, and a `games/shared/arcade-api.php` generalizing the Bingo state pattern). Not started — build in phases per that doc when there's a session for it.
- [ ] Confirm the default boot volume for the car-aux music player (set to 80 in `car-music-start.sh`); optionally expose MPD on `192.168.4.1:6600` for native MPD phone control (Part 9).