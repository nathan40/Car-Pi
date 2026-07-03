# Games to modify
monster.html is pointless.
animals.html is not the correct sounds. I would like to remove or modify this to do something else as the sounds are not accurate.

I would like the games index to automatically pick up the games if possible (longshot). The list I would like to be alphabetical as well as this is tough to find the games unless you memorize the game's location.


# RoadTrip Arcade — Wave 2: Educational Games (Build Plan)

A build brief for **18 new learning games** on the Pi's offline homepage server, to be built in a later session. Wave 1 (bubbles, fireworks, xylophone, animals, paint, Feed Me!, Bonk!, shapes, Vroom!, memory, Minnesota Car Bingo, Spell It!) is live and nails the toddler tier — this wave targets the **third grader** and **kindergartner**, with several games that scale down to the 2-year-old.

**Serving setup (unchanged):** `php:8-apache` container, games in `/srv/homepage/games/` served at `http://192.168.4.1/games/`, writable state only at `/var/www/state` (the bingo-api pattern). Clients are Android tablets on the RoadTrip Wi-Fi with zero internet.

---

## 1. The players

| Player | Level | Target skills |
|---|---|---|
| 🦁 Third grader (8–9) | Grade 3 | ×/÷ facts to 12, fractions, telling time, money, spelling, US geography, mixed-operation fluency |
| 🐸 Kindergartner (5–6) | K | Letter sounds, sight words, counting to 20, making 10, patterns, alphabet order, rhyming |
| 🐣 Two-year-old | Toddler | Already covered by Wave 1; several Wave 2 games include a toddler mode |

**Key idea — player profiles.** Wave 2 adds a shared "who's playing?" picker (one avatar per kid). The chosen profile sets each game's default difficulty automatically, so *one* counting game serves the 2-year-old (1–5, count-along) and the kindergartner (1–20, no hints), and Quiz Duel can pit the 5- and 8-year-old against each other fairly. Profiles and stars live in server state; each tablet remembers its last player in localStorage.

---

## 2. Rules of the road (every game must follow these)

These match the Wave 1 conventions — the new games should be indistinguishable in feel.

- **Fully offline.** No CDNs, no web fonts, no external requests of any kind. Acceptance test: tablet in airplane mode joined to RoadTrip, plus a DevTools "offline" check for stray requests.
- **One self-contained file per game** in `/srv/homepage/games/` (`.html`, or `.php` only when server state is genuinely needed). Shared word lists / helper JS may live in `games/shared/`.
- **Art is emoji + inline SVG + CSS.** No image files. Sound is Web Audio synthesis (chimes, pops, fanfares) — starts after first tap per browser rules, with the existing 🔊 mute toggle.
- **Voice = the tablet's built-in TTS** (`speechSynthesis`), the same trick Spell It! uses. It works offline **only if voice data is installed**: before the trip, Android Settings → Google Text-to-speech → install/update voice data, then test in airplane mode. Every voice-dependent game ships a no-voice fallback mode and degrades to it automatically if no voice is available.
- **Touch-first:** pointer events, targets ≥ 64 px, works portrait and landscape, `touch-action: manipulation`, no hover-dependent UI, no reading required to *start* any kindergarten game (icons, demo animation, or voice carry the instructions).
- **🏠 home button** top-corner in every game, back to the games hub. Each game gets its own hub tile color + emoji so pre-readers navigate by color, same as Wave 1.
- **State discipline:** per-tablet progress via the existing localStorage `store()` helper; shared state only through PHP + flock-locked JSON in `/var/www/state`, writing **only on user actions** (SD-card friendly), ~2–3 s polling for multiplayer, and the "📴 this tablet only" offline-fallback chip when the API is unreachable — all straight from `bingo-api.php`.
- **Skip secure-context APIs.** Over plain `http://192.168.4.1` there is **no** service worker, wake lock, or clipboard API. Not needed anyway — the Pi *is* the offline source. localStorage, Web Audio, TTS, and fullscreen all work fine. (Tablet tip: just lengthen the display sleep timeout for car use.)
- **Quality gate:** syntax-check every file's JS with `node --check` before zipping, like the Wave 1 builds.

---

## 3. Shared infrastructure — Phase 0 (build this first)

