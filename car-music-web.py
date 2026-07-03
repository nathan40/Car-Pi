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
