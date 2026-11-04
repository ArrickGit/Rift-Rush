*Note: the links and images in this document may point to external sources. Please review them before opening.*

# CLAUDE.md — Rift Rush Master Game Design & Implementation Spec (v3.5)

> **Status:** Single-Player Loop + Scene UI + Viral Sprint Part 1 Complete (`main` @ `7a0ea93`) — Now Executing **Section 4: "First 60 Seconds" Player Attraction Overhaul**
> **Latest Commits (`2026-11-04`):** Balance Pass (`bab6ba0`), Combat Juice & SFX (`2b23979`), 10 Screen-Breaking Upgrade Cards (`3339222`), Blacksmith Weapon Reforge & Auras (`1a273f3`), and Town Overhead Flex Badges (`7a0ea93`).
> **Platform:** Roblox (PC, Mobile, Console)
> **Genre:** 2.5D PvE Action Roguelite with Endless Permanent Progression, RNG Weapon Reforging & Rebirths
> **Working Title:** Rift Rush
> **Repository:** [ArrickGit/Rift-Rush](https://github.com/ArrickGit/Rift-Rush)
> **Codebase Snapshot:** 19 Server Services (incl. `FlexBadgeService`), 14 Client Controllers (incl. `ReforgeSection`, `Sfx`, `StationScenes`), 17 Shared Modules (incl. `ReforgeConfig`)
> **Document Purpose:** Serve as the single source of truth (`CLAUDE.md` / `game.md`) tracking completed systems, sub-agent findings, and the high-impact "First 60 Seconds" onboarding & dopamine overhaul.

---

## 0. AI Agent Execution Rules & Model Selection Guidelines

> **CRITICAL INSTRUCTIONS FOR CLAUDE CODE — READ BEFORE EVERY ACTION:**

### 0.1 Mandatory Coding & Architecture Standards
1. **Strict Luau Typing:** Every `.luau` script MUST begin with `--!strict` and use explicit type annotations for function parameters, return types, and data structures.
2. **Server Authority:** Never trust the client for damage calculations, currency payouts, Weapon Mastery XP, Rebirth eligibility, Ascension Shop purchases, Reforge rolls, environmental hazard damage, or room completion. Use `ReplicatedStorage.Shared.FormulaEngine` on the server as the single source of truth.
3. **Respect Module 200-Local Limits:**
   * `UIController.luau` is at Luau's 200 local-variable cap—never add locals there; put new scenes/sections in separate modules (`SceneKit`, `ReforgeSection`, etc.).
   * `CombatService.luau` is at **184 / 200 locals**—consolidate any new constants into existing tables (`CARD`, etc.) or helper modules rather than declaring new top-level `local` variables.

### 0.2 Model Selection & Sub-Agent Guidelines
* **Low-Tier Sub-Agents (`haiku` or `sonnet` via Task tool):** Use 1–2 read-only sub-agents for codebase audits, balance math checks, and feature specs. Sub-agents must NEVER edit files directly.
* **Main Agent Default (`sonnet`):** Default to **Sonnet** for standard feature work, UI polish, and wiring.
* **When to Switch Main Agent to `opus`:** Recommend switching to **Opus** for multi-service architectural changes or deep combat/balance passes.

---

## 1. Current Codebase Status Audit (`main` @ `7a0ea93`)

> **VERIFIED IN STUDIO PLAYTEST (19 Server Services, 14 Client Controllers, 17 Shared Modules):**

### 1.1 Movement, Camera & Controls (Done & Tested)
* **Side-on 2.5D Lock:** Players and enemies are locked to the $Z = 0$ plane with a vertical-tracking side camera and hit-shake (`Movement25DController`, `Camera25DController`, `Physics25D`).
* **Movement Mechanics:** Walk, double jump (triple jump via Ascension node), drop down through platforms (`Down + Jump`), ~30-stud jump pads, and ground dash / air "flash jump" with recharging charges.
* **Controls:** Keyboard, Gamepad, and Mobile virtual joystick + touch buttons (`MobileControlsController`).

### 1.2 All 8 Playable Weapons + Blacksmith Weapon Reforging (Done & Tested)
* **8 Playable Weapons (`WeaponHoldService`):** Greatsword, Daggers, Staff, Bow, Hammer, Gauntlets, Summoning Bell, and Trick Cards—all physically welded to the player's right hand and balanced (`bab6ba0`) so `Q` cooldowns sit at $5\text{s}-9\text{s}$ and baseline single-target DPS lands at $\sim 67-76$ across all 8 weapons.
* **Weapon Reforge & Aura System (`1a273f3` — `ReforgeConfig`, `ReforgeSection`, `InventoryService`):**
  * 5 tiers with public odds: **Common** *Sharp* ($60\%$, $+10\%$ Dmg) · **Rare** *Stormforged* ($25\%$, $+25\%$ Dmg, $+10\%$ Atk Speed) · **Epic** *Void-Touched* ($10\%$, $+50\%$ Dmg, $+1$ extra shot/slash wave) · **Legendary** *Celestial* ($4\%$, $+100\%$ Dmg, $+20\%$ Crit) · **Mythic** *Rift Sovereign* ($1\%$, $+200\%$ Dmg, $+40\%$ Size).
  * **Dual Pity Counters:** Guaranteed **Epic+** within 13 rolls and **Legendary+** within 60 rolls.
  * **Safe Keep/Discard Flow:** First roll applies directly; subsequent rolls wait as `Pending` so players choose **Keep New** or **Keep Current** without losing a top-tier roll.
  * **Visual Auras & Server Flex:** Per-tier weapon particle emitters (`ReforgeFx_*`), gold/crimson `Highlight`, character bead halo + neon wings (`ReforgeAura`) on Legendary+, and a server-wide `Celebrate:FireAllClients` banner + `RBXGeneral` system chat announcement + white-to-crimson screen flash on Mythic rolls.

### 1.3 Combat Juice, VFX Sprites & Audio (`2b23979` — Done & Tested)
* **Pooled Kenney VFX Sprites (`CombatVFXController`):** `slash_02` on melee arc swings, `spark_01` / `spark_04` + gold `star_04` on hits and crits, `flare_01` on kills, `spark_04` on chain lightning, `light_01` on boss roars, and custom sprites per burst style (`magic_03`, `fire_01`, `twirl_01`, `circle_05`).
* **Combat SFX with Pitch Variation (`0.92-1.08`):** `Combat_Swing1/2` alternate on every attack (lower pitch for heavy weapons), `Combat_Chop` on hit impacts, `Item_Drop` on kills/chests/Gold cards, `Gate_Open` on room clear/Rift Anchor spawn, and `Weapon_Equip` on weapon swap.
* **Hit-Stop:** $50\text{ ms}$ local animation freeze + micro camera kick on crits and $40\text{ ms}$ on boss hits (throttled to max once per $0.25\text{s}$).

### 1.4 20 Upgrade Cards (Including 10 "Screen-Breaking" Mutator Cards — `3339222`)
* **Original 10 Cards:** *Sharpened Edge, Swift Hands, Keen Eye, Vital Surge, Ember Edge, Storm Conduit, Cleaving Gale, Triple Threat, Napalm Wake, Volatile Cinders*.
* **10 New Screen-Breaking Cards (`3339222`):** *Gigantism, Echo Chamber, Chain Reaction, Ricochet Frenzy, Golden Piñata, Afterimage, Meteor Shower, Whirling Blades, Prismatic Barrage, Rift Overdrive*.
* **Performance Safety Caps:** Hard cap of 160 active player projectiles per run and 80 non-crit damage numbers per flush.

### 1.5 Survivability & Balance Pass Part 1 (`bab6ba0` — Done)
* **Room 1 Idle Survival Increased from ~12s to ~32s:** Contact hits now grant $0.85\text{s}$ contact immunity (`CONTACT_IFRAMES`), and World 1 Corruption 0 enemies deal $65\%$ damage in Rooms 1–4 ramping to $100\%$ by Room 9 (`EARLY_ATK_MULT`).
* **Boss & Hazard Tuning:** *Spore Golem* HP $1200 \rightarrow 1900$, Atk $25 \rightarrow 22$; *Mushroom Titan* Atk $40 \rightarrow 32$; Rising Acid adjusted from $8\%$ per $0.4\text{s}$ to $6\%$ per $0.5\text{s}$.

### 1.6 Town Hub, Scene UIs & Overhead Flex Badges (`7a0ea93` — Done & Tested)
* **Town Overhead Flex Badges (`FlexBadgeService.luau`):** Server-rendered `BillboardGui` above every player's head in Haven Outpost displaying `[Rebirth V ⭐] DisplayName` (or `[Lv N]`), highest earned title (*Rift Sovereign, Boss Breaker, Mushroom Slayer, Rift Delver*), and `🔥 Best: Room N`.
* **All 8 Station Windows Rebuilt as Visual Scenes:** Spark Sanctum, Quest Board, Star-Forge, Blacksmith (+ Reforge Section), Legion Hall, Hall of Champions, Rebirth, Bag, Rift Gate, and Settings & Credits.

---

## 2. Code Facts & Bug Fixes Before Next Sprint

1. ~~**Link Skill Damage Bonus Bug in `CombatService`:**~~ **Not a bug (checked 2026-11-04, A1):** all 8 Link Skills already apply in combat through their own stats — `CritDamage` / `CritRate` in `makeParams` / `makeAttackCtx`, `NormalEliteDamage` / `BossDamage` as `NormalBonus` / `BossBonus`, `AttackSpeedCooldown` in attack interval + Q cooldown, `StatusDamageDuration` on burn/shock, `DustDropRate` in `RunManagerService`, `RareUpgradeRate` as card Luck. No Link Skill is a flat "+% damage" stat, so `LinkSkillDmgBonus = 0` is correct (now commented).
2. **Wrong Asset Content-Type Warning (`B9` / Playtest Output):** `rbxassetid://203785492` ("Asset type does not match") — not in `src/` and not referenced by any instance in the server or client DataModel during play (scanned 2026-11-04). Most likely an accessory on the Studio test avatar, i.e. not the game's; ignore unless it shows up for other players.
3. **New Card Icons Fallback:** Only the original 10 cards have `Card_*` keys in `AssetRegistry.Icons`; ensure the 10 new cards (`UP_11` to `UP_20`) either map to existing uploaded icons in `AssetRegistry.Icons` or render their crisp emoji/glyph cleanly.

---

## 3. High-Priority "First 60 Seconds" Player Attraction Overhaul (Best of Playtest Feedback)

> **WHY THIS SECTION MATTERS:** Playtesting revealed that a brand-new player spawns 100+ studs away from the Rift Gate surrounded by 9 unfamiliar station waypoints, with no immediate combat action or single "Power Number" going up. The 7 features below directly solve the **First 60 Seconds** retention hook without adding months of scope creep.

### 3.1 Instant-Action First Join (Zero-Downtime Onboarding)
* **Problem:** Walking 100+ studs across Haven Outpost before fighting a single monster causes new Roblox players to bounce in the first 20 seconds.
* **Implementation Spec:**
  1. **First-Join Spawn Position (`Stats.RoomsCleared == 0`):** When a brand-new player joins for the first time (`Stats.RoomsCleared == 0` and `HunterLevel == 1`), either:
     * **Option A (Fastest & Safest):** Spawn the player **14 studs directly in front of the Rift Gate**, facing a **Starter Weapon Pedestal Trio** (*Greatsword — Heavy AoE*, *Daggers — Fast Crit*, *Staff — Arcane Nova*) with 1-click equip prompts and a pulsing golden arrow pointing into the **Rift Gate**, OR
     * **Option B (Instant Tutorial Rift):** Drop them directly into a 45-second, 2-room **Starter Rift** with 1-line action callouts (`"CLICK TO ATTACK!"` $\rightarrow$ `"PRESS Q FOR SKILL!"` $\rightarrow$ `"PICK YOUR UPGRADE!"`), guaranteed 100 *Rift Dust* + 1 *Boss Core* payout at the end, and extract them into Haven Outpost right in front of the Blacksmith with enough currency for their first **Weapon Reforge**!

### 3.2 Big Animated `⚡ Rift Power` Number (HUD + Popups + Overhead Badge)
* **Problem:** Younger Roblox players want **one big, unmistakable number** that represents their total strength and visibly ticks upward every 20–30 seconds.
* **Formula (`FormulaEngine.CalculateRiftPower(profile, inRunUpgradeCount?)`):**
  $$\text{RiftPower} = \text{round}\left(\text{BaseWeaponPower} \times (1 + 0.08 \times \text{HunterLevel}) \times \text{RebirthMult} \times \text{ReforgeMult} \times (1 + 0.05 \times \text{TotalMasteryLevels}) \times (1 + 0.12 \times \text{TotalRelicStars}) \times (1 + 0.15 \times \text{InRunUpgrades})\right)$$
* **Presentation Rules:**
  1. **HUD Display:** Show a bold golden **`⚡ Power: 1,248`** badge near the player's Level/Vitals cluster.
  2. **Animated Power-Up Popup:** Whenever `RiftPower` increases (on Level Up, Upgrade Card pick, Weapon Reforge, Relic Star-Up, or Mastery level-up), trigger a punchy floating counter toast:
     > **`⚡ RIFT POWER UP!  1,248 » 1,576 (+328)`**
     with an upward number ticker, gold flare burst (`flare_01`), and rising chime.
  3. **Town Flex Badge Integration:** Include `⚡ 1,576 Power` on `FlexBadgeService`'s overhead display in Town!

### 3.3 Progressive Town Station Unlocks & Single-Waypoint Decluttering
* **Problem:** Showing 9 station waypoints simultaneously overwhelms new players who don't know what *Star-Forge*, *Legion Hall*, or *Spark Sanctum* mean yet.
* **Implementation Spec (Clutter Reduction + Unlock Milestones):**
  * **Waypoint Decluttering Rule:** In Haven Outpost, only display the **nearest 1 or 2 relevant waypoints** (or the current tracked objective waypoint) rather than all 9 at once! Inside a run, only show Chest/Altar waypoints when within 45 studs, and always show the Room Exit / Rift Anchor waypoint once unlocked.
  * **Progressive Station Unlock Milestones (Visual Only or Soft-Gated):**
    * **First Join (`RoomsCleared == 0`):** Only highlight **Rift Gate** and **Bag**.
    * **After First Run / Room 1 Clear (`RoomsCleared >= 1`):** Highlight **Blacksmith (+ Reforge)** and **Quest Board**.
    * **After First Boss / Relic Drop (`BossKills >= 1` or any Relic owned):** Highlight **Star-Forge** and **Hall of Champions**.
    * **At Hunter Level 10+ or Mastery 5+:** Highlight **Legion Hall**, **Rebirth Pedestal**, and **Spark Sanctum**.
    * *(Players who walk up to an advanced station early see a clear 1-line hint banner like `"🔒 Unlocks after defeating your first Boss (Room 5)!"` or can still inspect it without cluttering their screen with 9 arrows.)*

### 3.4 Optional `⚔️ Auto-Attack` Toggle (Mobile & Casual Accessibility)
* **Problem:** Holding/tapping attack while platforming in 2.5D for 15 minutes fatigues young and mobile players.
* **Implementation Spec:**
  * Add a compact **`⚔️ AUTO: OFF / ON`** toggle button on the HUD (and in Settings).
  * When `Auto-Attack` is **ON** inside a run, if an enemy is within the player's weapon range (or within $28\text{ studs}$ for ranged weapons), the client automatically faces the nearest target and fires basic attacks at the weapon's normal cooldown—while the player still manually controls movement, jumping, dodging, and `Q` ability timing!

### 3.5 Physical Magnetic Currency Orbs & Rare Drop Light Beams (`Vacuum Aura` For All)
* **Problem:** Rewards added silently to a number counter feel invisible compared to physical coins/crystals bursting out of monsters and flying into the player.
* **Implementation Spec (Builds on `spawnPinata` in `CombatVFXController` + Wires `AS_T1_03`):**
  1. **Every Enemy Kill & Chest:** Spawn 2–5 glowing *Rift Dust* crystal orbs that bounce onto the floor for $0.25\text{s}$ and then magnetically zoom into the player's chest (with a base pickup radius of $18\text{ studs}$, scaled up to full-room by the `AS_T1_03 Vacuum Aura` Ascension node) and play a rising pitch tick as the HUD Dust counter animates up.
  2. **Rare Drop Light Beams:** When a **Boss Core** or **Relic** drops, spawn a tall vertical **Neon Light Pillar** (`Purple` for Core/Relic, `Gold` for Room 10 Relic) with floating title text (`"✨ RELIC DISCOVERED: FROST HEART!"`) and a celebratory chime.

### 3.6 Upgrade Card Synergy Badges (`🔥 SYNERGY!`)
* **Problem:** Players shouldn't have to do mental math to know which of the 3 offered Upgrade Cards fits their current weapon or build.
* **Implementation Spec:**
  * Add a `Tags: { string }` field to each weapon in `WeaponConfig` and each card in `UpgradePoolConfig` (`"Burn"`, `"Shock"`, `"Crit"`, `"AoE"`, `"Projectile"`, `"Summon"`, `"Speed"`).
  * In the Upgrade Picker UI, if an offered card shares a tag with the player's equipped weapon OR with 2+ cards already picked in the run, render a glowing **`🔥 SYNERGY!`** ribbon badge on the top-right corner of the card!

### 3.7 AFK Training Sanctuary Circle + "While You Were Away" Offline Training Summary
* **Problem:** Players who want to chill in Town or return the next day need passive progression that rewards staying in the server and coming back tomorrow.
* **Implementation Spec:**
  1. **Haven Outpost Training Sanctuary (`SanctuaryService.luau`):** Place a glowing rune circle near Town center with 3 respawning **Training Mushroom Dummies**. Players standing inside the circle automatically swing their weapon at the dummies every $1.5\text{s}$, spawning real damage numbers and earning $20\%$ of active-run *Rift Dust* and *Weapon Mastery XP* every $4\text{s}$ ($+10\%$ per other player training in the circle).
  2. **Offline Training Summary Popup (Capped at 8 Hours):** Record `profile.LastSeenAt = os.time()` on save. When a player rejoins after $\ge 15\text{ minutes}$ away, calculate passive offline training rewards ($15\text{ Dust/min} \times \text{RebirthEcoMult}$ + $5\text{ Mastery XP/min}$ for their equipped weapon, capped at $480\text{ minutes}$) and display a celebratory **`"🌙 WHILE YOU WERE AWAY — YOUR HUNTER TRAINED!"`** claim card with a **`[Claim Rewards]`** button (and optional **`[2x with Robux]`** button).

---

## 4. Recommended Implementation Order for Claude Code (Next Sprint)

> **INSTRUCTIONS FOR CLAUDE CODE:** Execute these in order on `main` (using **Sonnet** by default). Run `./luau-lsp analyze` after each item, update the Section 5 Changelog, and commit.

1. ✅ **Step A1 — Quick Bug Fix (`LinkSkillDmgBonus`) & `⚡ Rift Power` Counter (3.2):** *(done — see Section 5)*
   * Fix `LinkSkillDmgBonus = 0` in `CombatService.luau` so socketed Link Skills apply in combat.
   * Add `FormulaEngine.CalculateRiftPower`, display **`⚡ Power: N`** on the HUD and Town `FlexBadgeService`, and fire the animated `+Power` popup toast whenever the player's power increases.
2. ✅ **Step A2 — Instant-Action First Join + Waypoint Decluttering + `⚔️ Auto-Attack` Toggle (3.1, 3.3, 3.4):** *(done — see Section 5; note the MCP screen capture doesn't draw `AlwaysOnTop` billboards, so waypoint hovers were verified by state, not screenshot)*
   * Spawn first-time players (`RoomsCleared == 0`) right in front of the Rift Gate with a 3-weapon starter rack and single golden guide arrow.
   * Declutter Town waypoints so only the nearest 1–2 unlocked station waypoints show at a time (progressive station unlock hints).
   * Add the HUD **`⚔️ AUTO-ATTACK: ON/OFF`** toggle in `Movement25DController` / `UIController`.
3. ✅ **Step A3 — Magnetic Loot Orbs on Every Kill, Rare Drop Beams & Card `🔥 SYNERGY!` Badges (3.5, 3.6 + `AS_T1_03`):** *(done — see Section 5)*
   * Make every enemy kill / chest spawn magnetic *Rift Dust* orbs that fly into the player (wiring `AS_T1_03 Vacuum Aura` radius bonus) + vertical light beams for Boss Cores/Relics.
   * Add `Tags` to `WeaponConfig` and `UpgradePoolConfig` and render the **`🔥 SYNERGY!`** badge on matching upgrade cards.
   * Wire the remaining 3 `ComingSoon` Ascension nodes (`AS_T1_04 Headstart Blessing`, `AS_T3_01 Elemental Crit Overload`, `AS_T4_02 Miracle Evolution`).
4. **Step A4 — Town Training Sanctuary Circle + "While You Were Away" Offline Rewards (3.7):**
   * Build `SanctuaryService.luau` (auto-attacking training dummies in Haven Outpost for passive Dust + Mastery XP) and the 8-hour capped Offline Training Claim popup on join.

---

## 5. Live Development Log (Maintained by Claude Code)

| Date | Commit | Branch | What Changed |
| :--- | :--- | :--- | :--- |
| 2026-10-28 | `af46038` | `main` | Single-player World 1 loop complete: landmarks, vista, climb rooms + acid, waypoints, Blacksmith, Mastery, weapons 4–8, relics + Star-Force, curses, session locking, quests, leaderboards, mobile controls. |
| 2026-10-29 | `e545dff` | `game-like-ui` | **Asset drop:** 96 game-icons.net icons, 16 Kenney VFX textures, 9 Kenney UI panel textures, and 29 Kenney sounds uploaded and indexed in `AssetRegistry`. |
| 2026-10-30 | `8ac6b82` $\rightarrow$ `72f11a6` | `game-like-ui` | **Full Scene UI Redesign:** Rebuilt Spark Sanctum, Quest Board, Star-Forge, Blacksmith, Legion Hall, Hall of Champions, Rebirth, Bag, Rift Gate, and Settings & Credits; fixed `B3`, `B11`, `B12`, `B16`. |
| 2026-11-04 | `bab6ba0` | `main` | **Balance pass part 1 (`B25`):** Idle Room 1 death went from ~12s to ~32s (`0.85s` contact i-frames, $65\%$ early enemy damage in Rooms 1–4); boss HP/Atk tuned; acid $6\%$ per $0.5\text{s}$; all 8 weapons balanced to $5-9\text{s}$ Q cooldowns and $\sim 67-76$ single-target DPS. |
| 2026-11-04 | `2b23979` | `main` | **Combat juice:** Pooled Kenney VFX sprites (`slash_02`, `spark_01/04`, `star_04`, `flare_01`, `light_01`, burst styles), pitched combat/equip/drop/gate SFX (`0.92-1.08`), and $50\text{ ms} / 40\text{ ms}$ crit/boss hit-stop. |
| 2026-11-04 | `3339222` | `main` | **(A) 10 screen-breaking cards:** Added *Gigantism, Echo Chamber, Chain Reaction, Ricochet Frenzy, Golden Piñata, Afterimage, Meteor Shower, Whirling Blades, Prismatic Barrage, Rift Overdrive* with projectile/number caps, coin fountains, and orbiting blades. |
| 2026-11-04 | `1a273f3` | `main` | **(B) Weapon Reforge (`ReforgeConfig`, `ReforgeSection`):** 5 tiers (*Sharp* $60\%$ to *Rift Sovereign* $1\%$), dual pity counters (13 / 60), Keep/Discard pending state, weapon particle auras + halo/wings, and server-wide Mythic celebration + chat announcement. |
| 2026-11-04 | `7a0ea93` | `main` | **(C) Town flex badges (`FlexBadgeService`):** Overhead server `BillboardGui` in Haven Outpost displaying `[Rebirth R ⭐] Name`, highest earned title (*Rift Sovereign, Boss Breaker, Mushroom Slayer, Rift Delver*), and `🔥 Best: Room N`. |
| 2026-11-04 | `017d8d5` | `main` | **A1 `⚡ Rift Power` (3.2):** `FormulaEngine.CalculateRiftPower` (weapon DPS × 20 base ≈ 1,000 for a new hunter; Legacy levels count as Hunter levels so a rebirth doesn't crater it; mastery counts levels above 1; +15% per run card). `FlexBadgeService` owns the `RiftPower` attribute (recomputed on the new `PlayerDataService.Replicated` signal + CombatService's `RunCards` attribute) and shows `⚡ N Power` on the overhead badge. New `RiftPowerController`: gold `⚡ Power: N` badge on top of the HUD vitals column + bottom-centre `⚡ RIFT POWER UP! a » b (+c)` toast with roll-up counter, `flare_01` burst and pitched `UI_Unlock` chime; rises within 2.2s merge into one toast. Link Skill "bug" (§2.1) was a false alarm — commented. Studio-tested: mastery 6→8 and 2 cards (4,122 → 5,358, exactly +15%/card), toast clear of notify toasts, no console errors. |
| 2026-11-04 | `24be534` | `main` | **A2 First 60 Seconds (3.1 Option A, 3.3, 3.4):** New `OnboardingConfig` (shared: `IsNewHunter` = 0 rooms cleared & Lv 1; `TierFor` 1–4 per the 3.3 milestones; per-station tier + 🔒 hint text) and `OnboardingService`: a **Starter Weapon Rack** left of the Rift Gate (Greatsword *Heavy AoE* / Daggers *Fast Crit* / Staff *Arcane Nova* pedestals with floating weapon via new `WeaponHoldService.CreateDisplayModel`, accent ring, light, sparkles, label and one-press **Equip** prompt → new `InventoryService.EquipWeapon`); new hunters spawn facing the rack 16 studs from the gate on every spawn / town return until their first room clear, with a welcome toast; `TownTier` / `NewHunter` attributes; a one-time toast when you walk up to a locked station. `WaypointController` declutter: town shows only the Rift Gate + the nearest unlocked station (others hover only when you're right there, locked ones grey with the 🔒 hint), runs show chests/altars only within 45 studs while the Exit Portal always points; new hunters get a sliding gold **ENTER THE RIFT ▶▶▶** sign at the gate. **Auto-Attack:** `Settings.AutoAttack` (saved), HUD pill `⚔️ AUTO: ON/OFF` (runs only, bottom-centre) + Settings row; `CombatInputController` targets the nearest live enemy in melee reach (× SizeScale) or 28 studs for ranged and turns the character via new `Movement25DController.SetFacing`. RiftDev `SetProfile { Level, Stats }`. Studio-tested: fresh join spawns at the rack, Staff equip from the pedestal, tier-1 view shows only the gate marker, hint toasts, Auto-Attack killed a SporeBlob untouched; test profile restored (Lv 8, RoomsCleared 16, Auto off, Greatsword). |
| 2026-11-04 | *(A3)* | `main` | **A3 Physical loot, synergy & the last Ascension nodes (3.5, 3.6):** Every kill now pays its share of the room's Rift Dust on the spot (`KILL_DUST_SHARE` Normal 7% / Elite 15% / Boss 25%, capped at 50% of the room; the room clear pays the rest, so totals are unchanged) and chests send their Dust too, as `DustOrbs` CombatFx. New `LootOrbController`: 2–5 glowing crystals burst out, bounce 0.25s, hover until you're inside the pickup radius (18 studs; **Vacuum Aura `AS_T1_03`** +15 / +35 / whole room, Lv3 also +10% Dust) or 6s pass, then swoop into you with a rising-pitch `UI_ProgressTick` combo and a `+N Rift Dust` ticker under the run banner. **Loot beams:** new `RunManagerService.ShowLootBeam` (whole party sees it) for Boss Cores at the Anchor and every Relic drop (RelicService) — a neon pillar + ForceField halo, purple or gold (Room 10 relics), `AlwaysOnTop` title (`✨ RELIC DISCOVERED: FROST HEART!`, stacked when two drop at once) and a chime. **🔥 SYNERGY!:** `Tags` on all 8 weapons (`WeaponConfig`) and 18 cards (`UpgradePoolConfig` `CARD_TAGS`); new `UpgradePoolConfig.SynergyTag` (shared with the weapon, or with 2+ owned card stacks) goes out as `Synergy` in each card payload and the picker draws an orange ribbon with the tag on the card's corner. **Ascension (no more `ComingSoon`):** `AS_T1_04 Headstart Blessing` = a free Common+ / Rare+ / Epic+ orb 2s into Room 1 (`RollContext.MinRarity`, kept through rerolls / banishes); `AS_T3_01 Elemental Crit Overload` = Burn ticks and Shock chains roll your crit rate for 33 / 66 / 100% of Crit Damage; `AS_T4_02 Miracle Evolution` = 15% Double Orbs (the orb stays open for a 2nd pick, `✨ DOUBLE ORB! Pick 2 upgrades` → `Pick 1 more!`). RiftDev `Ascension { Id, Level }`. Studio-tested: Headstart offered 3 Rares with a SYNERGY (AoE) ribbon on Cleaving Gale for the Greatsword, kill orbs flew in (+21 Dust ticker), a Double Orb rolled and took two picks, purple + gold beams, Burn ticks crit 2/6 at Elemental Overload 3; no console errors; nodes and Auto-Attack restored. |