1. **`games/shared/arcade-api.php`** — generalize the bingo-api pattern into one small API: flock-locked JSON files under `/var/www/state/`, action-only writes. Endpoints: `profiles` (get/set kids), `stars` (append award, totals per kid), `lists` (get/set word lists), `rooms` (create/join/answer — for Quiz Duel and Math Bingo).
2. **Player picker** — `games/shared/players.js`: a drop-in start screen (tap your avatar), sets difficulty defaults, remembers last player per tablet. Solo static games still work if the API is down (falls back to a local guest profile).
3. **Star ledger** — every completed round can award ⭐ to the active profile; the hub shows each kid's running total. Deliberately simple: stars are the whole economy, no unlocks to manage.
4. **Parent page** — `games/parent.php`, behind a simple passcode: edit the weekly spelling list and sight-word list, peek at star totals and Times Table Turbo's weak-facts report. This is what keeps the spelling games matched to actual schoolwork all year.
5. **Hub update** — `games/index.html` gains a second row: 🐣 *Play* (Wave 1, untouched, still first so the toddler self-serves) and 🎓 *Learn* (Wave 2 tiles). 
6. **State folder cleanup (recommended, 2 minutes).** The compose file currently maps `/srv/homepage/bingo` → `/var/www/state`. Because `/srv/homepage` is also the web root, the raw state JSON is browseable at `http://192.168.4.1/bingo/…`. Harmless on a family LAN, but with profiles/stars/word lists moving in, move it out of the web root:

   ```yaml
   # homepage service, volumes:
   - /srv/homepage:/var/www/html:ro
   - /srv/config/arcade-state:/var/www/state   # was /srv/homepage/bingo
   ```

   ```bash
   sudo mkdir -p /srv/config/arcade-state
   sudo mv /srv/homepage/bingo/* /srv/config/arcade-state/ 2>/dev/null
   sudo chown -R 33:33 /srv/config/arcade-state    # 33 = www-data in the container
   cd /srv && docker compose up -d homepage
   ```

---

## 4. The games

Format: **name — file — who — teaches — how it plays — build notes** (S/M/L effort). TTS-dependent games are marked 🗣️ and always have a silent fallback.

### 🐸 Kindergarten wing

**1. 🔤 Letter Sounds Safari — `lettersounds.html` — K (+ toddler free-play) — phonics 🗣️ (S/M)**
Free-play mode: tap any letter to hear its *sound* (not just its name) and see three emoji that start with it ("B says buh — 🐻 🍌 🚌"). Quiz mode: "Find the letter that says /mmm/" with three big letter tiles. Silent fallback: match the letter to the picture that starts with it. Deliberately the step *before* Spell It!, which stays the blending step.

**2. 🎈 Sight Word Pop — `sightwords.html` — K — sight-word recognition 🗣️ (M)**
Balloons drift up carrying words; a voice calls one ("pop **the**!") and the kid pops it before it floats off. Wrong balloons wobble, no penalty. Bundle the public-domain Dolch lists (pre-primer → primer → grade 1) as levels, plus the parent-page custom list. Silent fallback: a big target word at the top, pop its matching balloon (visual discrimination — still useful).

**3. 🍪 Count & Crunch — `counting.html` — K + toddler — counting & numerals (S)**
A monster asks for cookies; count the objects on screen, tap the right numeral, monster crunches them with confetti. Levels: 1–5 with tap-to-count-along voice (toddler), 1–10, 1–20, then "how many more does he need?" as the stretch. Objects arranged sometimes in lines, sometimes scattered — that's the actual K skill.

**4. 🔟 Ten-Frame Frenzy — `tenframe.html` — K — making 10, addition within 10 (S)**
A ten-frame fills with dots; tap the number that completes 10 (or the sum shown, in add mode). Streaks build a gentle combo meter; no timer by default, optional 60-second "frenzy" once accuracy is high. The single highest-leverage K math visual there is.

**5. 🐛 Pattern Party — `patterns.html` — K + toddler — patterns (S)**
A caterpillar grows in a pattern (🔴🔵🔴🔵…); pick which of three segments comes next. AB → ABB → AABB → ABC with shapes and colors. Toddler mode collapses to simple color matching. Fully playable with zero words on screen.

