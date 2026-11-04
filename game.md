*Note: the links and images in this document may point to external sources. Please review them before opening.*

# CLAUDE.md — Rift Rush Master Game Design & Implementation Spec (v3.2)

> **Status:** Single-Player Feature Complete (`main` @ `af46038`) + Scene UI Redesign (`game-like-ui`) + Viral Growth & Sub-Agent Architecture (v3.2)
> **In Progress (2026-10-30):** Game-like UI redesign on branch `game-like-ui` (all 8 station scenes, Settings & Credits, and HUD glitch fixes complete) — see **Section 5 (Live Development Log)** and **Section 6 (Viral Mechanics & Sub-Agent Workflow)**.
> **Platform:** Roblox (PC, Mobile, Console)
> **Genre:** 2.5D PvE Action Roguelite with Endless Permanent Progression, RNG Auras & Rebirths
> **Working Title:** Rift Rush
> **Repository:** [ArrickGit/Rift-Rush](https://github.com/ArrickGit/Rift-Rush)
> **Codebase Snapshot:** 18 Server Services, 13 Client Controllers (incl. `Sfx` + `StationScenes`), 16 Shared Modules
> **Document Purpose:** Serve as the single source of truth (`CLAUDE.md` / `game.md`) for Claude Code (and its research sub-agents) to finish the remaining 4 unwired Ascension nodes, audio hooks, balance pass, and viral retention mechanics.

---

## 0. AI Agent Execution Rules & Model Selection Guidelines

> **CRITICAL INSTRUCTIONS FOR CLAUDE CODE — READ BEFORE EVERY ACTION:**

### 0.1 Mandatory Coding & Architecture Standards

1. **Strict Luau Typing:** Every `.luau` script MUST begin with `--!strict` and use explicit type annotations for function parameters, return types, and data structures.

2. **Server Authority:** Never trust the client for damage calculations, currency payouts, Weapon Mastery XP, Rebirth eligibility, Ascension Shop purchases, environmental hazard damage, or room completion. Use `ReplicatedStorage.Shared.FormulaEngine` on the server as the single source of truth.

3. **Preserve Working Systems (`af46038` & `game-like-ui`):** All 8 weapons, 8 relics, 9 town stations, scene-based UI panels, Star-Force upgrading, Weapon Mastery/Paragon, and DataStore profile locking are already built and verified in Studio playtesting. Do NOT rewrite or break working services when adding polish, wiring the final 4 Ascension Shop nodes, or adding viral hooks.

4. **Respect `UIController` 200-Local Limit:** `UIController.luau` is near Luau's 200 local-variable cap. Never add new local variables to `UIController.luau`; place new UI scenes or helpers in separate modules routed through `StationPanels` or `SceneKit`.

### 0.2 Model Selection & Sub-Agent Guidelines

* **Low-Tier Sub-Agents (`haiku` or `sonnet` via Task tool):** Use 1–2 lightweight sub-agents for **read-only codebase audits, viral mechanic design tables, upgrade card synergy brainstorming, and DPS spreadsheet math** (see **Section 7** for ready-to-run sub-agent prompts). Sub-agents must NEVER edit files directly—they return structured JSON/Markdown specs to the Main Agent.

* **Main Agent Default (`sonnet`):** Use **Sonnet** as the main orchestrator to write and edit `.luau` files based on the sub-agents' findings.

* **When to Switch Main Agent to `opus`:** Let the user know to switch to **Opus** only when performing the **Comprehensive Game-Wide Balance Pass (Step PL-4)** or debugging complex multi-service concurrency issues.

---

## 1. Current Codebase Status Audit (`main` @ `af46038` + `game-like-ui`)

> **VERIFIED IN STUDIO PLAYTEST (18 Server Services, 13 Client Controllers, 16 Shared Modules):**

### 1.1 Movement, Camera & Controls (Done & Tested)

* **Side-on 2.5D Lock:** Players and enemies are locked to the $Z = 0$ plane with a narrow side camera that smoothly follows the player vertically and shakes on hits (`Movement25DController`, `Camera25DController`, `Physics25D`).

* **Movement Mechanics:** Walk, double jump (triple jump via Ascension node), drop down through platforms (`Down + Jump`), jump pads launching \~30 studs upward, and ground dash / air "flash jump" with recharging charges.

* **Cross-Platform Controls:**

  * **Keyboard & Gamepad:** `Q` / `LB` / `RB` for active ability; `I` / `B` / `Select` for the Bag.

  * **Mobile (`MobileControlsController`):** Floating virtual joystick plus Attack, `Q` (with cooldown display), Dash, and Jump buttons *(built in code; needs real mobile device verification)*.

* **Attack Feel:** Character arm swings on every attack, and Gauntlets punches lunge the player forward.

### 1.2 All 8 Playable Weapons (Done & Tested — Each Cleared a Room)

Every weapon is physically welded into the character's right hand both in Town and inside Portal Runs (`WeaponHoldService`).

| Weapon | Unlock Cost | Basic Attack | `Q` Ability | Innate Passive | Link Skill (Mastery 10 / 20) | 
 | ----- | ----- | ----- | ----- | ----- | ----- | 
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

* **Status Effects:** *Burn* (DoT that spreads on enemy death) and *Shock* (hits chain lightning to nearby enemies).

* **Combo Counter:** $+1\%$ damage per 10 hits, up to $+50\%$.

* **Invincibility Frames & Shields:** Short i-frame window after dashing or taking a hit; shields absorb damage before HP.

* **Shadow Line Extra Hits:** Bonus shadow hits triggered via the `Limit Breaker` Ascension node.

* **Floating Damage Numbers & Combat VFX (`CombatVFXController`):** Color-coded damage numbers by type, summoned spirit foxes, orbiting coins, erupting rock pillars, card draw visuals, and green screen vignette flash when touching acid.

### 1.4 Enemies & Bosses — World 1: Mushroom Wilds (Done & Tested)

* **Regular Enemies:** *Spore Blob* and *Mushroom Hopper*, plus tougher Elite variants that hop onto platforms and deal contact damage.

* **Bosses:** *Spore Golem* (Room 5) and *Mushroom Titan* (Room 10), featuring telegraphed warning zones, $50\%$ HP enraged phases, and deflectable *Spore Boulders* (`"EXPOSED - ATTACK!"` stun window).

* **Procedural Animation:** Code-driven squash-and-stretch, hit-flinching, and overhead HP bars on imported 3D models.

### 1.5 Runs, Hazards, Upgrades & Curses (Done & Tested)

* **10 Room Layouts + Endless Mode:** Combat rooms, 2 climbing rooms with rising acid (exit at the top), a Treasure room, and 2 boss rooms. Endless continuation past Room 10 with bosses every 5th room.

* **Bubbling Acid Flood (`HazardService`, `AmbientController`):** Multi-layered bubbling flood rendered on client while the server applies $8\%$ **Max HP damage per tick** and an upward lava bounce.

* **At-Risk Loot Pouch & Rift Anchors:** *Rift Dust*, *Boss Cores*, and *Relic Shards* sit in an at-risk pouch until banked at a **Rift Anchor**, where players choose to **Extract** or **Keep Pushing**.

* **Tiered Defeat Loss:** $30\% / 50\% / 75\%$ pouch loss depending on depth, with Defeat Screen options for Accept Defeat, Anchor Token Rewind/Insure, or Robux Revive/Rewind/Insure.

* **10 Upgrade Cards & 5 Curses:** Common to Legendary cards with Reroll and Banish; 5 Curses offered on Treasure room altars (up to 4 per run).

* **Corruption Tiers:** Selectable at the Rift Gate; beating Room 10 unlocks the next Corruption Tier or World.

### 1.6 Relics & Star-Force System (`RelicService` — Done & Tested)

* **8 Working Relics:** *Frost Heart, Treasure Tooth, Thunder Boots, Hungry Coin, Phoenix Feather, Vampiric Fang, Broken Crown, Volatile Hourglass*.

* **Drop Rates & Shard Conversion:** $35\%$ from Room 5 boss, $100\%$ from Room 10 boss, $25\%$ from chests; duplicates grant **+5 Relic Shards**.

* **Non-Destructive Star-Force (**$1\star \rightarrow 5\star$**):** Failed strikes never lose stars and add $+25\%$ Pity heat to the next attempt; Safeguard refunds shards on failure.

* **Starting Relics:** Carry 1 into every run (expandable via `Twin Relic Vessel` Ascension node and Gamepass).

### 1.7 Permanent Progression (Done & Tested)

* **Hunter Level & Rebirth:** 10 structured Rebirth tiers + endless scaling (**Standard Rebirth**, **Keep Everything Rebirth**, and **Robux Instant Rebirth**).

* **Weapon Mastery & Paragon (`MasteryService`):** Levels $1 \rightarrow 20$ plus up to $979$ Paragon ranks; Link Skills unlock at Mastery 10 and upgrade at Mastery 20 (up to 6 active slots).

* **Ascension Shop (17 Nodes Total):** **13 nodes are fully wired and functional**, including Respec. **4 nodes are flagged `ComingSoon = true`** until wired (see Section 2.1).

### 1.8 Town Hub (Haven Outpost) & Scene UI Redesign (`game-like-ui` — Done & Tested)

* **9 Working Stations on Custom Landmarks (`LandmarkBuilder`)** with persistent waypoints and high-fantasy sky/island vistas (`VistaBuilder`).

* **All 8 Station Windows Rebuilt as Visual Scenes (`game-like-ui`):** Spark Sanctum skill tree, Quest Board parchment cards/bounties, Star-Forge anvil scene, Blacksmith weapon rack, Legion Hall mastery ring, Hall of Champions podium, Rebirth Before/After with two-tap confirm, Bag paper doll, Rift Gate world map, and Settings & Credits screen.

* **HUD Glitches Fixed (`game-like-ui`):** Toasts stack cleanly beside open windows, Combo Counter sits under vitals on the left, and `"Label"` flash is eliminated.

### 1.9 Saving, Backend & Dev Tools (Done & Tested Online)

* **DataStore Persistence, Session Locking, 90s Autosave & Safe Leave Payout.**

* **Lifetime Stats Tracking & Monetization Scaffolding** (13 Products, 8 Gamepasses wired; IDs currently `0`).

* **Studio Test Suite (`RiftDev`).**

---

## 2. Remaining Pre-Launch Core Tasks (Steps PL-1 to PL-6)

### 2.1 The 4 Unwired Ascension Shop Nodes (`ComingSoon = true` in `AscensionShopConfig`)

> **Verified Node IDs & Service Names (`AscensionShopConfig` & `RunManagerService`):**
>
> * `AS_T1_03` = **Vacuum Aura** (3 levels)
>
> * `AS_T1_04` = **Headstart Blessing** (3 levels: Common+ $\rightarrow$ Rare+ $\rightarrow$ Epic+)
>
> * `AS_T3_01` = **Elemental Crit Overload** (3 levels: $33\% / 66\% / 100\%$ of Crit Damage)
>
> * `AS_T4_02` = **Miracle Evolution** (1 level: $15\%$ chance for Double Upgrade Pick + guaranteed on Boss rooms)
>
> * *When wiring each node below, remove its `ComingSoon = true` flag in `AscensionShopConfig.luau`.*

1. **Vacuum Aura (`AS_T1_03` — Loot Magnet & Drop Orbs):**

   * Spawn lightweight client-rendered glowing loot orbs (*Rift Dust* crystals, *Boss Cores*, *HP globes*) when enemies die or chests open that scatter briefly and magnetically accelerate toward the player within a base pickup radius of $14\text{ studs}$. Each level increases pickup radius by $+35\%$ (full-room pull at Lv. 3) and grants $+2\%$ bonus *Rift Dust*.

2. **Headstart Blessing (`AS_T1_04` — Free Room 1 Upgrade Card):**

   * In `RunManagerService`, when Room 1 starts, check if the player owns `AS_T1_04` (`Level >= 1`). If owned, trigger a bonus **Headstart Upgrade Card Selection** where cards have a minimum rarity floor of **Common+ (Lv. 1)**, **Rare+ (Lv. 2)**, or **Epic+ (Lv. 3)**.

3. **Elemental Crit Overload (`AS_T3_01` — Status Effects Can Crit):**

   * In `CombatService` status tick/proc evaluation, if the attacker owns `AS_T3_01`, roll `CritRate` on every *Burn* tick, *Shock* chain, and *Arcane Nova* burst. On crit, multiply status damage by `1 + (CritDamageBonus * (NodeLevel / 3))` and display an orange-gold crit status number.

4. **Miracle Evolution (`AS_T4_02` — Double Upgrade Card Picks):**

   * When rolling a room-clear Upgrade Selection in `RunManagerService`, if the player owns `AS_T4_02`, roll a $15\%$ chance (and $100\%$ on Boss Rooms 5 and 10) to display a golden `"✨ MIRACLE EVOLUTION — PICK 2 UPGRADES!"` banner, letting the player pick **2 cards** before closing.

---

### 2.2 Remaining UI & Onboarding Polish (Step PL-2)

* **Completed on `game-like-ui`:** All 8 station scenes, Bag paper-doll redesign, Settings & Credits screen, and the 3 HUD glitch fixes are **done**.

* **Still Needed for PL-2:**

  1. **HUD Gear Button:** Add a direct `⚙` button on the HUD / Town side menu so players don't have to open the Bag first to find Settings (fixes `B26`).

  2. **Hide Combo Counter on Defeat Screen:** Clear or hide the Combo Counter when the Rift Collapse (defeat) screen opens (fixes `B27`).

  3. **End-of-Run Summary Screen:** Shown upon **Successful Extraction**, displaying rooms cleared, time elapsed, enemies/bosses slain, banked currencies (*Rift Dust*, *Boss Cores*, *Relic Shards*) with flying icon juice, Weapon Mastery XP gained, and a `"Return to Haven Outpost"` button.

  4. **60-Second Spirit-Fox Onboarding Guide:** For brand-new players (`RoomsCleared == 0`), spawn a glowing **Spirit Fox guide** (or golden trail) that leads them from Town spawn $\rightarrow$ Rift Gate, shows brief control prompts in Room 1, and guides them to the Blacksmith after extraction.

---

### 2.3 Remaining Audio Hooks & Music (`Sfx.luau` / `AudioController` — Step PL-3)

* **Completed on `game-like-ui`:** 29 Kenney UI/forge/quest/combat sounds are uploaded in `AssetRegistry.Sounds` and wired into UI buttons, station open/close, Quest Board, Star-Forge, Blacksmith, and Settings volume scaling (`Sfx.SetVolumeScale`).

* **Still Needed for PL-3:**

  1. Hook the already-uploaded `Combat_Swing1/2`, `Combat_Chop`, `Weapon_Equip`, `Gate_Open`, and `Item_Drop` sounds into `CombatVFXController`, `WeaponHoldService`, Rift Gate, and loot drops with slight pitch randomization (`0.92` to `1.08`).

  2. Fill the 6 empty legacy sound slots in `AssetRegistry.Sounds` (`Hit`, `Crit`, `LevelUp`, `Pickup`, `BossRoar`, `Rebirth`) using uploaded IDs or pitch-shifted combinations of existing sounds.

  3. Add looping Background Music (Town BGM, Combat Run BGM, Boss BGM) with a **Music Volume** pill in `SettingsScene.luau`.

---

### 2.4 Pre-Launch Balance Pass Targets (Step PL-4 — Recommend Opus)

> **CRITICAL ISSUE CONFIRMED AGAIN (`B25`):** An idle player in Room 1 dies within \~12 seconds.

1. **Player Survivability & Contact Damage Tuning:** Reduce World 1 normal enemy contact damage by $\sim 35\%$ and add a $0.85\text{s}$ post-hit contact immunity window so a new player takes $8-10$ hits to die.

2. **Weapon DPS & Cooldown Parity:** Balance all 8 weapons in `WeaponConfig` so slower AoE weapons (*Hammer*, *Greatsword*) match fast weapons (*Daggers*, *Gauntlets*, *Bow*), and tune `Q` cooldowns between $5\text{s}$ and $9\text{s}$.

3. **Boss HP, Acid Damage & Economy:** Tune *Spore Golem* ($45-60\text{s}$), *Mushroom Titan* ($75-100\text{s}$), Rising Acid ($6\%$ Max HP per `0.5s` tick), Curse trade-offs ($+35\%$ to $+60\%$ reward/damage bonus), and Star-Force costs.

---

## 3. Pre-Launch Execution Roadmap (Steps PL-1 to PL-6)

| Step | Focus Area | Exact Tasks to Complete | Model | 
 | ----- | ----- | ----- | ----- | 
| **Step PL-1: Wire Final 4 Ascension Nodes** | `AS_T1_03`, `AS_T1_04`, `AS_T3_01`, `AS_T4_02` | Wire `Vacuum Aura`, `Headstart Blessing`, `Elemental Crit Overload`, and `Miracle Evolution` in `RunManagerService` & `CombatService`, then remove `ComingSoon = true`. | **Sonnet** | 
| **Step PL-2: Run Summary, Onboarding & Minor UI Fixes** | Merge `game-like-ui`, Run Summary, Spirit-Fox Guide, `B26`/`B27` | 1\. Merge `game-like-ui` to `main`.<br>2. Add HUD Settings icon (`B26`) and hide combo on defeat (`B27`).<br>3. Add **Run Summary Screen** on extraction and **Spirit-Fox Onboarding Guide**. | **Sonnet** | 
| **Step PL-3: Combat SFX Hooks & Music** | `Sfx.luau`, `CombatVFXController`, Music | Hook uploaded combat/equip/drop sounds into gameplay, fill remaining 6 sound keys, add Town/Combat/Boss music loops, and add Music Volume to Settings. | **Sonnet** | 
| **Step PL-4: Game-Wide Balance Pass** | Fix 12s idle death (`B25`), 8 Weapons, Bosses, Economy | Tune enemy contact damage + i-frames, weapon DPS parity, boss HP, acid tick damage, curse multipliers, and Star-Force costs. | **Opus** | 
| **Step PL-5: Viral Hooks & World 1 Variety** | See **Section 6** (Weapon Auras, God-Build Synergies, AFK Sanctuary) | Implement the top viral retention hooks from **Section 6** + add 10 wild transformative Upgrade Cards and new room variations. | **Sonnet** (+ Sub-Agents) | 
| **Step PL-6: Launch Prep & Housekeeping** | Real Robux IDs, API Key Rotation (`B10`), Mobile Test | 1\. Rotate Open Cloud API key (`B10`) & back up `.rbxl` file.<br>2. Set real Developer Product & Gamepass IDs.<br>3. Remove unused `DevRunPortal` script. | **Sonnet** | 

---

## 4. Post-Launch Expansion Roadmap

1. **Co-op Party UI at Rift Gate** (1–4 player party create/join modal wired to existing server party & *Sidekick Sync* scaling).

2. **Worlds 2–8 Content Updates** (*Toy Kingdom, Haunted Metro, Frozen Citadel, Neon Grid, Dessert Wastes, Sunken Archive, Volcanic Factory*).

3. **Endgame Systems** (8-Player Multi-Part Boss Raids, Guild Citadels, Daily Shared-Seed Mirror Rifts).

---

## 5. Live Development Log (Maintained by Claude Code)

> **How this section works:** Claude Code updates it before every commit: what got finished, bugs it noticed (confirmed or suspected), what's left, and ideas. Status icons: ✅ done & Studio-tested · 🟡 done but not fully verified · 🔨 in progress · ⬜ not started · 💡 idea only.

### 5.1 Changelog

| Date | Commit | Branch | What Changed | 
 | ----- | ----- | ----- | ----- | 
| 2026-10-28 | `af46038` | `main` | Single-player World 1 loop complete (old Steps SP-1 $\rightarrow$ SP-6): landmarks, vista, climb rooms + acid, waypoints, Blacksmith, Mastery, weapons 4–8, relics + Star-Force, curses, session locking, quests, leaderboards, mobile controls, station panels. | 
| 2026-10-29 | `e545dff` | `game-like-ui` | **Asset drop:** 96 game-icons.net icons, 16 Kenney VFX textures, 9 Kenney UI panel textures, and 29 Kenney sounds uploaded to Roblox and indexed in `AssetRegistry`. | 
| 2026-10-29 | `8ac6b82` | `game-like-ui` | **Spark Sanctum** $\rightarrow$ **skill tree.** **Quest Board** $\rightarrow$ **pinned parchment cards + WANTED posters.** New `Sfx.luau`. Station window enlarged $660\times 540 \rightarrow 700\times 600$. 4 unwired Ascension nodes flagged `ComingSoon`. | 
| 2026-10-30 | `146f53c` | `game-like-ui` | Live log (Section 5) added; Ascension node IDs in 2.1 corrected against the code. | 
| 2026-10-30 | `a284759` | `game-like-ui` | **Star-Forge** $\rightarrow$ **anvil scene** (`StarForgeScene.luau`). Shared helpers moved to `SceneKit.luau`. **Bug fix:** Escaped `%` signs in *Broken Crown* (`REL_07`) description (`B12`). | 
| 2026-10-30 | `13ca7f0` | `game-like-ui` | **Blacksmith** $\rightarrow$ **weapon rack** (`BlacksmithScene.luau`). | 
| 2026-10-30 | `5065462` | `game-like-ui` | **Legion Hall** $\rightarrow$ **mastery shrine** (`LegionScene.luau`). | 
| 2026-10-30 | `8e64c65` | `game-like-ui` | **Hall of Champions** $\rightarrow$ **podium** (`HallScene.luau`) with `rbxthumb://` avatar headshots. | 
| 2026-10-30 | `b99fe86` | `game-like-ui` | **Rebirth** $\rightarrow$ **before / after** (`RebirthScene.luau`) with two-tap confirmation. | 
| 2026-10-30 | `54cd527` | `game-like-ui` | **Bag** $\rightarrow$ **paper doll** (`BagScene.luau`). All 8 station windows are now visual scenes; `StationPanels` reduced from \~420 to 159 lines. | 
| 2026-10-30 | `fa8630c` | `game-like-ui` | **Rift Gate** $\rightarrow$ **world map** (`RiftGateScene.luau`). | 
| 2026-10-30 | `708eb77` | `game-like-ui` | **Settings & Credits screen** (`SettingsScene.luau`), fixing `B3` CC BY 3.0 attribution. | 
| 2026-10-30 | *(latest)* | `game-like-ui` | **Fixed the 3 HUD glitches from 2.2** (`B11`, `B16`): Toasts stack at bottom-right beside open windows, Combo Counter moved to left under vitals, and `"Label"` flash eliminated. | 

### 5.2 Technical Notes & Known Bugs Summary

* **Key Architectural Guardrails:**

  * `UIController` is at Luau's 200-local limit—never add locals there; put new scenes in separate modules using `SceneKit.luau`.

  * Roblox does not render `Rotation` on GuiObjects inside a `ClipsDescendants` scrolling frame; render rotating elements on `SceneKit.overlay()`.

* **Open Bugs to Address:** `B1` (verify audio volumes in playtest), `B2` (group asset ownership if published under a group), `B8` (6 empty legacy sound slots), `B10` (**rotate Open Cloud API key**), `B25` (**idle player dies in 12s in Room 1 — fix in Step PL-4**), `B26` (add HUD shortcut button for Settings), `B27` (hide combo counter behind defeat screen).

---

## 6. Viral Growth, TikTok Spectacle & Roblox Mass-Appeal Mechanics (Solving the "Too Niche" Problem)

> **WHY THIS SECTION EXISTS:** Pure single-player roguelites can feel too niche on Roblox if players only grind deterministic shop upgrades alone in private rooms. On Roblox, games blow up through **3 viral loops**:
>
> 1. **RNG Jackpot Moments & Town Hub Flexing** (*Sol's RNG / Blox Fruits / Pet Sim* appeal — rolling something `1 in 1,000` with a dramatic screen cutscene and flexing a giant glowing aura/weapon in Town).
>
> 2. **Absurd "God-Build" Screen Spectacle** (*Vampire Survivors* appeal — upgrades that visually multiply projectiles, size, and hit-counts until the player clears whole rooms in 1 second of rainbow chaos, making instant TikTok/Shorts clips).
>
> 3. **Zero-Friction Casual / AFK Progression** (giving tired or mobile players a way to hang out in Haven Outpost, flex their titles/auras, and passively earn *Rift Dust* + Mastery XP, skyrocketing **Average Session Length** for the Roblox Discovery algorithm).

### 6.1 Viral Feature 1: Weapon Enchantment / Aura Rolling at the Blacksmith ("Rift Reforging")

Right now, once a player buys a weapon at the Blacksmith (`400 Dust + 2 Cores`), it is identical to everyone else's weapon.

* **The Viral Hook:** Add a **"Reforge Aura / Enchant"** button in `BlacksmithScene.luau` (costing *Rift Dust* or a *Reforge Token* dropped by bosses).

* **How It Works:** Rolling gives the weapon a tiered **Visual Aura + Prefix Stat Multiplier** with visible odds:

  * **Common (60%):** *Sharp* ($+10\%$ Dmg, subtle white sheen)

  * **Rare (25%):** *Stormforged* ($+25\%$ Dmg, $+10\%$ Atk Speed, crackling blue lightning particles on the weapon in hand)

  * **Epic (10%):** *Void-Touched* ($+50\%$ Dmg, $+1$ Extra Projectile/Slash Wave, purple nebula trail)

  * **Legendary (4%):** *Celestial* ($+100\%$ Dmg, $+20\%$ Crit Rate, golden wings/halo particle aura around the player in Town)

  * **Mythic (1% — Server Chat Announcement + Cutscene Flash):** *Rift Sovereign* ($+200\%$ Dmg, **Size** $+40\%$, screen-flash cutaway on roll, and a global server toast: `"🔥 [Player] just forged a MYTHIC [Rift Sovereign Greatsword] (1 in 100)!"`)

* **Why It Goes Viral:** Players become obsessed with rolling a *Celestial* or *Rift Sovereign* weapon to show off in Haven Outpost, and the server-wide chat broadcast creates instant FOMO.

### 6.2 Viral Feature 2: "Overclocked / Mutated" Screen-Filling Upgrade Cards (TikTok Clip Fuel)

Right now, the 10 Upgrade Cards in `UpgradePoolConfig` are balanced, modest RPG buffs. To make runs feel insanely fun and clip-worthy, add **"Screen-Breaking Mutator Cards"**:

* **Examples of Viral Upgrade Cards to Add:**

  * **Gigantism (`Legendary`):** Your projectiles, slashes, rock pillars, and summoned Spirit Foxes become $+100\%$ **LARGER** and deal $+40\%$ damage.

  * **Echo Chamber (`Epic`):** Every `Q` ability casts **twice** with a $0.25\text{s}$ echo delay (fireballs become double fireballs; 2 Spirit Foxes become 4 Spirit Foxes!).

  * **Chain Reaction (`Legendary`):** Killing any enemy triggers a miniature *Arcane Nova* explosion that chains across packs of mobs.

  * **Ricochet Frenzy (`Rare`):** All attacks and projectiles bounce $+2$ additional times between platforms and enemies.

  * **Golden Piñata (`Epic`):** Critical hits have a $20\%$ chance to burst enemies into a fountain of flying *Rift Dust* orbs (`flare_01` + coin burst).

### 6.3 Viral Feature 3: Haven Outpost "Sacred Rift Campfire / AFK Training Sanctuary"

Roblox's front-page algorithm heavily rewards **Session Length** and **Concurrent Players in Town**.

* **How It Works:** Place a glowing **Sacred Rift Sanctuary Circle** in the center of Haven Outpost (near the spawn/landmarks).

* When players stand inside the circle in Town, their character automatically performs rhythmic meditation/weapon-practice swings, displaying their equipped Weapon Aura and floating title while earning **passive *Rift Dust* and Weapon Mastery XP every 5 seconds** (scaled by their Rebirth tier).

* **Social Multiplier:** For every other player standing in the Sanctuary Circle with you, everyone gets **+10% AFK Training Speed** (up to $+50\%$). This encourages friends to invite each other into the server just to hang out, chat, and flex their gear!

### 6.4 Viral Feature 4: "Public Town Boss Invasion" Every 15 Minutes

Since runs are currently solo, players never get to fight *together* in the Town Hub.

* **How It Works:** Every 15 minutes in Haven Outpost, the sky turns purple for 90 seconds (`"⚠️ WORLD RIFT BREACH IN HAVEN OUTPOST!"`) and a giant **Corrupted Rift Colossus** spawns right in the Town Hub!

* **Zero New Co-op Party Code Needed:** Every player currently in the Town server can whale on the Town Boss together using their equipped weapons, showing off their damage numbers and auras to everyone in the server. When defeated (or when 90s ends), everyone who dealt damage gets a shower of *Rift Dust*, *Relic Shards*, and a chance at a Relic!

### 6.5 Viral Feature 5: Overhead Flex Banners & Collectible Damage Number Skins

* **Overhead Town Flex Tag:** Above every player's head in Haven Outpost, display a sleek `BillboardGui` badge showing:

  * `[Rebirth V ⭐] PlayerName`

  * Title unlocked from achievements/codex (e.g., `"Mushroom Slayer"`, `"Star-Forge Gambler"`, `"Rift Sovereign"`)

  * Their Highest Endless Room Badge (`"🔥 Best: Room 35"`).

* **Damage Number Skins (`CombatVFXController`):** Add 5 unlockable Damage Number Skins (Classic Maple Orange, Neon Cyber Cyan, Golden Crit Fountain, Void Purple, Rainbow Mythic) that change the font/gradient of floating combat numbers—a massive nostalgic hook for *MapleStory* and Roblox anime fans.

---

## 7. Multi-Agent Research & Implementation Workflow (2 Low-Tier Sub-Agents + Main Claude)

> **HOW TO RUN THIS IN CLAUDE CODE:**
> You can tell Claude Code to spawn **2 lightweight sub-agents (`haiku` or `sonnet` via the `Task` tool)** in parallel to inspect your code and design the exact tables/math, and then have your **Main Claude Agent** implement the changes cleanly.

### 7.1 Sub-Agent 1 Role: "Viral Hook & Synergy Architect" (Read-Only Sub-Agent)

* **What Sub-Agent 1 Does:** Reads `WeaponConfig.luau`, `UpgradePoolConfig.luau`, `RelicConfig.luau`, and `BlacksmithScene.luau`. It designs:

  1. The exact **10 new "Screen-Breaking" Upgrade Cards** (Gigantism, Echo Chamber, Chain Reaction, etc.) with balanced numbers that hook into existing `CombatService` attributes without breaking server performance.

  2. The **Weapon Reforge / Enchant Aura System** (5 rarity tiers, roll odds, Dust costs, visual particle/trail specs from `AssetRegistry.VfxTextures`, and stat multipliers).

* **Output:** Returns a ready-to-code Luau specification table to the Main Agent.

### 7.2 Sub-Agent 2 Role: "Combat Feel, Onboarding & Balance Auditor" (Read-Only Sub-Agent)

* **What Sub-Agent 2 Does:** Reads `FormulaEngine.luau`, `EnemyConfig.luau`, `CombatService.luau`, `CombatVFXController.luau`, and `Sfx.luau`. It audits:

  1. **Why the player dies in 12 seconds (`B25`)** and calculates the exact HP, contact damage, and i-frame numbers for Rooms 1–10.

  2. **The "Game Juice" Audit:** Identifies every exact line in `CombatVFXController.luau` and `CombatService.luau` where the 10 unused Kenney VFX textures (`slash_02`, `spark_04`, `magic_01`, `trace_02`), the 40ms crit hit-stop, and the uploaded combat sounds (`Combat_Swing1/2`, `Combat_Chop`, `Item_Drop`) should be plugged in.

* **Output:** Returns an exact file-by-file patch checklist with line numbers and math replacements to the Main Agent.

### 7.3 Ready-to-Paste Prompt for Claude Code (Spawning the 2 Sub-Agents + Main Builder)

Copy and paste this prompt into Claude Code whenever you want to run the 2 sub-agents and execute the viral & balance upgrades:

```
Read CLAUDE.md Sections 2, 6, and 7. Before editing any code, spawn 2 parallel read-only research sub-agents (using a fast/low-tier model):

1. Sub-Agent 1 (Viral & Synergy Architect): Read WeaponConfig, UpgradePoolConfig, RelicConfig, and BlacksmithScene. Design the exact data tables and implementation spec for:
   - 10 new "Screen-Breaking" Upgrade Cards (like Gigantism, Echo Chamber double-cast, Chain Reaction, Ricochet, Golden Piñata) that make builds look explosive and viral.
   - A Weapon Reforge / Aura Enchant rolling system in the Blacksmith (Common to Mythic 1% roll with weapon particle glow, server announcement toast, and bonus stats) + Overhead Player Flex Badges in Town (Rebirth tier + Deepest Room).

2. Sub-Agent 2 (Balance & Combat Juice Auditor): Read FormulaEngine, EnemyConfig, CombatService, CombatVFXController, and Sfx. Calculate the exact number changes to fix Bug B25 (idle player dying in 12s in Room 1), balance all 8 weapons, and map out the exact lines to hook up our unused Kenney VFX textures (slash_02, spark_04, magic_01) and uploaded combat sounds (Combat_Swing1/2, Combat_Chop, Item_Drop).

Once both sub-agents return their reports, review their findings as the Main Agent and implement the changes step-by-step while keeping all existing systems intact.

```