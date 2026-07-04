# Car-Pi

Have you ever wanted a server with media on a road trip? This is a fully offline media server for your next road trip!

## Quick start

1. Flash Raspberry Pi OS Lite (64-bit, Debian 13 "Trixie") to a Raspberry Pi 4 with Raspberry Pi Imager (set hostname/user/SSH, and set the Wi-Fi country in the imager options).
2. Connect the Pi to your network with an **Ethernet cable** (internet is needed for the build only) and SSH in.
3. Run this one-liner to grab the repo and start the installer:
   ```
   curl -fsSL https://raw.githubusercontent.com/nathan40/Car-Pi/main/setup.sh | sudo bash -s -- --bootstrap
   ```
   This clones the repo to `~/Car-Pi` (skipping the clone if it's already there) and launches the real `setup.sh` from that copy.

   (Already have the repo cloned locally? Just run `sudo ./setup.sh` directly from inside it.)
4. Answer the questions (all asked up front), confirm, and walk away. It's safe to re-run — every step is idempotent.

## What it is

Car-Pi turns a Raspberry Pi 4 into a self-contained, fully offline media server for the car (or a hotel room, cabin, or anywhere else without internet). Passengers connect to the Pi's own Wi-Fi access point — no cellular data or internet connection needed once it's built.

Once set up, it provides:

- **Jellyfin** (`:8096`) — movies and TV, streamed to phones/tablets
- **Audiobookshelf** (`:13378`) — audiobooks and podcasts
- **Navidrome** (`:4533`) — a music library/streaming server
- **Dashboard + games arcade** (`:80`) — a homepage with links to everything, plus a set of simple browser games (bingo, memory, painting, a racer, etc.) for kids
- **Auto-shuffle aux music** — on every boot, the Pi shuffles its whole music library and plays it out the 3.5mm aux jack, with a small web control API (`:8088`) for play/pause/volume
- **Dashboard power-off button** (`:8097`) — a safe shutdown button reachable from the dashboard, so you don't have to pull the power on the SD card

Everything runs in Docker (`docker-compose.yml`) except the Wi-Fi access point (hostapd + dnsmasq), the aux music player (MPD), and the shutdown listener, which run as native services set up by `setup.sh`.

See `pi-media-server-master-guide.md` for the full build background and rationale.