**6. 🚂 Alphabet Train — `abctrain.html` — K — alphabet order, upper/lowercase (S/M)**
Build the train by tapping the next letter car A→Z (choices shrink from 3 as skill grows); every 5 cars, a toot-toot and the train chugs a bit. Mode 2: match lowercase cars to the uppercase engine ("which car goes with B? → b"). Mode 3: the train is missing a letter mid-sequence — fill it.

**7. 👂 Rhyme Time — `rhymes.html` — K — rhyming awareness 🗣️-optional (S)**
"What rhymes with 🐱 *cat*?" — pick from three pictures (🎩 hat, 🐕 dog, ☀️ sun). Voice speaks the candidates when available, but the emoji make it fully playable muted. Bundle ~40 rhyme sets built from emoji-representable words; three levels by similarity of the distractors.

### 🦁 Third-grade wing

**8. 🏎️ Times Table Turbo — `timestables.html` — 3rd — ×/÷ facts to 12 (M)**
Pick which tables to practice (×2–×12, or ÷ mode); answering facts boosts your car in a race against three CPU cars, misses make you coast. Per-profile it records personal-best race times and a **weak-facts list** (misses + slow answers), and quietly deals those facts more often — the parent page shows the report. This is the daily-driver game for fact fluency, so it gets the star hookup first.

**9. 🥋 Number Ninja — `ninja.html` — 3rd (K easy mode) — mixed-operation fluency (S/M)**
A 60-second dojo: quick-fire problems escalate as you answer, combo streaks multiply points, belts (white → black) mark lifetime progress. Difficulty comes from the profile: kindergartner gets add/subtract within 10, third grader gets the full +−×÷ mix with two-step problems at the top belts.

**10. 🍕 Fraction Pizzeria — `fractions.html` — 3rd — fractions (M)**
Customers order fractions of a pizza ("¾ pepperoni!"); tap slices to serve, inline-SVG pizzas do the visual work. Level 2: two customers order different fractions — who gets more? Level 3: equivalents ("2/4 is the same as…?") by matching differently-sliced pizzas. Fractions-as-pictures before fractions-as-symbols, which is exactly the grade-3 pitfall.

**11. 🕐 Clockworks — `clocks.html` — 3rd (K first level) — telling time (M)**
Read the SVG analog clock, tap the matching digital time; reverse mode: spin the hands to set a given time. Levels: o'clock only (kindergarten-friendly) → half hours → 5 minutes → to the minute, plus a "15 minutes later" elapsed-time stretch. A road trip is the natural habitat for "how long until…".

**12. 🪙 Coin Counter — `money.html` — 3rd — money (M)**
Drag SVG US coins onto the tray to pay the price tag exactly; harder: pay with the *fewest* coins; hardest: you're the cashier — make change from a dollar. Coins stay proportionally sized (the dime-is-smaller-than-a-nickel trap is the point).

**13. 🐝 Spelling Bee — `spelling.php` — 3rd — spelling 🗣️ required (M)**
The classic: voice says the word, then uses it in a sentence on request; kid types it on big on-screen letter keys; three hearts per round. The word list is the **weekly list from the parent page**, so it tracks actual school spelling all year, with a bundled grade-3 starter list. No-voice fallback: unscramble mode (same lists).

**14. 🗺️ State Snap — `states.html` — 3rd — US geography (M/L)**
"Find Minnesota!" — tap the state on a bundled inline-SVG US map; it glows and shows one kid-sized fact. Modes: find-the-state, name-the-highlighted-state, capitals, and region practice (start with the Midwest). The simplified public-domain SVG map must be fetched and inlined during the build session — the only game with an external asset to grab.

### 👨‍👩‍👧‍👦 Play-together wing

**15. 🎈 Word Rescue — `wordrescue.html` — K & 3rd — spelling/vocab (S/M)**
Friendly hangman: seven balloons hold a character aloft; each wrong letter pops one — spell the word before they're gone (they parachute safely on a loss, no doom). Pulls the same lists as the spelling games: sight words for the kindergartner, the weekly list for the third grader, per the active profile.

**16. 🃏 Memory: Learning Decks — upgrade to existing `memory.html` — all three kids — matching concepts (S)**
Add a deck picker to the Wave 1 memory game rather than building a new one: existing emoji decks stay (toddler), plus **Aa↔aa** (uppercase/lowercase), **number↔dot-count**, and **fact↔answer** (6×7 ↔ 42). Same engine, same chick/lion sizes, pass-and-play for two.

