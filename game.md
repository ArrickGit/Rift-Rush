*Note: the links and images in this document may point to external sources. Please review them before opening.*

# CLAUDE.md — Rift Rush Master Game Design & Implementation Spec (v3.1)

> **Status:** Single-Player Feature Complete (`main` @ `af46038`) — Pre-Launch Polish, Balance, Audio & UI Fix Roadmap (v3.1)
> **In Progress (2026-10-30):** Game-like UI redesign on branch `game-like-ui` (not merged yet) — see **Section 5 (Live Development Log)** for what's done, known bugs, and what's left.
> **Platform:** Roblox (PC, Mobile, Console)
> **Genre:** 2.5D PvE Action Roguelite with Endless Permanent Progression & Rebirths
> **Working Title:** Rift Rush
> **Repository:** [ArrickGit/Rift-Rush](https://github.com/ArrickGit/Rift-Rush)
> **Codebase Snapshot:** 18 Server Services, 13 Client Controllers (incl. new `Sfx` + `StationScenes`), 16 Shared Modules
> **Document Purpose:** Serve as the single source of truth (`CLAUDE.md` / `game.md`) for Claude Code to finish the remaining 4 unwired Ascension nodes, UI fixes, Bag redesign, audio system, balance pass, and pre-launch preparation.

---

## 0. AI Agent Execution Rules & Model Selection Guidelines

> **CRITICAL INSTRUCTIONS FOR CLAUDE CODE — READ BEFORE EVERY ACTION:**

### 0.1 Mandatory Coding & Architecture Standards
1. **Strict Luau Typing:** Every `.luau` script MUST begin with `--!strict` and use explicit type annotations for function parameters, return types, and data structures.
2. **Server Authority:** Never trust the client for damage calculations, currency payouts, Weapon Mastery XP, Rebirth eligibility, Ascension Shop purchases, environmental hazard damage, or room completion. Use `ReplicatedStorage.Shared.FormulaEngine` on the server as the single source of truth.
3. **Preserve Working Systems (`af46038`):** All 8 weapons, 8 relics, 9 town stations, Star-Force upgrading, Weapon Mastery/Paragon, and DataStore profile locking are already built and verified in Studio playtesting. Do NOT rewrite or break working services when adding polish, fixing UI overlaps, or wiring the final 4 Ascension Shop nodes.

### 0.2 Model Selection Guidelines (Default Sonnet vs. When to Recommend Opus)
* **Default Model (Sonnet):** Default to **Sonnet** for standard development (wiring the 4 remaining Ascension nodes, fixing HUD/popup overlaps, redesigning the Bag UI, adding `AudioController` sound effects, and expanding World 1 rooms/cards).
* **When to Recommend Switching to Opus:** Let the user know to switch to **Opus** only when performing the **Comprehensive Game-Wide Balance Pass (Step PL-4)**—which requires cross-referencing `FormulaEngine`, enemy DPS, weapon cooldowns, Star-Force costs, and curse trade-offs simultaneously—or when debugging complex cross-service edge cases.

---

## 1. Current Codebase Status Audit (`main` at `af46038`)

> **VERIFIED IN STUDIO PLAYTEST (18 Server Services, 11 Client Controllers, 16 Shared Modules):**

### 1.1 Movement, Camera & Controls (Done & Tested)
* **Side-on 2.5D Lock:** Players and enemies are locked to the $Z = 0$ plane with a narrow side camera that smoothly follows the player vertically and shakes on hits (`Movement25DController`, `Camera25DController`, `Physics25D`).
* **Movement Mechanics:** Walk, double jump (triple jump via Ascension node), drop down through platforms (`Down + Jump`), jump pads launching ~30 studs upward, and ground dash / air "flash jump" with recharging charges.
* **Cross-Platform Controls:**
  * **Keyboard & Gamepad:** `Q` / `LB` / `RB` for active ability; `I` / `B` / `Select` for the Bag.
  * **Mobile (`MobileControlsController`):** Floating virtual joystick plus Attack, `Q` (with cooldown display), Dash, and Jump buttons *(built in code; needs real mobile device verification)*.
* **Attack Feel:** Character arm swings on every attack, and Gauntlets punches lunge the player forward.

### 1.2 All 8 Playable Weapons (Done & Tested — Each Cleared a Room)
Every weapon is physically welded into the character's right hand both in Town and inside Portal Runs (`WeaponHoldService`).

| Weapon | Unlock Cost | Basic Attack | `Q` Ability | Innate Passive | Link Skill (Mastery 10 / 20) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Greatsword** | Free | Wide slash, hits up to 8 targets | **Rift Cleave** shockwave | $+15\%$ attack speed after hitting $3+$ enemies | $+8\% / +15\%$ Normal & Elite Dmg |
| **2. Daggers** | Free | Fast twin-blade stab | **Shuriken Fan** (5 blades) | Dashing through an enemy guarantees next hit Crits | $+10\% / +20\%$ Critical Damage |
| **3. Staff** | Free | Bolt that inflicts *Shock* | **Fireball** that explodes and *Burns* | *Burn* + *Shock* on one enemy triggers an *Arcane Nova* | $+8\% / +15\%$ Status Dmg & Duration |
| **4. Bow** | $400$ Dust + $2$ Cores | Arrows that pierce through enemies | **Arrow Rain** (8 arrows, aims at an enemy) | Hitting the same target repeatedly stacks damage up to $+30\%$ | $+5\% / +10\%$ Critical Hit Rate |
| **5. Hammer** | $750$ Dust + $4$ Cores | Slam that pops enemies up and stuns them | **Seismic Tremor** (3 erupting rock pillars + stun) | Bonus damage to stunned enemies; slams grant a shield | $+8\% / +15\%$ Boss Damage |
| **6. Gauntlets** | $1,200$ Dust + $6$ Cores | 3-punch chain, 3rd punch hits harder with forward lunge | **Rising Uppercut** (launches you and enemies, *Burns*) | Combo doesn't drop while dashing; $+$damage per combo | $+6\% / +12\%$ Atk Speed & CDR |
| **7. Summoning Bell** | $2,000$ Dust + $10$ Cores | Sonic pulse that commands foxes what to attack | **Call Rift Familiar** (2 Spirit Foxes for $12\text{s}$ firing bolts) | Foxes inherit your Crit, Attack Speed, and status effects | $+10\% / +20\%$ *Rift Dust* Drop Rate |
| **8. Trick Cards** | $3,500$ Dust + $15$ Cores | Cards bounce to a second enemy | **Royal Flush** (5 cards) + draws a card | Every 6th attack draws **Red** (fire blast), **Blue** (cooldown cut), or **Gold** ($+$Dust) | $+8\% / +15\%$ Rare/Epic Upgrade Chance |

### 1.3 Server-Authoritative Combat Rules (Done & Tested)
* **Multiplicative Damage Formula (`FormulaEngine`):** Hunter Level, Weapon Mastery, Rebirth, Ascension nodes, Link Skills, Relics, in-run upgrades, combo bonus, Curses, and Critical Hits all multiply cleanly.
* **Status Effects:**
  * **Burn:** Damage over time that spreads to nearby enemies when the target dies.
  * **Shock:** Hits chain lightning to nearby enemies.
* **Combo Counter:** $+1\%$ damage per 10 hits, up to $+50\%$.
* **Invincibility Frames & Shields:** Short i-frame window after dashing or taking a hit; shields absorb damage before HP.
* **Shadow Line Extra Hits:** Small bonus shadow hits triggered via the `Limit Breaker` Ascension node.
* **Floating Damage Numbers & Combat VFX (`CombatVFXController`):** Color-coded damage numbers by type (crit, poison, shield, etc.), summoned spirit foxes, orbiting coins, erupting rock pillars, card draw visuals, and green screen vignette flash when touching acid.

### 1.4 Enemies & Bosses — World 1: Mushroom Wilds (Done & Tested)
* **Regular Enemies:** *Spore Blob* and *Mushroom Hopper*, plus tougher Elite variants that hop onto platforms and deal contact damage.
* **Bosses:** *Spore Golem* (Room 5) and *Mushroom Titan* (Room 10).
  * Telegraphed warning zones appear before attacks land.
  * Bosses enter an enraged faster phase at $50\%$ HP.
  * Hitting a thrown *Spore Boulder* back at the boss stuns it (`"EXPOSED - ATTACK!"` window).
* **Procedural Animation:** Code-driven squash-and-stretch, hit-flinching, and overhead HP bars on imported 3D models.

### 1.5 Runs, Hazards, Upgrades & Curses (Done & Tested)
* **10 Room Layouts + Endless Mode:** Combat rooms, 2 climbing rooms with rising acid (exit at the top), a Treasure room, and 2 boss rooms. After Room 10, runs continue endlessly with procedural room selection and a boss every 5th room.
* **Bubbling Acid Flood (`HazardService`, `AmbientController`):** Multi-layered bubbling flood rendered on client while the server applies **$8\%$ Max HP damage per tick** and an upward lava bounce.
* **At-Risk Loot Pouch & Rift Anchors:** *Rift Dust*, *Boss Cores*, and *Relic Shards* accumulate in an at-risk pouch until a boss checkpoint (**Rift Anchor**) banks them, letting the player choose to **Extract** or **Keep Pushing**.
* **Tiered Defeat Loss:** $30\% / 50\% / 75\%$ of unsecured pouch lost depending on depth, with Defeat Screen options for Accept Defeat, Anchor Token Rewind/Insure, or Robux Revive/Rewind/Insure.
* **10 Upgrade Cards:** Across Common to Legendary (*Sharpened Edge, Swift Hands, Keen Eye, Vital Surge, Ember Edge, Storm Conduit, Cleaving Gale, Triple Threat, Napalm Wake, Volatile Cinders*), with Reroll and Banish support.
* **5 Curses:** Offered on altars in the Treasure room, up to 4 active per run (verified in testing: Max HP accurately scaled down from $258 \rightarrow 155$).
* **Corruption Tiers:** Selectable at the Rift Gate; beating Room 10 unlocks the next Corruption Tier or World.

### 1.6 Relics & Star-Force System (`RelicService` — Done & Tested)
* **8 Working Relics:** *Frost Heart, Treasure Tooth, Thunder Boots, Hungry Coin, Phoenix Feather, Vampiric Fang, Broken Crown, Volatile Hourglass*. Each has active combat hooks that scale up with each star level.
* **Drop Rates & Shard Conversion:** $35\%$ drop chance from Room 5 boss, $100\%$ guaranteed from Room 10 boss, and $25\%$ from chests. Duplicate drops automatically convert into **+5 Relic Shards**.
* **Non-Destructive Star-Force ($1\star \rightarrow 5\star$):** Failed attempts never lose stars and add $+25\%$ Pity to the next attempt. Safeguard items refund shards on failure.
* **Starting Relics:** Players carry 1 Starting Relic into every run, expandable with the `Twin Relic Vessel` Ascension node and Gamepass.

### 1.7 Permanent Progression (Done & Tested)
* **Hunter Level & Rebirth:** 10 structured Rebirth tiers followed by endless Rebirth scaling. Supports **Standard Rebirth**, **Keep Everything Rebirth**, and **Robux Instant Rebirth**.
* **Weapon Mastery & Paragon (`MasteryService`):** Levels $1 \rightarrow 20$ plus up to $979$ Paragon ranks. Each weapon unlocks its account-wide **Link Skill** at Mastery 10 and upgrades it at Mastery 20, with up to 6 active Link Skill slots.
* **Ascension Shop (17 Nodes Total):** **13 nodes are fully wired and functional**, including Respec (which refunds spent Sparks and automatically trims active Link Skill and Starting Relic slots to match). *4 nodes remain to be wired (see Section 2.1).*

### 1.8 Town Hub — Haven Outpost (Done & Tested)
* **9 Working Stations on Custom Landmarks (`LandmarkBuilder`):** All 9 stations have functional UI panels, and all except the Rift Gate stand as oversized landmarks on custom-themed animated platforms.
* **Persistent Waypoints:** Markers always point toward every interactable and never hide when close, including chests, curse altars, and room exits inside runs.
* **Fantasy Vista Scenery (`VistaBuilder`):** Floating islands with waterfalls, ancient World Tree, distant castle spires, stone aqueduct, drifting clouds, and floating spirit motes.
* **High-Contrast Platforms:** Elevated platforms feature vibrant lime grass inside a timber frame with vines and flowers, contrasting cleanly against the darker forest ground floor.
* **UI Panels (`StationPanels` & `UIController`):**
  * `StationPanels`: Blacksmith, Legion Hall, Star-Forge, Quest Board, Hall of Champions, and Bag.
  * `UIController`: Rift Gate, Rebirth Pedestal, Ascension Shop, and Robux Store.
* **Quests & Leaderboards:** 3 Daily Quests drawn from a pool of 9 + 2 repeatable Bounties; 3 Leaderboards backed by `OrderedDataStore` with in-server fallback.
* **HUD:** Displays Hunter Level, HP + Shield bar, XP & Mastery bars, active Relics and Curses, currencies, run banner, popup notifications, and celebration banners.

### 1.9 Saving, Backend & Dev Tools (Done & Tested Online)
* **DataStore Persistence & Session Locking:** Player profiles save/reload reliably, with session locking so the same profile cannot be opened on two servers simultaneously.
* **Autosave & Safe Leave Payout:** Autosaves every 90 seconds; if a player leaves mid-run, their at-risk pouch is paid out properly before the final save writes.
* **Lifetime Stats Tracking:** Tracks kills, elite kills, boss kills, rooms cleared, deepest room, chests opened, Dust banked, and extractions.
* **Monetization Scaffolding:** Complete receipt/purchase handling for 13 Developer Products and 8 Gamepasses (all product/pass IDs currently set to `0` pending live Roblox asset creation).
* **Studio Test Suite (`RiftDev`):** Studio-only console helpers to grant currencies, equip weapons, add relics, and set Mastery levels.

---

## 2. Remaining Gaps & Pre-Launch Specification (What Needs to Be Done Next)

### 2.1 The 4 Unwired Ascension Shop Nodes (Priority Code Wiring)

These 4 of the 17 Ascension Shop nodes have no gameplay effect yet. **Since `8ac6b82` they are flagged `ComingSoon = true` in `AscensionShopConfig`:** the Spark Sanctum shows them with a "SOON" tag and `AscensionShopService` refuses to sell them, so no one wastes Sparks. When a node gets wired, delete its `ComingSoon` flag. Here is the exact specification for Claude Code to wire them up:

> **ID correction (checked against `AscensionShopConfig`, 2026-10-30):** the real IDs are Vacuum Aura = `AS_T1_03`, Headstart Blessing = `AS_T1_04`, Elemental Crit Overload = `AS_T3_01`, Miracle Evolution = `AS_T4_02`. (`AS_T2_04` is *Boss Hunter's Trophy* and `AS_T3_02` is *Relic Resonance*, both already working.) The run service is `RunManagerService`, not `RunService`. Also note the config text differs slightly from the specs below: Headstart is "Common+ → Rare+ → Epic+" over 3 levels, Elemental Crit is "33% / 66% / 100% of Crit Damage", and Miracle Evolution is a 1-level node, "15% Double Orb". Decide which version wins before wiring.

1. **Vacuum Aura (`AS_T1_03` — Loot Magnet & Drop Orbs):**
   * **Why it currently does nothing:** Loot is currently granted directly to the pouch without spawning physical drop orbs, or lacks a pull magnet.
   * **Implementation Spec:** When an enemy dies or a chest opens, spawn lightweight client-rendered glowing loot orbs (*Rift Dust* crystals, *Boss Cores*, *HP globes*) that scatter briefly and then magnetically accelerate toward the player within a base pickup radius of $14\text{ studs}$. Each level of **Vacuum Aura** increases pickup radius by $+35\%$ (at Lv. 3, full-room magnet pull from anywhere in the room) and grants $+2\%$ bonus *Rift Dust* collected.
2. **Headstart Blessing (`AS_T1_04` — Free Room 1 Upgrade Card):**
   * **Why it currently does nothing:** Room 1 does not trigger the free bonus upgrade card check on run start.
   * **Implementation Spec:** In `RunService:StartRun()`, check if the player owns `Headstart Blessing` (`Level >= 1`). If owned, immediately trigger a bonus **Headstart Upgrade Card Selection** at the start of Room 1 where every offered card is guaranteed to be **Rare or higher** (or **Epic or higher** if upgraded).
3. **Elemental Crit Overload (`AS_T3_01` — Status Effects Can Crit):**
   * **Why it currently does nothing:** *Burn* ticks, *Shock* chains, and *Arcane Nova* procs currently deal flat non-critical damage.
   * **Implementation Spec:** In `CombatService` status tick/proc evaluation, check if the attacker owns `Elemental Crit Overload`. If owned, roll the player's `CritRate` on every *Burn* tick, *Shock* chain, and *Arcane Nova* burst. On a critical status hit, multiply the status damage by `1 + (CritDamageBonus * 0.50 * NodeLevel)` and display an orange-gold critical status damage number.
4. **Miracle Evolution (`AS_T4_02` — Double Upgrade Card Picks):**
   * **Why it currently does nothing:** The room-clear upgrade picker always closes after 1 card pick.
   * **Implementation Spec:** When rolling a room-clear Upgrade Selection, if the player owns `Miracle Evolution`, roll a $15\% \times \text{NodeLevel}$ chance (and **guaranteed $100\%$ on Boss Rooms 5 and 10**) to display a golden `"✨ MIRACLE EVOLUTION — PICK 2 UPGRADES!"` banner on the Upgrade Picker, allowing the player to select **2 cards** from the hand before closing.

---

### 2.2 UI Bugs, Bag Redesign & Missing Screens (Step PL-2)

1. **Fix 3 Specific HUD & UI Glitches:**
   * **Popup Overlap Fix:** Toast/popup messages currently overlap open station windows. Move notifications to a high `ZIndex` top-center/top-right toast queue or suppress non-critical HUD popups while a full-screen station panel is open.
   * **Combo Counter Overlap Fix:** Reposition the Combo Counter so it anchors cleanly below the player's health/ability cluster or left of center, never overlapping the top-right currency display.
   * **"Label" Flash Before Profile Load Fix:** Initialize all HUD text labels with `Text = ""` (or a clean loading shimmer state) instead of default `"Label"` text until `PlayerDataLoaded` fires on the client.
2. **Bag / Inventory UI Redesign (`StationPanels`):**
   * Rebuild the Bag screen using the **UIPack's native Inventory Template** with clean weapon and relic icons (supporting `game-icons.net` decal asset IDs in `AssetRegistry` with crisp vector fallbacks).
   * Display clear equipment slots (**Equipped Weapon**, **Starting Relic(s)**, **Active Link Skills**), live stat summary, and 1-click Equip/Unequip actions.
3. **Add 3 Missing Essential Screens:**
   * **End-of-Run Summary Screen:** Shown upon **Successful Extraction** (and integrated cleanly with Defeat), displaying: Total Rooms Cleared, Time Elapsed, Enemies & Bosses Defeated, Total *Rift Dust* / *Boss Cores* / *Relic Shards* Banked, Weapon Mastery XP Gained, Relics Discovered, and a `"Return to Haven Outpost"` button.
   * **Settings Menu (HUD Gear Icon):** Toggle switches/sliders for: Music Volume, SFX Volume, Screen Shake On/Off, Teammate VFX Reduction, and Damage Number Style (Cascading vs. Compact).
   * **First-Time Onboarding Tutorial (60-Second Guided Flow):** Highlights the **Rift Gate** with a golden tutorial prompt for brand-new players (`RoomsCleared == 0`), shows brief control callouts in Room 1 (`Move`, `Attack`, `Q Ability`, `Dash`), and guides them to the **Blacksmith** or **Star-Forge** after their first extraction.

---

### 2.3 Audio & Sound Design Implementation (`AudioController.luau` — Step PL-3)

> **Partly started (2026-10-29/30):** 29 Kenney UI / forge / quest / combat sounds are uploaded and listed in `AssetRegistry.Sounds`. A small `client/Controllers/Sfx.luau` (`Sfx.Play(name, volume?, pitch?)`) plays them: every button clicks, station windows play an open / close sound, and the Quest Board and Spark Sanctum have claim / unlock sounds. **Still missing:** combat SFX hooks, enemy / boss SFX, music, pitch randomization, and the volume settings. `Sfx.luau` can grow into the `AudioController` described below.

Originally the game was completely silent. Create a centralized `ReplicatedStorage.Shared.SoundConfig` and `StarterPlayerScripts.Controllers.AudioController` using pooled `SoundService` playback with pitch randomization (`PlaybackSpeed = 0.92 to 1.08`) so rapid attacks never sound robotic:

* **Combat SFX:** Weapon swing whooshes (heavy metallic cleave for Greatsword, fast twin-slice for Daggers, arcane hum for Staff, bowstring twang, hammer ground-thud, rapid punch snaps, bell chime, card flick), hit impacts, critical hit chime, shield break, and dash whoosh.
* **Enemy & Boss SFX:** Mushroom hop boing, boss warning siren/telegraph rumble, boulder deflect clang, boss stun shatter, and acid sizzle when touching Stage 3 poison.
* **UI & Progression SFX:** Button hover/click, Upgrade Card appear/select, Legendary upgrade fanfare, Relic drop chime, Star-Force anvil strike (success fanfare vs. failure clink), Hunter Level Up, and Rebirth ascension chord.
* **Music Layers:** Calm high-fantasy orchestral/synth loop for *Haven Outpost*, upbeat driving action track for *Mushroom Wilds* combat rooms, and high-tempo boss battle music for Rooms 5 and 10.

---

### 2.4 Pre-Launch Balance Pass Targets (Step PL-4 — Recommend Opus)

> **CRITICAL ISSUE OBSERVED IN PLAYTEST:** Right now, an idle player dies in ~12 seconds against basic enemies, and several weapon/curse/cost curves need tuning.

1. **Player Survivability & Contact Damage Tuning:**
   * Reduce normal enemy contact damage in World 1 Rooms 1–4 by $\sim 35\%$ and add a $0.85\text{s}$ post-hit contact immunity window so a new player takes $8-10$ hits to die rather than melting in 12 seconds.
2. **Weapon DPS & Cooldown Parity:**
   * Audit all 8 weapons in `WeaponConfig` so slower weapons (*Hammer*, *Greatsword*) deal enough AoE/stagger burst per swing to match high-attack-speed weapons (*Daggers*, *Gauntlets*, *Bow*), and tune `Q` cooldowns between $5\text{s}$ and $9\text{s}$.
3. **Boss HP & Acid Damage:**
   * Tune *Spore Golem* (Room 5) for a $45-60\text{s}$ fight and *Mushroom Titan* (Room 10) for a $75-100\text{s}$ fight at appropriate gear levels.
   * Tune Rising Acid tick interval (`0.5s`) and damage ($6\%$ Max HP per tick in World 1) so climbing rooms feel thrilling without instantly killing players on a single missed jump.
4. **Curse Risk/Reward & Star-Force Economy:**
   * Ensure every Curse grants a multiplicative combat/loot upside ($+35\%$ to $+60\%$) that justifies its penalty, and smooth Star-Force *Relic Shard* costs ($5 \rightarrow 10 \rightarrow 20 \rightarrow 35$ Shards) and Daily Quest payouts.

---

## 3. Pre-Launch Execution Roadmap (Steps PL-1 to PL-6)

> **MODEL NOTE FOR CLAUDE:** Default to **Sonnet** for Steps PL-1, PL-2, PL-3, PL-5, and PL-6. Let the user know to switch to **Opus** for **Step PL-4 (Comprehensive Balance Pass)**.

| Step | Focus Area | Exact Tasks to Complete | Model |
| :--- | :--- | :--- | :--- |
| **Step PL-1: Wire Final 4 Ascension Shop Nodes** | `Vacuum Aura`, `Headstart Blessing`, `Elemental Crit Overload`, `Miracle Evolution` | 1. Add physical/client loot orbs + `Vacuum Aura` magnet pull.<br>2. Trigger free Room 1 Rare/Epic+ upgrade pick for `Headstart Blessing`.<br>3. Allow *Burn*/*Shock*/*Nova* to crit with `Elemental Crit Overload`.<br>4. Allow double upgrade picks on proc/boss rooms with `Miracle Evolution`. | **Default (Sonnet)** |
| **Step PL-2: UI Bug Fixes, Bag Redesign & Missing Screens** | HUD overlaps, Bag template, Run Summary, Settings, Tutorial | 1. Fix popup overlap with open panels, combo counter overlap with currencies, and `"Label"` text flash on load.<br>2. Rebuild Bag on the UIPack inventory template with weapon/relic icons.<br>3. Add **Run Summary Screen**, **Settings Menu**, and **First-Run Tutorial callouts**. | **Default (Sonnet)** |
| **Step PL-3: Audio System & Sound Effects (`AudioController`)** | Music, Combat SFX, UI SFX, Boss & Hazard SFX | 1. Create `SoundConfig.luau` with categorized Roblox `rbxassetid://` audio IDs and volume/pitch rules.<br>2. Build `AudioController.luau` and hook SFX into weapon swings, hits, crits, skills, bosses, acid sizzle, UI clicks, Star-Force, and Town/Run BGM. | **Default (Sonnet)** |
| **Step PL-4: Game-Wide Balance Pass** | Survivability, 8 Weapons, Boss HP, Acid, Curses, Economy | 1. Fix the "idle player dies in 12s" issue (tune contact damage + post-hit i-frames).<br>2. Balance DPS/cooldowns across all 8 weapons.<br>3. Tune Boss HP, Acid damage, Curse trade-offs, Star-Force costs, and Quest rewards. | **Switch to Opus** *(Remind user before starting PL-4)* |
| **Step PL-5: World 1 Variety Expansion** | More Rooms, Upgrade Cards, Enemy Variants | 1. Add 6–8 additional World 1 room layouts (combat, platforming, elite ambush).<br>2. Expand Upgrade Card pool from 10 to 20+ cards.<br>3. Add 1–2 ranged/flying World 1 enemy variants (e.g., *Spore Spitter*, *Mycelium Bat*). | **Default (Sonnet)** |
| **Step PL-6: Launch Prep, Real Robux IDs & Housekeeping** | Product IDs, Mobile/Console check, Cleanup | 1. Replace placeholder `0` IDs in `MonetizationConfig` with real Developer Product and Gamepass IDs.<br>2. Remove unused `DevRunPortal` script.<br>3. Verify `MobileControlsController` touch button sizing and gamepad navigation. | **Default (Sonnet)** |

---

## 4. Post-Launch Expansion Roadmap (After Steps PL-1 to PL-6)

Once the game launches with World 1 polished end-to-end, post-launch updates will roll out in this order:
1. **Co-op Party UI at Rift Gate:** Connect a Party Create / Join modal at the Rift Gate to the existing 1–4 player server party and *Sidekick Sync* scaling backend.
2. **Worlds 2–8 Content Updates:** Add *Toy Kingdom*, *Haunted Metro*, *Frozen Citadel*, *Neon Grid*, *Dessert Wastes*, *Sunken Archive*, and *Volcanic Factory* (each with custom tilesets, environmental mechanics, enemies, and 2 bosses; formula scaling is already in place).
3. **MapleStory-Inspired Endgame Systems:** Collectible Damage Skins, Boss Familiar Cards, AFK Dojo Training Grounds, 8-Player Multi-Part Boss Raids, Weapon Potential Cubing, Guild Citadels, and Daily Shared-Seed Mirror Rifts.
4. **Live-Ops & Retention:** Achievements & chat titles, seasonal portal events, Weekly Boss Rush mode, and Endless-Mode Seasonal Leaderboards.
---

## 5. Live Development Log (Maintained by Claude Code)

> **How this section works:** Claude Code updates it before every commit: what got finished, bugs it noticed (confirmed or suspected), what's left, and ideas. Sections 1–4 stay the design spec; this section tracks where the build actually is. Status icons: ✅ done & Studio-tested · 🟡 done but not fully verified · 🔨 in progress · ⬜ not started · 💡 idea only.

### 5.1 Changelog

| Date | Commit | Branch | What Changed |
| :--- | :--- | :--- | :--- |
| 2026-10-28 | `af46038` | `main` | Single-player World 1 loop complete (old Steps SP-1 → SP-6): landmarks, vista, climb rooms + acid, waypoints, Blacksmith, Mastery, weapons 4–8, relics + Star-Force, curses, session locking, quests, leaderboards, mobile controls, station panels. |
| 2026-10-29 | `e545dff` | `game-like-ui` | **Asset drop:** 96 game-icons.net icons (every weapon, ability, link skill, relic, Ascension node, quest, curse, upgrade card, currency + 15 UI glyphs), 16 Kenney VFX textures, 9 Kenney UI panel textures, and 29 Kenney sounds, all uploaded to Roblox. IDs are in `AssetRegistry.Icons / VfxTextures / UiTextures / Sounds`. |
| 2026-10-29 | `8ac6b82` | `game-like-ui` | **Spark Sanctum → skill tree.** **Quest Board → pinned parchment cards + WANTED posters.** New `Sfx.luau` (all buttons click; windows open / close with sounds). Station window enlarged 660×540 → 700×600. 4 unwired Ascension nodes flagged `ComingSoon` (shown as SOON, refused by the server). |

### 5.2 Game-Like UI Redesign (Branch `game-like-ui`)

**Why:** the player feedback was "too many words, words too small, feels like scrolling through a list, doesn't feel like a game".

**Design pillars (apply to every panel):**
1. **Icon first, words second.** Every item, node, quest and currency shows its uploaded icon. Text is a short label, never a paragraph.
2. **One big number per thing.** The count, price or level is large (TextSize 28–40); everything else is secondary.
3. **Details on tap.** The main view is a scene / grid; tapping something opens a detail card with the full description and the action button.
4. **Show progress visually.** Pips, rings, bars, stamps and glows, not "x / y" sentences.
5. **Every action gives feedback.** A sound (`Sfx.Play`), a pop / burst (`flare_01` bloom), and reward icons that fly toward the counter.
6. **Each station has its own material.** Parchment for the Quest Board, starlit stone for the Sanctum, iron and embers for the Forge, wood for the Blacksmith rack, marble and gold for the Hall of Champions.

| Panel | Status | Scene Concept |
| :--- | :--- | :--- |
| **Spark Sanctum** (Ascension) | ✅ | Skill tree with tier rows T1–T4 + ∞. Round icon nodes joined by glowing branches, locked tiers say "🔒 Rebirth X", level pips under each node, gold glow on affordable nodes. A detail card on the right holds the Upgrade button. Big Sparks counter + two-click Respec. |
| **Quest Board** | ✅ | 3 pinned parchment cards (icon disc, big "12 / 60", bar, reward icons, glowing Claim). Claiming flies the rewards and slams a DONE stamp. 2 WANTED bounty posters below. Countdown pill shows when the next dailies arrive. |
| **Star-Force** | 🔨 next | **Anvil scene.** A shelf of relic icons along the top (undiscovered = dark silhouette "?"). The selected relic sits on a big anvil with **5 star sockets** above it. Success chance is shown as a huge %, and the **pity meter is a "heat" bar** that glows hotter after each failure. A Safeguard shield toggles on the anvil. **Strike!** plays 3 hammer hits (`Forge_Hammer1–3`) with sparks, then either a star slams into its socket (`Forge_Success` + burst) or the sparks fizzle (`Forge_Fail`) and the heat rises. |
| **Blacksmith** | ⬜ | **Weapon rack.** 8 weapons hang on a wooden wall. Owned ones are bright, locked ones are black silhouettes with a price tag (Dust + Cores icons). Tapping one opens a card with Attack / Q / Passive icons and a Forge button (hammer). Equipped weapon gets a glowing frame. |
| **Legion Hall** | ⬜ | **Weapon carousel** with a big **Mastery ring** around the weapon icon (XP progress as a radial ring, level in the middle). **6 link-gem sockets** along the bottom: drag / tap a weapon's Link gem into a socket. Locked sockets show the Mastery needed. |
| **Hall of Champions** | ⬜ | **Podium** with the top 3 as avatar headshots (gold / silver / bronze pedestals), ranks 4–10 as hanging ribbons, 3 board tabs as banners. The player's own rank is pinned at the bottom. |
| **Rebirth** | ⬜ | **Before → After split.** Left is "now" (level, multiplier), right is "after" (new multiplier, +Sparks in huge gold), with a big pulsing portal button in the middle. Standard vs Keep-Everything as 2 big choice cards. |
| **Bag** | ⬜ | **Paper doll.** Character silhouette with Weapon, Starting Relic(s) and Link Skill slots around it; a live stat summary with icons; an inventory grid below with 1-tap equip. |
| **Rift Gate / Store / HUD** | ⬜ | Later: world-map style gate (World 1 lit, Worlds 2–8 shadowed), store cards with Robux badges, and the HUD fixes from 2.2. |

**Tech notes for whoever continues:**
* New scenes live in `client/Controllers/StationScenes.luau` and get routed through `StationPanels.Renderers`. **`UIController` is at Luau's 200-local limit**, so never add locals there.
* The kit `K` (passed into `StationPanels.Init` / `StationScenes.Init`) has `create`, `newLabel`, `newButton`, `round`, `outline`, `newBar`, `currencyIcon`, `formatNumber`, `profile()`, `renderStation`, `content()`, `newLayer`, etc.
* **Roblox does not render `Rotation` on GuiObjects inside a `ClipsDescendants` scroll frame.** Tilted cards and rotated stamps don't work inside station content.
* Test a panel without playing through: from the Server datamodel, fire `OpenStation` to the player with crafted `{Station=..., Data=...}`.

### 5.3 Known & Potential Bugs

| # | Severity | Status | Issue |
| :--- | :--- | :--- | :--- |
| B1 | Medium | Suspected | **Sounds not heard yet.** All 29 sounds preload with Success in Studio, but nobody has listened to them in a playtest. Volumes may need tuning (default 0.5). |
| B2 | High (launch) | Open | **Asset ownership.** All images and sounds were uploaded under the personal account (userId 94633131). If the game is ever published under a **group**, the assets must be re-uploaded to the group or given permission, or they'll show blank or silent. |
| B3 | High (legal) | Open | **game-icons.net is CC BY 3.0, which requires an in-game credit.** No credits screen exists yet. Credit text is in `assets/icons/picked/CREDITS.txt`. |
| B4 | Medium | Open | **Rojo drift risk.** Some Studio syncs were done by pushing scripts in directly because the Rojo plugin wasn't connected. Reconnect Rojo before the next Studio session so Studio exactly matches `src/`. |
| B5 | Low | Accepted | Any Sparks spent on the 4 now-`ComingSoon` nodes before `8ac6b82` stay spent (levels kept, no effect). Respec refunds them. No live players yet, so this is harmless. |
| B6 | Medium | Unverified | The Sanctum level-up burst and the Quest Board DONE-stamp were tested with **crafted** data. The test profile hasn't rebirthed, so a real buy has not been tested. |
| B7 | Medium | Unverified | The 700×600 station window relies on `UIScale` to fit phones; check on a real small-screen device (and with the mobile buttons on screen). |
| B8 | Low | Open | Legacy empty sound slots (`Hit`, `Crit`, `LevelUp`, `Pickup`, `BossRoar`, `Rebirth`) in `AssetRegistry.Sounds` still have no IDs, so code calling them is silent. |
| B9 | Low | Not ours | Console warning for `rbxassetid://203785492` comes from existing place content, not `src/`. |
| B10 | Security | Open | **Rotate the Open Cloud API key.** It was pasted into a chat once. It now lives in `~/.config/rift-rush/opencloud.key` (never commit it). |
| B11 | Medium | Open | Section 2.2's popup / combo / "Label"-flash HUD glitches are still unfixed. Popups may cover the new, bigger station window. |

### 5.4 Leftover Deliverables (Checklist)

**UI redesign:**
- [x] Spark Sanctum skill tree
- [x] Quest Board cards + bounty posters
- [ ] Star-Forge anvil scene *(next)*
- [ ] Blacksmith weapon rack
- [ ] Legion Hall carousel + link-gem sockets
- [ ] Hall of Champions podium
- [ ] Rebirth before → after
- [ ] Bag paper doll (replaces 2.2 item 2)
- [ ] Credits screen (fixes B3), probably behind a Settings gear
- [ ] Merge `game-like-ui` → `main` after the user reviews it

**Assets now in hand but not used yet:**
- [ ] 14 of 16 VFX textures (`slash_02`, `fire_01`, `spark_04`, `magic_01`…) for combat hit sparks, Burn / Shock visuals, dash trails and boss telegraphs in `CombatVFXController`
- [ ] 7 of 9 Kenney UI panel textures (wood / brown panels for the Blacksmith, buttons)
- [ ] `Combat_Swing1/2`, `Combat_Chop`, `Weapon_Equip`, `Gate_Open`, `Item_Drop` sounds → hook into combat, equip, Rift Gate and loot drops

**Carried over from Sections 2–3:** PL-1 (4 nodes), PL-2 (HUD fixes, run summary, settings, tutorial), PL-3 (rest of audio + music), PL-4 (balance pass, Opus), PL-5 (World 1 variety), PL-6 (real product IDs, cleanup, device tests), plus backing up the place file (models + ShardUI aren't in git).

### 5.5 Asset Pipeline (How to Add More Icons / Sounds)
1. Drop downloads into `assets/<models|ui|vfx|audio|icons>/` (git-ignored), then copy the chosen files into that folder's `picked/` with the game ID as the filename (e.g. `Relic_REL_09.png`, `Forge_Anvil.ogg`).
2. **Images:** upload via the Roblox Studio MCP `upload_image` (serve `picked/` on a localhost http server and pass the URLs).
3. **Audio:** upload via Open Cloud `POST /assets/v1/assets` (`assetType: Audio`, creator userId 94633131), then poll the operation for the asset ID.
4. Paste the IDs into `AssetRegistry` under the same key. UI code looks icons up by key (`Weapon_<Id>`, `Relic_<Id>`, `Asc_<NodeId>`, `Quest_<Id>`, `Cur_<Currency>`, `UI_<Glyph>`) and sounds by name (`Sfx.Play("Forge_Success")`).
5. If it's a CC BY asset, add the author to the credits list.

### 5.6 Creative Ideas Backlog (Claude's Suggestions — Not Committed Scope)
💡 These are pitches for the user to pick from, not promises.

**Make Haven Outpost feel alive**
* **Station keepers:** a small NPC at each station (a stout smith hammering at the Blacksmith, a robed sage at the Sanctum) who reacts when you buy something. The smith slams the anvil in the 3D world when you Star-Force.
* **The town grows with you:** each Rebirth tier lights another lantern line, raises a banner or opens a new market stall, so progress is visible without opening a menu.
* **Trophy wall:** first kill of each boss mounts its head / cap in the Hall of Champions. Endless-mode depth records go on a stone tablet.

**Collection & long-term goals**
* **Relic Codex:** a book with a page per relic. Undiscovered relics are silhouettes with a one-line riddle hinting where they drop. A 5★ relic gets a gold-leaf page. Completing a full row gives a cosmetic title.
* **Weapon Awakening:** at Paragon 25 / 50 / 100 the weapon model gets a glow, then particles, then a recolour. Free prestige that you can see.
* **Damage-number skins** from Mastery milestones and bounties (ties into the post-launch Damage Skins plan).

**Daily reasons to come back**
* **Rift Chest calendar:** a 7-day login streak chest on the Quest Board; day 7 is a Relic Shard bundle.
* **Rift Weather:** a daily global modifier shown at the Rift Gate ("Spore Storm: +30% enemies, +40% Dust"), a cheap way to add variety.
* **Weekly Rift Contract:** a big 3-step poster on the Quest Board ("Clear Room 10 with Hammer → without dashing → under 6 min") with a large payout.

**Juice & feel**
* **Hit-stop:** a 40–60 ms freeze on crits and boss hits, plus a `slash_02` spark texture at the impact point.
* **Loot fountain:** when extracting, banked currencies pour out of the Rift Anchor as icons into the HUD counters (reuses the Quest Board fly-to-counter code).
* **Star-Force streaks:** 3 successes in a row set the anvil on fire for the next strike (purely cosmetic, so it's not a gambling buff).

**Accessibility (directly answers the "words are too small" feedback)**
* A **Text Size** slider in Settings that scales a `UIScale` on all panels.
* A **colour-blind palette** for damage numbers (crit / burn / shock also differ by shape or icon, not just colour).
* A **Reduce Flashing** toggle that turns off screen shake, bursts and vignette flashes.

**Onboarding**
* A **spirit-fox guide** (the Summoning Bell familiar) leads brand-new players from spawn → Rift Gate → (after the first extraction) Blacksmith, as a waypoint you can follow, instead of text popups.
