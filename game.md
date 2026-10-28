*Note: the links and images in this document may point to external sources. Please review them before opening.*

# CLAUDE.md — Rift Rush Master Game Design & Implementation Spec (v3.0)

> **Status:** Single-Player World 1 Completion Roadmap, Live Codebase Audit, 5 Landmark/Vista/Hazard Design Upgrades & Full System Wiring Spec (v3.0)
> **Platform:** Roblox (PC, Mobile, Console)
> **Genre:** 2.5D PvE Action Roguelite with Endless Permanent Progression & Rebirths
> **Working Title:** Rift Rush
> **Repository:** [ArrickGit/Rift-Rush](https://github.com/ArrickGit/Rift-Rush)
> **Document Purpose:** Serve as the single source of truth (`CLAUDE.md` / `game.md`) for Claude Code to complete the Single-Player loop of **Rift Rush** end-to-end.

---

## 0. AI Agent Execution Rules & Model Selection Guidelines

> **CRITICAL INSTRUCTIONS FOR CLAUDE CODE — READ BEFORE EVERY ACTION:**

### 0.1 Mandatory Coding, Architecture & Single-Player Focus Standards

1. **Strict Luau Typing:** Every `.luau` script MUST begin with `--!strict` and use explicit type annotations for function parameters, return types, and data structures.
2. **Server Authority:** Never trust the client for damage calculations, currency payouts, Weapon Mastery XP, Rebirth eligibility, Ascension Shop purchases, environmental hazard damage, or room completion. Use `ReplicatedStorage.Shared.FormulaEngine` on the server as the single source of truth.
3. **Single-Player First Rule (DO NOT Touch Co-op Yet):**
   * **CRITICAL:** Do NOT spend tokens building Co-op party invites, lobby matchmaking, or multi-player Rift Gate queues right now. Co-op is deferred until the entire Single-Player World 1 progression loop (Visual Upgrades, Blacksmith, Inventory, Weapon Mastery, All 8 Weapons, Relics & Star-Force, and Data Safety) is 100% playable and complete.
4. **Bespoke Multi-Part Visual Standard (ZERO "Stock 2-Part Primitives"):**
   * **Weapons Held in Hand:** Every equipped weapon MUST be physically welded (`Motor6D` or `WeldConstraint`) to the player character's `RightHand` / `Right Arm` both in Haven Outpost and inside Portal Runs.
   * **Oversized Landmark Interactables & Unique Platforms:** Every Town Hub & Stage interactable (except the Rift Portal) must be scaled to $2.2\times - 2.8\times$ **player height ($12 - 16$ studs tall)** and sit atop its own **unique, custom-themed Sanctuary Dais platform** (Section 33.1) with a persistent overhead bobbing waypoint chevron (`▼`) that never disappears when the player approaches.
   * **High-Contrast Terrain & Fantasy Vista:** Elevated platforms in World 1 monster stages must use distinct color/material framing from the ground floor (Section 33.4) so they never blend together, backed by a bright, expansive high-fantasy daytime blue-sky vista ($Z = -35$ to $-180$) that evokes a sense of wonder and exploration.

### 0.2 Model Selection Guidelines (Default Sonnet vs. When to Recommend Opus)

* **Default Model (Sonnet):** The user defaults to **Sonnet** for standard development (UI panels, Blacksmith, Inventory, Weapon Mastery XP hooks, Weapons 4–8 attack scripts, landmark interactables, skybox vistas, and Stage 3 Rising Poison overhaul).
* **When to Recommend Switching to Opus:** Only mention switching to **Opus** when the user is about to tackle complex concurrency/data-integrity tasks—specifically **Step SP-6 (DataStore Session Locking & Fixing the Save/Loot Race Condition)**—or if a multi-file architecture/physics bug requires deep cross-file reasoning.

---

## 1. Current Codebase Status Audit (What Exists vs. What Needs Wiring)

> **SNAPSHOT OF `ArrickGit/Rift-Rush` REPOSITORY:**

### 1.1 Working Systems (Playable Today)

* **Core & 2.5D Movement:** 2.5D combat plane lock ($Z = 0$), side-on camera, keyboard/gamepad movement, jump, one-way drop-through platforms, and jump pads.
* **Server-Authoritative Combat:** Basic attack, `Q` ability, dash with brief i-frames, combo counter, floating damage numbers, critical hits, **Burn** and **Shock** status effects, and Staff's *Arcane Nova* dual-status trigger.
* **Playable Weapons (3 of 8):**
  1. **Greatsword:** *Rift Cleave* ability + *Berserker's Momentum* passive.
  2. **Daggers:** *Shuriken Fan* ability + guaranteed crit after dashing through an enemy.
  3. **Staff:** *Fireball* ability + *Arcane Nova* passive.
* **Enemies & Bosses:**
  * *Spore Blob* and *Mushroom Hopper* (normal + elite variants).
  * *Spore Golem* and *Mushroom Titan* bosses with 4 telegraphed moves (*Ground Pound*, *Boulder Charge*, *Poison Wave*, *Spore Boulder*), $50\%$ HP enraged phase, boulder-deflect stun mechanic, move-warning banner, and `"EXPOSED - ATTACK!"` vulnerability window.
* **World 1 (Mushroom Wilds) Runs:** 10 rooms (combat, jump rooms with rising poison, treasure shrine, 2 boss rooms), Corruption Tier selector at Rift Gate, 10 room-clear upgrade cards (Common/Rare/Epic/Legendary with Pick/Reroll/Banish), Rift Anchors every 5 rooms (Extract vs. Push), Unsecured Pouch loot risk, Chests, and Defeat Screen recovery options.
* **Progression & Currencies:** Hunter Level & XP (DataStore backed), Rift Rebirth (Standard & Keep Everything reset rules), Ascension Shop (all 17 nodes + respec), and all 5 currencies (*Rift Dust*, *Boss Cores*, *Relic Shards*, *Anchor Tokens*, *Rebirth Sparks*).
* **Town Hub (Haven Outpost):** 9 station models placed; **4 stations have working UI panels** (*Rift Gate*, *Ascension Pedestal*, *Spark Sanctum*, *Rift Shrine*).
* **Monetization Scaffolding:** Idempotent receipt handling wired for 7 Developer Products and 8 Gamepasses (awaiting real asset IDs).

### 1.2 In the Codebase But Not Yet Usable (Priority Wiring Targets)

* **Weapons 4–8 (Bow, Hammer, Gauntlets, Summoning Bell, Trick Cards):** Stats and Link Skill definitions exist in config, but they have **no attack execution code** and **no UI to unlock or equip them**.
* **Weapon Models Not Equipped in Hand:** Weapon models exist, but are **never welded/held in the character's hand** during Town or Run gameplay.
* **Weapon Mastery & Paragon Ranks:** Read by `FormulaEngine` damage/dust formulas, but **nothing awards Mastery XP on enemy/boss kills**, leaving all weapons stuck at Mastery Level 1.
* **Link Skills:** Bonus math exists in `FormulaEngine`, but **there is no UI panel to equip/unequip Link Skills**.
* **Relics & Star-Force:** Saved profile fields exist, but **no Relics drop from bosses/chests** and **the Star-Forge UI panel is not implemented**.
* **Curses:** Multiplier hook exists in damage math (always $1.0\times$), with no shrine/curse selection active.
* **Unwired Town Hub Stations (5 of 9):** *Blacksmith*, *Legion Hall*, *Star-Forge*, *Quest Board*, and *Hall of Champions* have 3D models in Town, but interacting shows `"not yet available"`.
* **Stage 3 Rising Poison Hazard:** Currently a rising green bar that lacks bubbling liquid textures and does **not deal damage or bounce the player**.

### 1.3 Not Started Yet

* **Inventory & Loadout Screen** (and HUD Bag button / `I` hotkey).
* **5 Visual & World Readability Upgrades** (Oversized landmark interactables on custom platforms, persistent close-range bobbing waypoints, bright blue-sky fantasy vista, high-contrast World 1 platforms, and damaging/bubbling Stage 3 acid flood).
* **Data Safety & Session Locking** (preventing profile dual-server loading and fixing the save vs. loot payout race condition).
* **Quests/Bounties, Leaderboards, Mobile Touch Controls, Audio/SFX.**
* **Deferred Post-Single-Player Systems:** Co-op party join UI at the Rift Gate, Worlds 2–8, and Post-Launch Expansion features.

---

## 2. High Concept & Core Loop Summary

**Rift Rush** is a fast-paced 2.5D Roblox PvE action roguelite inspired by classic side-scrolling RPGs like *MapleStory*. Players enter unstable dimensional portals, clear short randomized rooms, assemble visually explosive combat builds, complete platforming "Jump Quest" rooms, defeat multi-phase bosses, and decide whether to extract safely with their loot or push deeper for massive reward multipliers.

1. **Minute-to-Minute Room Loop (20–45s):** Enter Room $\rightarrow$ Execute & Mob across high-contrast 2.5D platforms $\rightarrow$ Collect loot bursts & Weapon Mastery XP $\rightarrow$ Pick 1 of 3/4 transformative upgrades $\rightarrow$ Enter next portal door.
2. **Run-to-Run Extraction Loop (8–20m):** Prep Loadout in Town (Weapon, Link Skills, Starting Relics) $\rightarrow$ Build synergies across rooms $\rightarrow$ Defeat Boss at Room 5/10 to activate **Rift Anchor** $\rightarrow$ Extract safely with $100\%$ loot OR push deeper for escalating multipliers.
3. **Long-Term Single-Player Grind Loop:** Level **Hunter Level** $\rightarrow$ Perform **Rift Rebirths** $\rightarrow$ Spend **Rebirth Sparks** in the **Ascension Shop** $\rightarrow$ Craft & Master all 8 Weapons at the **Blacksmith** $\rightarrow$ Equip **Hunter Legion Link Skills** $\rightarrow$ **Star-Force** Relics to 5-Star $\rightarrow$ Climb **Corruption Tiers 1–100+**.

---

## 3. Player Presentation, Camera & 2.5D Physics Rules (Locked Decision)

* **Movement Axes & Z-Plane Lock:** Players and monsters move along the X-axis and Y-axis. All characters and monsters have an `AlignPosition` / `PlaneConstraint` locking their RootPart to $Z = 0$ and `CollisionGroup = "ActorsNoCollide"`.
* **Vertical Stagger Instead of Horizontal Knockback:** Heavy attacks apply **Vertical Launch / Micro-Stun** in place rather than horizontal knockback so enemies are never pushed off platforms.
* **Camera Settings:** Narrow FOV ($35^\circ$) at $Z = +42$ studs with smooth spring-damped vertical tracking.

---

## 4. Controls & Cross-Platform Ergonomics

| Action | PC (Keyboard/Mouse) | Controller | Mobile |
| :--- | :--- | :--- | :--- |
| **Move / Drop Platform** | `A` / `D` (`S` + `Space` to drop) | Left Stick | Left Virtual Joystick |
| **Jump / Double Jump** | `Space` | `A` / `Cross` | Dedicated Jump Button |
| **Basic Attack (Holdable)** | `Left Click` or `J` | `X` / `Square` | Large Primary Attack Button |
| **Dash / Flash Jump** | `Shift` or `K` | `B` / `Circle` | Dash Button |
| **Ability (`Q` Skill)** | `Q` | `LB` / `RB` | Skill Button |
| **Open Inventory / Loadout** | `I` or `B` | `D-Pad Down` / `Select` | Dedicated `🎒 Bag` HUD Button |
| **Interact with Station** | `E` / `F` | `Y` / `Triangle` | Context-sensitive tap prompt |

---

## 5. Complete 8-Weapon Roster & Attack Specifications (For Step SP-4)

> **CRITICAL IMPLEMENTATION SPEC FOR WEAPONS 4–8 & HAND WELDING:**
> Every weapon below must:
> 1. Be unlockable at the **Blacksmith** using *Rift Dust* + *Boss Cores* (Greatsword, Daggers, and Staff are unlocked by default or cheap starter tiers).
> 2. Visually attach to the player's right hand (`RightHand` for R15 or `Right Arm` for R6) via a `Motor6D` / `WeldConstraint` whenever equipped in Town or inside a Run.
> 3. Award **Weapon Mastery XP** on every enemy and boss kill while equipped.

| Weapon | Archetype | Base Dmg (`W_Base`) | Attacks / Sec | Basic Attack Behavior | `Q` Active Ability Behavior | Innate Passive | Link Skill (Mastery 10 / 20) | Unlock Cost |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Greatsword** *(Working)* | Wide melee cleaver | $42$ | $1.1$ | Wide horizontal 2.5D slash arc ($9$ stud reach). | **Rift Cleave:** Heavy forward shockwave slam ($240\%$ Dmg). | **Berserker's Momentum:** Hitting $3+$ enemies grants $+15\%$ Atk Spd for $3\text{s}$. | **Titan's Might:** $+8\% / +15\%$ Normal & Elite Dmg. | Starter (Free) |
| **2. Daggers** *(Working)* | Hyper-mobile assassin | $18$ | $2.6$ | Rapid twin-blade slashes ($6$ stud reach). | **Shuriken Fan:** Throws 3 piercing stars in a fan ($95\%\times 3$ Dmg). | **Shadow Step:** Dashing through an enemy guarantees next hit Crits. | **Lethal Instinct:** $+10\% / +20\%$ Critical Damage. | Starter (Free) |
| **3. Staff** *(Working)* | Elemental mage | $32$ | $1.4$ | Homing arcane bolts ($18$ stud range, inflicts *Shock*). | **Fireball:** Blazing orb that explodes on impact ($220\%$ Dmg + *Burn*). | **Elemental Resonance:** *Burn* + *Shock* on target triggers *Arcane Nova* ($150\%$ AoE). | **Arcane Flow:** $+8\% / +15\%$ Status Dmg & Duration. | Starter (Free) |
| **4. Bow** *(To Wire)* | Long-range sniper | $22$ | $2.2$ | Fires high-velocity piercing arrows ($28$ stud range along X-axis). | **Arrow Rain:** Fires an arc into the sky that rains 8 arrows over a $12$-stud zone ($45\%$ Dmg/arrow). | **Hurricane Focus:** Consecutive hits on the same target grant $+3\%$ Dmg per hit (up to $+30\%$). | **Eagle Eye:** $+5\% / +10\%$ Critical Hit Rate. | $400$ Dust + $2$ Cores |
| **5. Hammer** *(To Wire)* | Heavy crowd-control | $50$ | $0.9$ | Crushing overhead swing ($8$ stud reach) that vertically staggers enemies. | **Seismic Tremor:** Slams the ground, sending 3 erupting rock pillars along the platform ($260\%$ Dmg + $1.5\text{s}$ stun). | **Seismic Impact:** Ground slams deal $+40\%$ stagger damage and grant a $5\%$ Max HP shield for $4\text{s}$. | **Crushing Force:** $+8\% / +15\%$ Boss Damage. | $750$ Dust + $4$ Cores |
| **6. Gauntlets** *(To Wire)* | Rapid combo brawler | $16$ | $3.0$ | 3-hit martial arts punch combo with a forward micro-lunge ($5.5$ stud reach). | **Rising Uppercut:** Launches player and enemies upward in a flaming dragon spiral ($210\%$ Dmg + *Burn*). | **Combo Overdrive:** Combo meter never decays while dashing and grants $+1\%$ Dmg per 10 combo (up to $+30\%$). | **Relentless Flurry:** $+6\% / +12\%$ Atk Speed & CDR. | $1,200$ Dust + $6$ Cores |
| **7. Summoning Bell** *(To Wire)* | Spirit commander | $26$ | $1.5$ | Rings the bell to send a sonic pulse ($14$ stud range) and commands active spirits to focus target. | **Call Rift Familiar:** Summons 2 floating Spirit Foxes for $12\text{s}$ that auto-fire bolts every $0.8\text{s}$ ($65\%$ Dmg/bolt). | **Soul Pack:** Summons inherit $100\%$ of player Crit Rate, Atk Speed, and status procs. | **Rift Fortune:** $+10\% / +20\%$ *Rift Dust* Drop Rate. | $2,000$ Dust + $10$ Cores |
| **8. Trick Cards** *(To Wire)* | High-roller gambler | $25$ | $1.8$ | Throws slicing kinetic cards ($20$ stud range) that bounce once between nearby enemies. | **Royal Flush:** Throws a 5-card spread ($85\%\times 5$ Dmg) and triggers an immediate random Card Buff. | **Loaded Deck:** Every 6th attack draws a Card: **Red** ($150\%$ Burn AoE), **Blue** ($-2\text{s}$ `Q` cooldown), or **Gold** ($+15$ bonus *Rift Dust*). | **Lucky Draw:** $+8\% / +15\%$ Rare/Epic Upgrade Chance. | $3,500$ Dust + $15$ Cores |

---

## 6. Weapon Mastery XP, Hunter Legion Link Skills & Paragon Ranks (For Step SP-3)

### 6.1 Awarding Weapon Mastery XP (`CombatService.luau` / `PlayerDataService.luau`)

* **Why Mastery Was Stuck at Lv 1:** Previously, `FormulaEngine` read weapon mastery levels, but no service granted Mastery XP upon killing monsters.
* **Mastery XP Payout Formula (Awarded Immediately on Enemy Kill):**
  * **Normal Enemy Kill:** $+12 \times \text{WorldMultiplier} \times (1 + 0.08 \times \text{CorruptionTier})$ Mastery XP to the currently equipped weapon.
  * **Elite Enemy Kill:** $+45 \times \text{WorldMultiplier} \times (1 + 0.08 \times \text{CorruptionTier})$ Mastery XP.
  * **Mini-Boss (Room 5) Kill:** $+180 \times \text{WorldMultiplier}$ Mastery XP.
  * **World Boss (Room 10) Kill:** $+400 \times \text{WorldMultiplier}$ Mastery XP.
* **Mastery Level XP Curve (Levels 1–20 & Paragon 21+):**

  $$\text{MasteryXP}_{\text{Req}}(M) = \text{round}(100 \times M^{1.5})$$

  * **Level 1 $\rightarrow$ 10:** Unlock Tier 1 Account-Wide **Link Skill** for that weapon.
  * **Level 10 $\rightarrow$ 20:** Upgrade that weapon's **Link Skill** to Tier 2 (Max).
  * **Paragon Ranks (Level 21–999):** Each level past 20 grants $+0.5\%$ Weapon Base Damage and $+0.5\%$ *Rift Dust* Find, plus unlocks glowing weapon aura particles at Paragon 25, 50, 100.

### 6.2 Equipping Hunter Legion Link Skills (`LegionHallPanel` & `InventoryController`)

* **Default Active Link Skill Slots:** **3 Slots** (expandable to **5 Slots** via the Ascension Shop node `AS_T3_04 Legion Commander`, and up to **6 Slots** with Gamepass).
* **How Link Skills Work:** Once ANY weapon reaches Mastery Level 10, its Link Skill is permanently unlocked in the player's profile and can be slotted in the **Legion Hall** or **Inventory Loadout Screen** to buff the player even while using a completely different weapon.

---

## 7. Relics, Boss/Chest Drops & The Star-Force Forge (For Step SP-5)

### 7.1 Starter 8-Relic Pool (`RelicConfig.luau`)

Every Relic can drop from **Boss Kills (Room 5 = $35\%$ chance, Room 10 = $100\%$ guaranteed Relic drop)** and **Treasure Chests ($25\%$ chance)**, or be crafted at the **Star-Forge** using *Relic Shards*:

1. **Frost Heart (`REL_01`):** Taking damage freezes enemies within $12$ studs for $2.5\text{s}$ and grants a $10\%$ HP barrier ($8\text{s}$ CD). *(+20% freeze damage & barrier per Star).*
2. **Treasure Tooth (`REL_02`):** Opening any chest or clearing an Anchor permanently increases Damage by $+6\%$ for the rest of the run (stacks up to 10x). *(+2% per stack per Star).*
3. **Thunder Boots (`REL_03`):** Every double-jump or dash fires 2 homing lightning bolts dealing $55\%$ Weapon Damage and inflicting *Shock*. *(+1 bolt and +15% Dmg per Star).*
4. **Hungry Coin (`REL_04`):** Increases *Rift Dust* gained by $+15\%$ and spawns 2 orbiting golden coins that deal $40\%$ Weapon Damage/s to touching enemies. *(+5% Dust and +15% orbit Dmg per Star).*
5. **Phoenix Feather (`REL_05`):** Once per run, fatal damage instead heals you to $50\%$ Max HP and triggers a fiery invulnerability blast for $3\text{s}$. *(+10% heal per Star).*
6. **Vampiric Fang (`REL_06`):** Critical hits heal you for $1.5\%$ of your Max HP ($0.5\text{s}$ internal cooldown). *(+0.5% Max HP heal per Star).*
7. **Broken Crown (`REL_07`):** Deal $+25\%$ increased damage to Bosses and Elites, and $+35\%$ more damage while below $50\%$ HP. *(+6% Boss Dmg per Star).*
8. **Volatile Hourglass (`REL_08`):** Reduces `Q` Ability cooldown by $18\%$ and causes casting `Q` to emit a $100\%$ Weapon Damage arcane pulse. *(+4% CDR and +25% pulse Dmg per Star).*

### 7.2 Duplicate Drops $\rightarrow$ Relic Shards & Star-Force Awakening UI (`StarForgePanel`)

* **First Discovery:** Unlocks the Relic at **1-Star ($1\star$)** in the player's permanent `RelicCollection`.
* **Duplicate Drop Conversion:** Finding a Relic you already own automatically converts it into **+5 Relic Shards** (with a floating toast notification: `"Duplicate Thunder Boots converted into +5 Relic Shards!"`).
* **The Star-Forge UI Panel (Town Station):**
  * Players select any owned Relic to view its current Star Level ($1\star \rightarrow 5\star$), next-tier stat bonus, *Relic Shard* + *Rift Dust* cost, success probability, and **Non-Destructive Star Pity Bar ($+25\%$ per failure)**.
  * Players can also equip **1 Starting Relic** (or **2 Starting Relics** if they unlocked `AS_T3_03 Twin Relic Vessel` in the Ascension Shop) to carry into every Portal Run from Room 1.

---

## 8. The Rift Rebirth & Ascension System (Working Reference)

| Rebirth Tier ($R$) | Required Hunter Level ($L_{\text{req}}$) | Global Damage & HP Multiplier ($M_{\text{RebDmg}}$) | Rift Dust & Hunter XP Multiplier ($M_{\text{RebEco}}$) | Sparks Awarded ($\Delta S$) | Cumulative Sparks ($S_{\text{total}}$) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Rebirth 0** | Lv. 1 | $1.00\times$ | $1.00\times$ | $0$ | $0$ |
| **Rebirth I** | **Level 50** | $1.30\times$ | $1.25\times$ | **+2 Sparks** | 2 |
| **Rebirth II** | **Level 75** | $1.65\times$ | $1.55\times$ | **+3 Sparks** | 5 |
| **Rebirth III** | **Level 100** | $2.10\times$ | $1.90\times$ | **+4 Sparks** | 9 |
| **Rebirth IV** | **Level 130** | $2.65\times$ | $2.35\times$ | **+5 Sparks** | 14 |
| **Rebirth V** | **Level 165** | $3.35\times$ | $2.90\times$ | **+6 Sparks** | 20 |
| **Rebirth VI** | **Level 200** | $4.20\times$ | $3.55\times$ | **+7 Sparks** | 27 |
| **Rebirth VII** | **Level 240** | $5.25\times$ | $4.30\times$ | **+8 Sparks** | 35 |
| **Rebirth VIII** | **Level 285** | $6.50\times$ | $5.20\times$ | **+9 Sparks** | 44 |
| **Rebirth IX** | **Level 335** | $8.00\times$ | $6.25\times$ | **+10 Sparks** | 54 |
| **Rebirth X** | **Level 400** | $10.00\times$ | $7.50\times$ | **+12 Sparks** | 66 |
| **Rebirth XI+** | $400 + 75(R - 10)$ | $10.0 + 2.0(R - 10)$ | $7.5 + 1.25(R - 10)$ | **+12 Sparks** | $+12/\text{tier}$ |

---

## 33. The 5 Mandatory Visual, World Readability & Hazard Upgrades (Step SP-1)

> **CRITICAL DIRECTIVE FOR CLAUDE CODE:**
> Before or alongside wiring the remaining Town stations, Claude Code MUST implement these 5 concrete visual & gameplay upgrades in Haven Outpost and World 1:

### 33.1 Upgrade 1: Oversized Landmark Interactables ($2.2\times - 2.8\times$ Player Scale)

* **The Scale Rule (Except Rift Portal):** Currently, interactable stations in Haven Outpost and stages are roughly player-sized, making them hard to spot. Every interactable station (Blacksmith, Ascension Pedestal, Spark Sanctum, Star-Forge, Legion Hall, Rift Shrine, Quest Board, Hall of Champions, and Treasure Shrines)—**EXCEPT the main Rift Gate Portal**—MUST be scaled up to **Hero Landmark Scale ($12\text{ to }16\text{ studs tall, }10\text{ to }14\text{ studs wide}$, roughly $2.2\times - 2.8\times$ player height)**.
* **Expanded Interaction Radius:** Set `ProximityPrompt.MaxActivationDistance = 18` and `RequiresLineOfSight = false` on all oversized interactables so players can trigger them comfortably from the front of the platform.

### 33.2 Upgrade 2: Unique Custom-Themed Base Platforms (Sanctuary Daises) for Each Interactable

Every interactable MUST sit on its own distinct, bespoke multi-part platform rather than sharing generic floor blocks:

1. **Blacksmith Platform (*"Molten Obsidian Forge Deck"*):** Dark basalt & iron-riveted octagonal deck with glowing magma cracks running through the floor, an oversized runesmith anvil, a quenching barrel, a rack of glowing weapons, and rising ember sparks.
2. **Ascension Pedestal Platform (*"Celestial Marble Sanctum"*):** Levitating 3-tiered white-and-gold marble temple dais with floating golden steps, 4 ornate spiral pillars, a giant levitating gyroscope astrolabe overhead, and upward-drifting golden starlight motes.
3. **Spark Sanctum Platform (*"Astral Constellation Dais"*):** Deep cosmic-indigo starstone ring inlaid with glowing neon-gold constellation lines and floating prism crystals.
4. **Star-Forge & Relic Vault Platform (*"Amethyst Geode Pedestal"*):** Split crystalline cavern base studded with giant translucent purple/cyan crystal clusters, a levitating crystalline anvil, and orbiting star-shards.
5. **Legion Hall Platform (*"Grand Podium of Blades"*):** Crimson-carpeted royal sandstone podium flanked by 4 towering golden war-banners, crossed giant ancestral weapons, and brazier torches.
6. **Rift Shrine Platform (*"Resonant Obelisk Fountain"*):** Circular mossy rune-stone basin filled with glowing cyan spirit water and 3 floating obelisk shards.

### 33.3 Upgrade 3: Persistent, Always-Pointing Waypoints That Hover Over Interactables When Near (`WaypointController.luau`)

* **NEVER Hide Waypoints When Near:** Currently, waypoints only work off-screen or disappear when the player approaches. Waypoints must **always keep pointing to the interactable**.
* **Two-State Continuous Tracking (`RunService.RenderStepped`):**
  1. **Far / Off-Screen State ($\text{Distance} > 30\text{ studs}$):** Displays a directional indicator arrow pointing directly toward the station, showing the station's icon, name, and distance.
  2. **Near Hover State ($\text{Distance} \le 30\text{ studs}$):** Instead of hiding, the waypoint smoothly transitions to **hover directly over the top apex of the interactable** (`WorldPosition = InteractableTop + Vector3.new(0, 4.5 + math.sin(os.clock() * 3.5) * 1.1, 0)`). It renders a high-contrast **Downward-Pointing Animated Chevron (`▼`)** that continuously bobs up and down while pointing straight at the interactable, paired with its floating name badge.

### 33.4 Upgrade 4: Bright Blue-Sky Fantasy Vista ("Wow, There's So Much to Explore") & High-Contrast World 1 Platforms

* **Radiant High-Fantasy Daytime Sky (`Lighting` & Vista Overhaul):**
  * Configure a bright, crystal-clear blue sky (`Lighting.ClockTime = 14.2`, `Brightness = 2.6`, `OutdoorAmbient = Color3.fromRGB(135, 165, 210)`, azure-blue `Sky`, soft `SunRaysEffect`, and low-haze `Atmosphere`).
  * Populate the background vista ($Z = -35\text{ to }-180\text{ studs}$) with a breathtaking *MapleStory*-inspired fantasy horizon: **floating sky-islands with cascading animated waterfalls**, a colossal **ancient World Tree** on the horizon, distant sunlit castle spires and stone aqueduct arches, fluffy low-poly drifting clouds, and rising golden spirit motes so players immediately feel *"wow, there's so much to explore!"*
* **World 1 (Mushroom Wilds) Monster Stage Platform Contrast Rule:**
  * Make the elevated jump platforms in World 1 monster stages much more lush and grassy (thick overhanging turf cushion, hanging vines, wildflowers, and mini-sprouts), **BUT ensure they NEVER visually blend into the bottom ground floor**:
    1. **Ground Floor (`Y <= 2`):** Deep, rich **Shadowed Forest Emerald Turf (`Color3.fromRGB(46, 108, 54)`, `Material = Grass`)** over heavy **Dark Slate & Basalt Cliff Stone (`Color3.fromRGB(52, 54, 66)`)**.
    2. **Elevated Jump Platforms (`Y > 2`):** Bright, sunlit **Vibrant Spring Chartreuse-Lime Grass (`Color3.fromRGB(118, 222, 78)`, `Material = LeafyGrass`)** overhanging by $+0.6$ studs, cradled inside a distinct **Warm Carved Ancient Timber & Tan Sandstone Frame (`Color3.fromRGB(155, 118, 78)`)** with a subtle bottom highlight rim so players can distinguish jump platforms from the ground floor in 0.1 seconds.

### 33.5 Upgrade 5: Stage 3 Rising Poison Overhaul ("Floor is Lava" Bubbling Acid Flood)

* **Visual Overhaul (Replace Flat Green Bar):**
  * Transform the Stage 3 rising poison into a **3-Layer Animated Bubbling Acid Flood**:
    1. **Top Wave Crest Layer:** Translucent `Neon` venomous lime-green surface (`Color3.fromRGB(115, 255, 45)`, `Transparency = 0.28`) with a scrolling/pulsing foam texture (`Texture`) and undulating wave motion on `Heartbeat`.
    2. **Deep Toxic Sludge Body:** Darker emerald-viridian liquid body (`Color3.fromRGB(28, 125, 42)`, `Material = Glass`, `Transparency = 0.15`) with an upward green glow (`SurfaceLight`).
    3. **3D Bursting Acid Bubbles & Toxic Fumes:** Continuously spawn 3D `Neon` green bubble spheres across the surface that swell and pop into splash rings, plus rising purple/green toxic fume particles.
* **Server-Authoritative "Floor is Lava" Damage & Upward Bounce (`HazardService.luau`):**
  * Run a `0.4s` check while the Rising Poison room is active (`HumanoidRootPart.Position.Y <= CurrentPoisonSurfaceY + 1.5`):
    * **Damage Per Tick:** Deals **$8\%$ of the player's Max HP** as Poison Damage per `0.4s` tick (with floating green/purple damage numbers and a brief toxic green screen vignette flash).
    * **"Floor is Lava" Panic Bounce:** Immediately launches the player upward (`AssemblyLinearVelocity = Vector3.new(currentVel.X, 68, 0)`) so touching the poison burns them and bounces them into the air like hot lava.

---

## 29. Single-Player World 1 Completion Roadmap (Phases SP-1 to SP-6 — No Co-op Yet)

> **MODEL NOTE FOR CLAUDE:** Default to **Sonnet** for Steps SP-1 through SP-5. Let the user know to switch to **Opus** only when starting **Step SP-6** (DataStore session locking and concurrency race-condition fixes).

| Step | Target Systems | Files to Create / Modify | Model Recommendation |
| :--- | :--- | :--- | :--- |
| **Step SP-1: The 5 Visual, Landmark, Vista & Acid Lava Upgrades** | 1. Scale interactables (except Rift Gate) to 2.2x–2.8x on custom themed platforms.<br>2. Persistent waypoints that hover/bob over interactables when near.<br>3. Clear blue-sky fantasy vista (floating waterfall islands, World Tree).<br>4. High-contrast grassy World 1 platforms.<br>5. Stage 3 Rising Poison texture + 8% Max HP damage + lava bounce. | Modify Town/Stage builder scripts, waypoint UI script, lighting/scenery generator, and Stage 3 poison room logic. | **Default (Sonnet)** |
| **Step SP-2: Blacksmith, Inventory/Loadout UI & Hand-Held Weapon Models** | 1. Wire **Blacksmith** station panel to unlock weapons with Dust + Cores.<br>2. Build **Inventory & Loadout UI** (`I` hotkey + HUD Bag button) to equip Weapons & Link Skills.<br>3. Weld the equipped 3D weapon model into the player's right hand in Town and Runs. | Create/update `BlacksmithPanel`, `InventoryController`, `InventoryService`, and character weapon-hand welding logic. | **Default (Sonnet)** |
| **Step SP-3: Weapon Mastery XP on Kill, Link Skill Unlocks & Paragon Ranks** | 1. Award Weapon Mastery XP on every enemy/elite/boss kill.<br>2. Auto-level Weapon Mastery (1–20) and Paragon Ranks (21+).<br>3. Unlock Tier 1 Link Skill at Mastery 10 and Tier 2 at Mastery 20 with HUD level-up toast. | Update `CombatService` / enemy death handler, `PlayerDataService`, and HUD mastery bar/toast. | **Default (Sonnet)** |
| **Step SP-4: Implement Weapons 4–8 (Bow, Hammer, Gauntlets, Summoning Bell, Trick Cards)** | Write full server + client basic attack, `Q` ability, innate passive, and projectile/summon VFX for all 5 remaining weapons so all 8 weapons are 100% playable. | Update `CombatService`, weapon attack handlers, projectile/summon controllers, and `WeaponConfig`. | **Default (Sonnet)** |
| **Step SP-5: Relics, Boss/Chest Drops, Star-Forge Station & Curses** | 1. Implement the 8 Relics (`RelicConfig`) and their passive combat hooks.<br>2. Make Bosses and Chests drop Relics (duplicates convert to +5 Relic Shards).<br>3. Wire the **Star-Forge** Town station UI ($1\star \rightarrow 5\star$ upgrading + Pity bar + equipping Starting Relics).<br>4. Wire Shrine Curse offers. | Create/update `RelicConfig`, `RelicService`, `StarForgePanel`, and Curse shrine choices. | **Default (Sonnet)** |
| **Step SP-6: Data Safety, Quests, Hall of Champions & Mobile Controls** | 1. Add DataStore session locking (prevent dual-server profile load) and fix the save/loot race condition.<br>2. Wire **Quest Board** (daily/repeatable quests) and **Hall of Champions** leaderboards.<br>3. Add Mobile touch buttons. | Update `PlayerDataService`, `QuestBoardPanel`, `LeaderboardService`, and mobile HUD buttons. | **Switch to Opus** *(Remind user before starting SP-6)* |

---

## 30. Post-World 1 Roadmap (Deferred Until Steps SP-1 to SP-6 Are Done)

Once **Steps SP-1 through SP-6** are complete and the Single-Player World 1 loop is 100% polished, development will proceed to:

1. **Phase C-1 (Co-op Party Join Flow):** Add a Party Create / Join UI at the Rift Gate to connect to the existing server-side party & Sidekick Sync system.
2. **Phase W-2 (Worlds 2–8 Content Expansion):** Add *Toy Kingdom*, *Haunted Metro*, *Frozen Citadel*, and unique world bosses.
3. **Phase EX-1 (MapleStory Expansion Systems):** Collectible Damage Skins, Boss Familiar Cards, AFK Dojo Training Grounds, 8-Player Raids, Weapon Potential Cubing, Guild Citadels, and Daily Mirror Rift Seeds.