**17. ⚔️ Quiz Duel — `duel.html` + rooms API — K vs 3rd — the flagship (L)**
True head-to-head across tablets: each kid joins a room from their own tablet, both get a question at the *same moment* but **at their own level** (from profiles — counting for one, times tables for the other), first correct answer takes the point, best of 10 with a big shared scoreboard. The handicap is the whole magic: the 5-year-old can genuinely beat the 8-year-old. Built on the bingo-api patterns: flock JSON room state, ~2 s polling, and the 📴 fallback becomes solo practice mode. Build last, after everything it depends on exists.

**18. 🚌 Math Bingo — `mathbingo.html` — family — fact fluency, together (M)**
Wave 1 bingo's academic cousin, reusing its server referee: cards hold *answers*; the caller shows "6 × 7" and everyone hunts their card for 42. Auto-caller mode (a new call every 20 s) or a parent device drives it. Kindergarten cards get their own call types: dot patterns, number words, "one more than 4." Server verifies bingos exactly like the Minnesota game.

---

## 5. Content to bundle at build time (needs internet once, then never again)

- Dolch sight-word lists, pre-primer → grade 1 (public domain — include as JS data in `games/shared/`)
- A grade-3 spelling starter list (~100 words; the parent page takes over from there)
- ~40 emoji-representable rhyme sets (written in-session, no fetch needed)
- Simplified public-domain **US states SVG** (e.g., from Wikimedia) inlined into `states.html`, plus one fun fact per state
- US coin SVGs drawn in-session (circles + text — no asset fetch needed)

## 6. Suggested build order

| Phase | Ships | Contents |
|---|---|---|
| 0 | infrastructure | arcade-api.php, player picker, stars, parent page, hub "Learn" row, state-folder move |
| 1 | six quick wins, all static | Count & Crunch, Pattern Party, Ten-Frame Frenzy, Rhyme Time, Number Ninja, Memory Learning Decks |
| 2 | the bigger statics | Clockworks, Fraction Pizzeria, Coin Counter, Alphabet Train, Word Rescue, State Snap |
| 3 | voice + lists | Letter Sounds Safari, Sight Word Pop, Spelling Bee (parent-page lists go live here) |
| 4 | multiplayer | Math Bingo, Times Table Turbo (stars + weak-facts), Quiz Duel |

Each phase is independently shippable — same zip/scp install flow as Wave 1, no container changes needed after the Phase 0 state-folder move.

**If trimming toward 12:** cut in this order — Alphabet Train, Rhyme Time, Coin Counter, Ten-Frame Frenzy (fold its "make 10" into Count & Crunch as a top level), Word Rescue, State Snap. Don't cut Quiz Duel; it's the one they'll remember.

## 7. Acceptance checklist (every game, before it goes in the zip)

- [ ] Loads and plays with the tablet in **airplane mode** via `http://192.168.4.1/games/…`; DevTools shows zero external requests
- [ ] Touch targets ≥ 64 px; playable in portrait *and* landscape; no hover anywhere
- [ ] Kindergarten games are startable by a non-reader (icons/voice/demo carry the instructions)
- [ ] 🗣️ games detect missing voices and switch to their silent fallback automatically
- [ ] 🏠 returns to the hub; 🔊 mute works; sound waits for the first tap
- [ ] Static games fully work if the PHP API is down (guest profile, 📴 chip on multiplayer)
- [ ] State survives a Pi power-cut (localStorage or flock-JSON only, action-only writes)
- [ ] `node --check` passes on all inline JS; tested on an actual Android tablet, not just desktop

## 8. Kickoff prompt for the build session

> Read `educational-games-build-plan.md` (attached/in project). Build **Phase N**, following section 2's conventions exactly and matching the look and feel of the existing Wave 1 games (emoji art, per-game tile colors, Web Audio sound, 🏠 home button, pointer events, the localStorage `store()` helper). Deliver one self-contained file per game into a zip mirroring the Wave 1 layout (`games/`, updated `games/index.html`, README install steps via scp to `pi@192.168.4.1`), syntax-check all JS with `node --check`, and note any spec deviations at the top of your reply.

Run one phase per session so each zip stays testable on the real tablets before the next begins.
