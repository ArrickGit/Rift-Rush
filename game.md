# CLAUDE.md — Rift Rush Master Game Design & Implementation Spec (v2.6)

> **Status:** Final Production-Ready Blueprint, Audited Math Engine, Asset Pipeline & Claude Pro Workflow Guide (v2.6)
> **Platform:** Roblox (PC, Mobile, Console)
> **Genre:** 2.5D PvE Action Roguelite with Endless Permanent Progression & Rebirths
> **Working Title:** Rift Rush
> **Document Purpose:** Serve as the single source of truth (`CLAUDE.md`) for Claude Code to build **Rift Rush** end-to-end while respecting the developer's **Claude Pro ($30 SGD/mo)** rate limits through explicit step boundaries, `/model` switching recommendations, and `/clear` checkpoints.

---

## 0. AI Agent Execution Rules & Claude Pro ($30 SGD/mo) Token Management Protocol

> **CRITICAL INSTRUCTIONS FOR CLAUDE CODE — READ BEFORE EVERY ACTION:**

### 0.1 Mandatory Coding & Architecture Standards
1. **Strict Luau Typing:** Every `.luau` script MUST begin with `--!strict` and use explicit type annotations for function parameters, return types, and data structures.
2. **Server Authority:** Never trust the client for damage calculations, currency payouts, Rebirth eligibility, Ascension Shop purchases, or room completion. Use `ReplicatedStorage.Shared.FormulaEngine` on the server as the single source of truth.
3. **Zero Missing-Asset Crashes:** Never assume a 3D `MeshPart` or `ImageLabel` asset already exists in `ReplicatedStorage.Assets`. Always route model and icon creation through `AssetRegistry.luau` (Section 31.6) and `ModelNormalizer.luau` (Section 31.7) so the game automatically generates clean, glowing procedural fallbacks when a custom 3D model is not present.
4. **2.5D Plane & Collision Discipline:** All player characters and monsters MUST be constrained to the $Z = 0$ combat plane using `AlignPosition` or `PlaneConstraint`, and assigned to the `"ActorsNoCollide"` collision group so players and monsters never push each other along the Z-axis.

### 0.2 Mandatory Token-Saving & Model-Switching Protocol (For $30 SGD Claude Pro Plan)
To prevent the user from hitting the 5-hour rolling token limit on the Claude Pro plan, **Claude Code MUST enforce the following workflow at all times**:

1. **Build Strictly One Step at a Time (Never Monolith-Dump):**
   * Follow the **6 Build Steps in Section 29** one step per session.
   * **NEVER** attempt to write all 20 files in a single conversation turn. Complete **ONLY** the files listed in the current Step, verify there are no syntax/type errors, and then **STOP**.
2. **Mandatory End-of-Step Checkpoint Message:**
   * At the end of every completed Step, output a concise summary (max 10 bullet points) of the files created/modified and print this exact reminder box for the user:
     ```text
     ====================================================================
     ✅ STEP [X] COMPLETE!
     💡 TOKEN-SAVING ACTION REQUIRED BEFORE CONTINUING:
     1. Type `/clear` right now to wipe chat history and save 60%+ of your Pro quota.
     2. Recommended model for Next Step (Step [X+1]): `/model [sonnet OR opus]`
     3. Recommended Thinking Mode for Next Step: [OFF / ON]
     4. Next Prompt to Copy-Paste: "Read CLAUDE.md and execute Step [X+1]."
     ====================================================================
     ```
3. **Model Selection Matrix (`sonnet` vs. `opus`):**
   * **Default Model (`/model sonnet` — Use for 90% of work):** Use **Claude Sonnet** for all config tables, data services, UI generation (`ScreenGui`), ASCII room templates, `AssetRegistry` procedural models, and shop/economy wiring.
   * **Precision Physics/Audit Model (`/model opus` — Use ONLY for Step 2 & Final Audit):** Only recommend switching to **Claude Opus** when implementing complex 2.5D platform physics/raycasting (Step 2) or debugging a tricky multi-script race condition. Always instruct the user to switch back to `/model sonnet` immediately afterward!
4. **Targeted File Reading:**
   * Do not read the entire codebase into context on every turn. Only read the specific `.luau` files directly imported by the script you are currently editing.

---

## 1. High Concept

**Rift Rush** is a fast-paced 2.5D Roblox PvE action roguelite inspired by classic side-scrolling RPGs like *MapleStory*. Players enter unstable dimensional portals, clear short randomized rooms, assemble visually explosive combat builds, complete platforming "Jump Quest" rooms, defeat multi-phase bosses, and decide whether to extract safely with their loot or push deeper for massive reward multipliers.

While each run resets the player's temporary combat build, collected resources feed into an endless, deeply satisfying grind loop: leveling the player's **Hunter Level** to perform prestigious **Rift Rebirths** (at Levels 50, 75, 100, 130, 165, 200+), spending **Rebirth Sparks** in the **Ascension Shop**, unlocking weapons, building an account-wide **Hunter Legion** (Link Skill bonuses), Star-Forcing permanent Relics, and climbing 100+ **Portal Corruption Tiers**. Players can spend Robux to recover failed high-stakes runs, insure unsecured loot, trigger **Instant Rebirths** without reaching the level cap, pay to **Keep Everything** during a Rebirth, and supercharge their progression speed.

### Intended Player Feeling

* **Instant Gratification:** Easy to understand within the first 60 seconds, with rooms lasting 20–45 seconds.
* **Screen-Clearing Power Fantasy:** Upgrades visually transform basic skills into screen-filling spectacles (reminiscent of 4th/5th Job *MapleStory* skills) within a 10-minute run.
* **Addictive Rebirth & Milestone Grind:** Every run pushes the player closer to their next **Rift Rebirth**, granting permanent compounding damage/drop multipliers, **Rebirth Sparks**, and flashy overhead Rebirth Wings.
* **High-Stakes Extraction Tension:** Continuing past a boss checkpoint puts unsecured loot on the line, making survival thrilling and paid recovery/insurance genuinely valuable.
* **Generous & Cooperative Social Play:** Playable solo or in 1–4 player parties, with individual extraction choices, **Rift Sidekick Sync** (so friends of any level can play together), and celebratory server-wide buffs.

---

## 2. One-Sentence Pitch

Enter randomized 2.5D portals, evolve basic attacks into screen-clearing builds one room at a time, and choose whether to cash out your loot at a Rift Anchor or risk it all to fuel endless Rebirths and mastery.

---

## 3. Core Design Pillars

### 3.1 Short Bursts of Action
Rooms last between 20 and 45 seconds. Players constantly cycle through combat waves, platforming challenges, treasure events, upgrade selections, and route decisions without dull walking downtime.

### 3.2 Builds That Visibly Transform
Upgrades alter how abilities behave mechanically and visually rather than merely adding flat percentage stats. A simple single-target projectile can split into multiple projectiles, chain between platforms, leave burning ground trails, and rain down meteors on critical hits.

### 3.3 Risk Versus Reward Extraction
At every boss checkpoint (**Rift Anchor**), players face a clear choice: extract safely with $100\%$ of their accumulated loot, or push deeper into higher-multiplier rooms where defeat results in losing a portion of unsecured rewards.

### 3.4 Endless MapleStory-Style Grinding & Prestige Rebirths
Players repeat runs to fuel deep, interlocking permanent progression systems (**Hunter Level & Rebirths**, **Ascension Shop Perks**, Weapon Mastery, Hunter Legion Link Skills, Relic Star-Forcing, and Corruption Tiers), while procedural room ordering, curses, and build synergies keep the grind fresh.

### 3.5 High-Value, Non-Predatory Paid Power
Robux purchases provide tangible gameplay utility—saving failed runs, insuring high-risk loot, performing **Instant Rebirths**, **Keeping Everything on Rebirth**, banishing unwanted RNG upgrades, and supercharging drop rates—while keeping all core content earnable through dedicated grinding.

### 3.6 Frictionless Co-op Without Forced Griefing
The entire game is solo-friendly, while 1–4 player parties enjoy combo synergies, clutch revives, and cooperative objectives. **Individual Extraction** at checkpoints ensures no player is ever held hostage or forced to lose their loot by a party vote.

---

## 4. Target Audience & Session Targets

### Primary Audience
* Roblox players who love anime dungeons, simulators, Rebirth systems, visible power scaling, and flashy combat effects.
* Fans of *MapleStory* and classic side-scrolling RPGs who enjoy vertical platforming, flashy mobbing, and long-term account progression.
* Friend groups looking for a drop-in cooperative PvE game without toxic PvP griefing.

### Secondary Audience
* Action roguelite players (*Hades*, *Dead Cells*, *Risk of Rain*) who enjoy theorycrafting build synergies and pushing high-difficulty modifiers.
* Leaderboard grinders and completionists who want to reach Rebirth X+, max out every weapon's Link Skill, and climb pure-run rankings.

### Intended Session Length
* **First-Time Onboarding Session:** 12–20 minutes (includes tutorial run + first permanent upgrades + second run to Room 10).
* **Standard Portal Run (Rooms 1–10):** 8–12 minutes.
* **Extended Deep Run (Rooms 11–20):** 15–25 minutes.
* **Endless High-Corruption Run (Rooms 21+):** 30+ minutes.

---

## 5. Game Structure

### 5.1 The Town Hub (Haven Outpost)
The Town Hub is a vibrant 2.5D multi-tiered social space (inspired by *Henesys* and *Perion*) where players gather, show off their Rebirth Wings, weapon auras, and titles, and manage permanent progression. It contains:
* **The Central Rift Gate:** Enter solo, manage parties, select Portal Worlds, and adjust **Corruption Tiers**.
* **The Ascension Pedestal & Spark Sanctum (Rebirth Altar):** Perform **Rift Rebirths** once the required Hunter Level is met (or via Robux), spend **Rebirth Sparks** in the **Ascension Shop**, and preview next Rebirth multipliers.
* **Mastery & Legion Hall:** View weapon mastery levels, equip account-wide **Hunter Link Skills**, and claim milestone rewards.
* **The Star-Forge & Relic Vault:** View discovered Relics and spend *Rift Dust* or duplicate Relic shards to Star-Force them.
* **Blacksmith & Weapon Trainer:** Unlock new weapons and test builds on training dummies with a live DPS meter.
* **Rift Shrine (Server Booster Altar):** Trigger Robux or milestone-earned **Rift Surges** (server-wide atmospheric buffs with visual skybox effects).
* **Quest Board & Bounty NPC:** Manage Daily, Weekly, and Mastery quests.
* **Hall of Champions:** Separate physical podiums and leaderboards for **Standard Runs**, **Pure Runs**, and **Top Rebirth Rank**.

### 5.2 Portal Runs
Portal runs consist of modular 2.5D rooms grouped into 5-room stages:

| Room Range | Stage Phase | Expected Content |
| :--- | :--- | :--- |
| **Rooms 1–4** | Stage 1: Entry | Fast mobbing rooms, 1 platforming/collection room, and 1 guaranteed Special/Shrine room. |
| **Room 5** | **First Rift Anchor** | **Mini-Boss / Stage 1 Boss.** Activates the first Rift Anchor (Checkpoint & Extraction Point). |
| **Rooms 6–9** | Stage 2: Deep Rift | Higher enemy density, Elite enemies with 1 mutation, Cursed Chest opportunities, and a Travelling Merchant. |
| **Room 10** | **Main Rift Anchor** | **World Boss.** Activates the main Rift Anchor. Unlocks the next Portal World or Corruption Tier upon completion. |
| **Rooms 11–14** | Stage 3: Overdrive | Endless-tier scaling begins. Enemies gain dual elemental mutations; reward and XP multipliers escalate rapidly. |
| **Room 15** | **Overdrive Anchor** | **Mutated Boss.** Drops rare Relic Shards and high Boss Core quantities. |
| **Rooms 16–20** | Stage 4: Abyssal | Former Stage 1 Mini-Bosses spawn as regular Elite enemies; platforming hazards intensify. |
| **Rooms 21+** | Endless Chaos | Extreme density, chaotic mutators, leaderboard glory, and maximum shiny/aura drop rates. |

---

## 6. Core Gameplay Loops

### 6.1 Minute-to-Minute Room Loop (20–45 Seconds)
1. **Enter Room:** Objective flashes clearly at the top of the screen (e.g., *"Clear 35 Corrupted Spores"* or *"Ascend Before the Poison Rises"*).
2. **Execute & Mob:** Use 2.5D movement (double jumps, platform drops, dashes, jump pads) to group enemies and unleash multi-hit skills.
3. **Clear & Collect:** Enemies explode into loot bursts (*Hunter XP*, *Rift Dust*, coins, health orbs); room completion chest spawns.
4. **Upgrade & Route Selection:** Pick 1 of 3 (or 4 with Gamepass) transformative upgrades, then jump into the next portal door.

### 6.2 Run-to-Run Extraction Loop (8–20 Minutes)
1. **Prep in Town:** Equip a Weapon, Starting Ability, Starting Relic (if unlocked), and active **Hunter Link Skills**.
2. **Build Power:** Progress through rooms, combining active ability evolutions, passive Relics, and optional high-risk Curses.
3. **Reach a Rift Anchor (Room 5, 10, 15...):** Defeating the boss automatically **Secures** $100\%$ of current rewards and Hunter XP, opening the Extraction UI.
4. **Make the Extraction Decision:**
   * **Extract Now:** Return to Town with $100\%$ of Secured and Unsecured loot.
   * **Push Deeper:** Keep your overpowered build and gain an increasing Reward & XP Multiplier, knowing that dying before the next Anchor risks a portion of your **Unsecured Loot**.
5. **Resolution:** Extract safely at a later Anchor, or get defeated and choose between accepting partial loss, using an earned **Anchor Token**, or spending Robux to **Revive / Rewind / Insure**.

### 6.3 Long-Term Grind & Rebirth Loop (10–300+ Hours)
1. **Level Up Your Hunter Level:** Earn Hunter XP from every monster and boss to reach your current **Rebirth Target Level** (starting at Level 50, then 75, 100, 130, 165, 200...).
2. **Perform a Rift Rebirth:** Reset your Hunter Level, standard world access, and unspent *Rift Dust* (or pay Robux to **Keep Everything!**) in exchange for a massive **Permanent Stat & Drop Multiplier**, **Rebirth Sparks**, and prestigious **Rebirth Wings/Crests**.
3. **Spend Rebirth Sparks in the Ascension Shop:** Unlock game-changing permanent account upgrades (extra Dash charges, Starting Upgrade Orbs, Auto-Loot Magnet, and damage-cap breakers).
4. **Grind Weapon Mastery & Hunter Legion:** Level every weapon to Mastery 20 to unlock its account-wide **Link Skill**, then push your favorite weapon into **Infinite Paragon Ranks (Mastery 21–999)**.
5. **Star-Force Your Relic Collection:** Collect duplicate Relics and *Rift Dust* to upgrade Relics from 1-Star to 5-Star.
6. **Climb Portal Corruption Tiers:** Beat World 1–8 on Normal, then use your compounded Rebirth multipliers to push **Corruption Tiers 1 to 100+**.

---

## 7. Player Presentation, Camera & 2.5D Physics Rules (Locked Decision)

### 2.5D Side-Scrolling Action Format
Rift Rush officially uses a **2.5D side-scrolling perspective** inside a rich 3D Roblox environment.
* **Movement Axes & Z-Plane Lock (Crucial Physics Rule):** Players and monsters move along the X-axis (left/right) and Y-axis (jumping, double-jumping, dropping down through one-way platforms, climbing ropes/ladders, and riding launch pads). To prevent Roblox physics collisions from knocking players or enemies off the combat plane, all characters and monsters have an `AlignPosition` / `PlaneConstraint` locking their RootPart to $Z = 0$ (and `CollisionGroup = "ActorsNoCollide"` so players and monsters pass cleanly through each other without physics flinging).
* **Vertical Stagger Instead of Horizontal Knockback:** Heavy weapons (like *Hammer* or *Greatsword*) apply **Vertical Launch / Micro-Stun** in place rather than horizontal knockback, ensuring melee players never accidentally knock enemies out of a *Staff* or *Bow* teammate's AoE spells, nor push enemies off upper platforms.
* **Camera Settings:** Orthographic-like narrow FOV ($35^\circ$) at a side offset of $Z = +42$ studs, with smooth spring-damped vertical tracking so high platform jumps feel crisp and readable on PC, Console, and Mobile.

---

## 8. Controls & Cross-Platform Ergonomics

### Core Inputs

| Action | PC (Keyboard/Mouse) | Controller | Mobile |
| :--- | :--- | :--- | :--- |
| **Move / Drop Platform** | `A` / `D` (`S` + `Space` to drop) | Left Stick | Left Virtual Joystick |
| **Jump / Double Jump** | `Space` | `A` / `Cross` | Dedicated Jump Button |
| **Basic Attack (Holdable)** | `Left Click` or `J` | `X` / `Square` | Large Primary Attack Button |
| **Dash / Flash Jump** | `Shift` or `K` | `B` / `Circle` | Dash Button |
| **Ability 1 & Ability 2** | `Q` / `E` | `LB` / `RB` | Skill Buttons 1 & 2 |
| **Ultimate Skill** | `R` | `LT + RT` | Ultimate Button (glows when full) |
| **Interact / Ping** | `F` / `G` | `Y` / `Triangle` | Context-sensitive tap prompt |

---

## 9. Combat Design

### Combat Rhythm & "Mobbing" Feel
1. **Herd & Group:** Normal enemies spawn in clusters across 2–3 platform tiers.
2. **Cleaving & Chaining:** Basic attacks and abilities hit multiple targets simultaneously with punchy hit-stop ($0.04\text{s}$), floating MapleStory-style cascading damage numbers, and satisfying sound effects.
3. **Telegraphed Danger:** Elites and Bosses use bold, high-contrast ground/air warning zones before unleashing heavy attacks, rewarding well-timed Flash Jumps or dashes.
4. **Combo Meter:** Consecutive hits within a $4\text{s}$ window build a **Rift Combo** counter ($10\times$, $25\times$, $50\times$, $100\times$, $250\times$), granting movement speed and Ultimate charge rate bonuses.

### Damage Types & Elemental Status Synergies
* **Physical (Bleed):** Rapid hits stack Bleed (up to 10 stacks); each stack deals $15\%$ of Base Attack per second. Reaching 10 stacks triggers a *Hemorrhage* burst for $250\%$ of Player Attack (capped at $5\%$ of Boss Max HP).
* **Fire (Burn):** Deals $40\%$ of Base Attack per second for $4\text{s}$ and spreads to nearby enemies within $10$ studs when a burning target dies.
* **Ice (Chill / Freeze):** Slows enemy movement and attack speed by $6\%$ per stack; reaching 5 stacks encases non-boss enemies in ice for $2.5\text{s}$ (shattering for $180\%$ AoE damage when hit by heavy attacks).
* **Lightning (Shock):** Causes attacks against the target to chain lightning bolts to up to 3 nearby enemies across platforms for $45\%$ of hit damage.
* **Poison (Toxin):** Inflicts infinitely stacking poison ticks ($20\%$ Base Attack per stack per second) and reduces enemy damage dealt by $15\%$.
* **Arcane (Mark):** Marks the target for $5\text{s}$; the next ability hit consumes the Mark to deal guaranteed Critical Damage and reduce active skill cooldowns by $1.0\text{s}$.

---

## 10. Weapons

Weapons define the player's base attack animations, attack speed, innate passive trait, starting ability pool, and **Hunter Legion Link Skill**.

| Weapon | Archetype & Playstyle | Base Weapon Damage (`W_Base`) | Attacks / Sec | Innate Weapon Passive | Account-Wide Link Skill (Mastery 10 / 20) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Greatsword** | Wide-arc melee cleaver | $42$ | $1.1$ | **Berserker's Momentum:** Hitting 3+ enemies grants $+15\%$ Attack Speed for $3\text{s}$. | **Titan's Might:** $+8\% / +15\%$ Damage to Normal & Elite Monsters. |
| **Daggers** | Hyper-mobile assassin | $18$ | $2.6$ | **Shadow Step:** Dashing through an enemy guarantees your next attack is a Critical Hit. | **Lethal Instinct:** $+10\% / +20\%$ Critical Damage. |
| **Staff** | Elemental mage | $32$ | $1.4$ | **Elemental Resonance:** Inflicting 2 different status effects triggers an Arcane Nova ($150\%$ AoE). | **Arcane Flow:** $+8\% / +15\%$ Elemental Status Damage & Duration. |
| **Bow** | Long-range sniper & volley | $22$ | $2.2$ | **Hurricane Focus:** Consecutive hits on the same target increase damage by $+3\%$ per arrow (up to $+30\%$). | **Eagle Eye:** $+5\% / +10\%$ Critical Hit Rate. |
| **Hammer** | Heavy crowd-control | $50$ | $0.9$ | **Seismic Impact:** Ground slam attacks deal $+40\%$ stagger damage and generate a $5\%$ Max HP shield. | **Crushing Force:** $+8\% / +15\%$ Boss Damage. |
| **Gauntlets** | Rapid combo brawler | $16$ | $3.0$ | **Combo Overdrive:** Rift Combo meter never decays while dashing and grants $+1\%$ damage per 10 combo. | **Relentless Flurry:** $+6\% / +12\%$ Attack Speed & Cooldown Recovery. |
| **Summoning Bell** | Spirit commander | $26$ | $1.5$ | **Soul Pack:** Summons inherit $100\%$ of your status-effect procs and attack speed bonuses. | **Rift Fortune:** $+10\% / +20\%$ *Rift Dust* Drop Rate. |
| **Trick Cards** | High-roller gambler | $25$ | $1.8$ | **Loaded Deck:** Every 6th basic attack draws a random Royal Card (Red = AoE, Blue = CDR, Gold = Dust). | **Lucky Draw:** $+8\% / +15\%$ Rare/Epic Upgrade Appearance Rate. |

---

## 11. Active Abilities & Visual Evolutions

Players start a run with their weapon's signature ability and can acquire a second active ability plus an Ultimate during the run.

### Example Evolution Tree: Staff — *Fireball*
* **Base Skill:** Fires a blazing orb horizontally ($220\%$ Weapon Damage, $3.5\text{s}$ cooldown) that explodes on the first enemy hit.
* **Evolution 1 (Multi-Cast):** *Triple Threat* — Fires 3 Fireballs in a $20^\circ$ fan across multiple platform heights (each dealing $75\%$ of full skill damage; shotgunning a large boss hits with all 3 for $225\%$ damage!).
* **Evolution 2 (Terrain):** *Napalm Wake* — Fireballs leave a scorching carpet of fire along the platform for $4\text{s}$ ($45\%$ Weapon Damage per second).
* **Evolution 3 (Chain Reaction):** *Volatile Cinders* — Enemies that die while Burning explode into 2 homing mini-fireballs ($80\%$ Weapon Damage each).
* **Evolution 4 (Capstone Synergy):** *Cataclysmic Meteor* — Every 5th Fireball cast calls down a giant diagonal meteor from the top of the screen ($500\%$ Weapon Damage across the entire platform tier).

---

## 12. Run Upgrades & RNG Control

After clearing combat and platforming rooms, an Upgrade Orb drops, offering **3 Upgrade Cards** (or **4 Cards** with the *VIP Architect* Gamepass).
* **Base Rarity Weights:** Common ($55\%$), Rare ($28\%$), Epic ($12\%$), Legendary ($4\%$), Corrupted ($1\%$).
* **Depth & Luck Scaling:** Every 5 rooms cleared shifts $+5\%$ weight from Common into Rare/Epic/Legendary, and the *Lucky Draw* Link Skill + Ascension Shop perks further boost Epic/Legendary appearance rates.
* **Upgrade Rerolls & The Banish System:** Players earn free Rerolls via Rebirths and the Ascension Shop, and can use the **Banish Pass** (or Ascension Shop *Fate Manipulation* perk) to permanently banish unwanted upgrades from the drop pool for the rest of that run.

---

## 13. Relics & The Star-Force Awakening System

Relics are passive artifacts found in Treasure Rooms, Boss Drops, and Shops. Finding duplicate Relics in runs grants **Relic Shards**, which are combined with *Rift Dust* in Town to **Star-Force** Relics from **1-Star up to 5-Star (Awakened)**.
* **Non-Destructive Pity Rule:** Failing a Star-Force attempt *never* destroys or downgrades a Relic; instead, it fills a **Star Pity Bar** by $+25\%$ (4 failures = guaranteed $100\%$ success on the next attempt).

| Star Level | Upgrade Cost | Effect on *Thunder Boots* (Example) | Base Success Rate |
| :--- | :--- | :--- | :--- |
| **1-Star (Base)** | First Discovery | Double-jump fires 2 bolts for $50\%$ weapon damage. | $100\%$ |
| **2-Star** | 3 Shards + 500 Dust | Double-jump fires 3 bolts for $65\%$ weapon damage. | $90\%$ |
| **3-Star** | 8 Shards + 1,500 Dust | Bolts now inflict *Shock* and chain to 1 extra target. | $75\%$ |
| **4-Star** | 20 Shards + 4,000 Dust | Double-jump fires 4 bolts for $90\%$ weapon damage. | $50\%$ |
| **5-Star (Awakened)** | 50 Shards + 12,000 Dust | **Awakening:** Every 3rd double-jump leaves a stationary Lightning Totem on the platform for $6\text{s}$. | $30\%$ ($100\%$ with *Star Shield*) |

---

## 14. Curses

Curses are optional high-risk pacts found at Cursed Shrines or offered before Boss rooms:
* **Glass Flame:** Deal $2.0\times$ total damage, but Maximum HP is capped at $50\%$.
* **Mimic's Fortune:** Double the number of Treasure Chests that spawn, but $40\%$ of chests are aggressive Elite Mimics.
* **King's Challenge:** The next Boss spawns with a phantom clone at $50\%$ HP, but drops $2\times$ **Boss Cores** and a guaranteed Epic+ Relic.
* **Unstable Momentum:** Movement speed $+40\%$ and Attack Speed $+25\%$, but standing completely still for more than $1.5\text{s}$ triggers a lightning strike on your position ($10\%$ Max HP damage).
* **Greedy Portal:** All *Rift Dust* drops are increased by $+100\%$, but the next Rift Anchor extraction point is locked.

---

## 15. Room Types & Objectives

* **Combat Rooms:** Extermination, Rift Surge Survival (30s hyper-spawn mobbing), Elite Hunt, Crystal Defense, and Combo Trials.
* **Movement Rooms ("Jump Quests"):** Rising Corruption tower climb, Laser Gauntlet, and Shadow Race. *Failing a Jump Quest room never ends the run; it only forfeits the bonus chest.*
* **Collection & Event Rooms:** Loot Goblin Chase, Mimic Roulette, and Spirit Harvest.
* **Party Synergy Rooms:** Dual Pressure Plates and Split-Lane Relays.
* **Special Utility Rooms:** Travelling Merchant, The Fusion Anvil, and Gambling Shrine.

---

## 16. Portal Worlds & Corruption Tiers

1. **Mushroom Wilds (World 1 — Launch MVP):** Lush multi-tiered forest inspired by *Henesys*. Base World Multiplier: $1.0\times$.
2. **Toy Kingdom (World 2):** Vibrant clockwork towers inspired by *Ludibrium*. Base World Multiplier: $1.8\times$.
3. **Haunted Metro (World 3):** Subterranean subway tunnels (*Kerning City* vibe). Base World Multiplier: $3.2\times$.
4. **Frozen Citadel (World 4):** Slippery ice platforms and blizzard wind pushes. Base World Multiplier: $5.5\times$.
5. **Neon Cyber-Grid (World 5):** Digital synthwave dimension with gravity-flip pads. Base World Multiplier: $9.5\times$.
6. **Dessert Wastes (World 6):** Bouncy jelly pits and sticky caramel floors. Base World Multiplier: $16.0\times$.
7. **Sunken Archive (World 7):** Low-gravity underwater library with current jets. Base World Multiplier: $27.0\times$.
8. **Volcanic Forge (World 8):** Rising magma and swinging foundry hammers. Base World Multiplier: $45.0\times$.

### Portal Corruption Tiers ($C = 0$ to $100+$)
Clearing Room 10 of a World on Normal ($C = 0$) unlocks incremental **Corruption Tiers ($C = 1$ to $100+$)** for that world. Higher Corruption Tiers scale monster HP/damage and reward multipliers exponentially (defined mathematically in Section 24), requiring players to stack **Rift Rebirths**, **Ascension Shop Perks**, Link Skills, and 5-Star Relics to conquer.

---

## 17. Bosses

* **Spore Golem (World 1 Room 5 Mini-Boss):** Telegraphed ground-pound waves and rolling boulder charges across 2 platform tiers.
* **Mushroom Titan (World 1 Room 10 World Boss):** Creates bouncy mushroom trampolines to dodge floor-wide poison waves; fires giant spore boulders players can smack back with basic attacks to stun him for $4\text{s}$.
* **Clockwork King (World 2 Room 10):** Places "Rewind Anchors" on players that snap them back 3 seconds in time.
* **Conductor Phantom (World 3 Room 10):** Summons speeding ghost trains on the lower track.
* **Candy Dragon (World 6 Room 10):** Melts the center platform into boiling caramel and drops jawbreaker bombs.
* **The Collector (Secret Endless Boss — Room 20+):** Dynamically equips and uses the exact **Relics and Upgrades that the party passed up or Banished** earlier in the run.

---

## 18. Difficulty, Dynamic Party Scaling & Rift Sidekick Sync

### 18.1 Dynamic Mid-Run Party Scaling Formula
Let $P \in \{1, 2, 3, 4\}$ be the number of active players currently inside the portal run:
$$\text{PartyHPScale}(P) = 1 + 0.55 \times (P - 1)$$
$$\text{PartySpawnCountScale}(P) = 1 + 0.25 \times (P - 1)$$
*(If 1 player extracts at Room 5, $P$ updates from $4 \rightarrow 3$ immediately for Room 6).*

### 18.2 Rift Sidekick Sync (Audited Fix for Mixed-Rebirth Co-op Parties)
To ensure a **Rebirth V** veteran and their brand-new **Rebirth 0** friend can play in the same party without the newbie dying in 1 hit or boosting to Lv. 100 in 30 seconds:
* **Combat Bolster (Floor):** Any party member whose combined `BaseAtk * RebirthMult * AscensionMult` is less than $70\%$ of the Party Host's baseline is temporarily bolstered up to **$70\%$ of the Party Host's combat power and Max HP** inside that run. They can actively fight, survive boss telegraphs, and contribute meaningful damage!
* **Anti-Boost Reward Cap (Ceiling):** A lower-level player's *Hunter XP* and *Rift Dust* earned per room is capped at **$3.0\times$ the baseline rate of the highest World/Corruption Tier they have personally unlocked**. Joining a high-level friend gives them a massive, exciting $3.0\times$ mentor boost, without letting them skip 50 hours of progression in a single room.

---

## 19. Failure, Extraction, and Checkpoints (Resolved Rules)

* **Secured Vault vs. Unsecured Pouch:** Boss checkpoints (**Rift Anchors** at Room 5, 10, 15, 20...) lock in $100\%$ of rewards earned up to that point. Rewards gathered *between* checkpoints sit in the Unsecured Pouch.
* **Tiered Unsecured Loot Loss Penalty:**
  * **Rooms 1–5:** Lose only $30\%$ of Unsecured *Rift Dust* on defeat (keep $70\%$).
  * **Rooms 6–10:** Lose $50\%$ of Unsecured *Rift Dust* and $100\%$ of Unsecured Relic Shards.
  * **Rooms 11+:** Lose $75\%$ of Unsecured *Rift Dust* and $100\%$ of Unsecured Relic Shards/Bonus Cores.
  *(Note: Hunter XP earned from killing monsters is NEVER lost on defeat, ensuring every run advances the player toward their next Rebirth!)*
* **Individual Party Extraction:** At every Rift Anchor, each player decides independently whether to cash out to Town or continue deeper.

---

## 20. The Defeat Screen & High-Conversion Recovery

When defeated, the **Rift Collapse Screen** clearly shows Safe Secured Loot vs. At-Risk Unsecured Loot and offers:
1. **Accept Defeat (Free):** Return to Town with Secured Loot + surviving fraction of Unsecured Loot.
2. **Use Anchor Token (Earned Free Currency):** Free Rewind or Insure & Extract.
3. **Rift Revive (39 R$):** Instant revive on the spot with $4\text{s}$ invulnerability + full Ultimate.
4. **Checkpoint Rewind (49 R$):** Rewind to the last Rift Anchor with full build & loot intact.
5. **Insure & Extract Now (29 R$):** End the run immediately, rescuing $100\%$ of Unsecured Loot.

---

## 21. Endless Permanent Progression Architecture

Long-term progression is structured across **Seven Interlocking Layers** that feed into one another:

```text
[Layer 1: Hunter Level (1–400+)] ──> Earned every run; grants base HP/Damage & gates Rebirths
       │
[Layer 2: Rift Rebirths (Rebirth I – X+)] ──> Resets Hunter Level for massive Global Multipliers & Rebirth Sparks
       │
[Layer 3: Ascension Shop (Spark Sanctum)] ──> Spend Rebirth Sparks on permanent account-altering perks
       │
[Layer 4: Base Unlocks & Weapon Mastery (1–20)] ──> Unlock all 8 Weapons, Alternate Skills & Passives
       │
[Layer 5: Hunter Legion (Link Skills)] ──> Level ALL Weapons to buff your entire account
       │
[Layer 6: Relic Star-Forcing (1★–5★)] ──> Permanently awaken every Relic in your Vault
       │
[Layer 7: Infinite Paragon (21–999) & Corruption Tiers (1–100+)] ──> Endless scaling & prestige
```

---

## 22. The Rift Rebirth & Ascension System

### 22.1 How Hunter Level & Rebirthing Work
Every player has an overarching **Account Hunter Level** displayed next to their name.
* Every monster killed, room cleared, and boss defeated grants **Hunter XP** (which is never lost on defeat).
* Each Hunter Level grants $+1.5\%$ Base Attack and $+1.5\%$ Base HP (plus $+0.75\%$ per "Retained Legacy Level" from *True Rebirths*).
* Once a player reaches the **Required Hunter Level** for their current Rebirth tier, they can visit the **Ascension Pedestal** in Town to trigger a **Rift Rebirth**.

### 22.2 Stepped Rebirth Level Curve, Multipliers & Spark Payouts

| Rebirth Tier ($R$) | Required Hunter Level ($L_{\text{req}}$) | Target Earned Playtime (Cumulative F2P) | Global Damage & HP Multiplier ($M_{\text{RebDmg}}$) | Rift Dust & Hunter XP Multiplier ($M_{\text{RebEco}}$) | Sparks Awarded ($\Delta S$) | Cumulative Sparks ($S_{\text{total}}$) | Milestone Unlock & Visual Prestige |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Rebirth 0** | Lv. 1 (Start) | 0 Hours | $1.00\times$ | $1.00\times$ | $0$ | $0$ | Novice Hunter Tunic |
| **Rebirth I** | **Level 50** | ~1.5 – 2 Hours | $1.30\times$ ($+30\%$) | $1.25\times$ ($+25\%$) | **+2 Sparks** | 2 | Bronze Rift Wings, Unlocks **Ascension Shop Tier 1** |
| **Rebirth II** | **Level 75** | ~3.5 – 4.5 Hours | $1.65\times$ ($+65\%$) | $1.55\times$ ($+55\%$) | **+3 Sparks** | 5 | Azure Rift Wings, $+1$ Free Upgrade Reroll per run |
| **Rebirth III** | **Level 100** | ~6 – 7.5 Hours | $2.10\times$ ($+110\%$) | $1.90\times$ ($+90\%$) | **+4 Sparks** | 9 | Silver Rift Wings, Unlocks **Ascension Shop Tier 2** & $+1$ Link Slot |
| **Rebirth IV** | **Level 130** | ~9.5 – 11.5 Hours | $2.65\times$ ($+165\%$) | $2.35\times$ ($+135\%$) | **+5 Sparks** | 14 | Amethyst Wings, Start every run with 150 Bonus Gold |
| **Rebirth V** | **Level 165** | ~14 – 17 Hours | $3.35\times$ ($+235\%$) | $2.90\times$ ($+190\%$) | **+6 Sparks** | 20 | Gold Empress Wings, Unlocks **Ascension Shop Tier 3** & $+1$ Relic Slot |
| **Rebirth VI** | **Level 200** | ~20 – 24 Hours | $4.20\times$ ($+320\%$) | $3.55\times$ ($+255\%$) | **+7 Sparks** | 27 | Crimson Phoenix Wings, Unlocks *Abyssal Corruption (50+)* |
| **Rebirth VII** | **Level 240** | ~27 – 32 Hours | $5.25\times$ ($+425\%$) | $4.30\times$ ($+330\%$) | **+8 Sparks** | 35 | Prismatic Crystal Wings |
| **Rebirth VIII** | **Level 285** | ~36 – 43 Hours | $6.50\times$ ($+550\%$) | $5.20\times$ ($+420\%$) | **+9 Sparks** | 44 | Void Archon Wings, Guaranteed Rare+ Upgrade in Room 1 |
| **Rebirth IX** | **Level 335** | ~48 – 57 Hours | $8.00\times$ ($+700\%$) | $6.25\times$ ($+525\%$) | **+10 Sparks** | 54 | Celestial Seraphim Halo & Six Wings |
| **Rebirth X** | **Level 400** | ~64 – 75 Hours | $10.00\times$ ($+900\%$) | $7.50\times$ ($+650\%$) | **+12 Sparks** | 66 | **Ascension Shop Tier 4**, Town Statue + *Transcendent Title* |
| **Rebirth XI+** | $400 + 75(R - 10)$ | Endless Grind | $10.0 + 2.0(R - 10)$ | $7.5 + 1.25(R - 10)$ | **+12 Sparks** | $+12/\text{tier}$ | Roman Numeral Overhead Crest + Infinite Spark Dump |

### 22.3 The 3-Bucket Reset Rule (Standard Free Rebirth vs. "Keep Everything" Robux Rebirth)

| Category | Standard (Free) Rebirth | "True Rebirth — Keep Everything" (99 R$ Single / 599 R$ Pass) |
| :--- | :--- | :--- |
| **1. Hunter Level & Legacy Stat Bonus** | **Resets to Level 1.** | **Resets to Level 1**, **AND permanently banks $+50\%$ of $\max(\text{CurrentLevel}, L_{\text{Req}}(R))$ (capped at $1.25 \times L_{\text{Req}}(R)$) into `LegacyBonusLevels`!** |
| **2. Unspent Rift Dust, World Gates & Weapon Equips** | **Resets:** Unspent *Rift Dust* is consumed (except the portion actively banked in the *Dimensional Pocket* Vault during runs); World 2–8 gates re-lock until Room 10 of the prior world is beaten once; Weapons 2–8 require a small Dust reactivation fee. | **KEPT $100\%$!** You keep **all unspent Rift Dust**, **all Portal Worlds 1–8 stay unlocked**, **all Weapons stay active**, AND you receive **+2 Bonus Rebirth Sparks**! |
| **3. Deep Account Investments** | **Always Kept:** Relics, Star-Force levels, Weapon Mastery, Link Skills, Ascension Shop Upgrades, and Boss Cores are never lost. | **Always Kept.** |

---

## 23. The Ascension Shop (Rebirth Spark Upgrades — Complete Specification)

Located at the **Spark Sanctum** beside the Ascension Pedestal, the **Ascension Shop** is where players spend their **Rebirth Sparks**.

### Complete Ascension Shop Upgrade Catalog (16 Nodes + 2 Infinite Sinks)

#### Tier 1: Initiate Ascendant (Unlocks at Rebirth I — Lv. 50)
| Node ID | Upgrade Name | Max Level | Spark Cost per Level | Effect per Level | Max Level Total Effect |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `AS_T1_01` | **Ascendant Might** | 10 | $1, 1, 1, 2, 2, 2, 3, 3, 4, 5$ (Total: 24) | $+8\%$ Multiplicative Ascension Damage & HP | **$+80\%$ Ascension Damage & HP** ($1.80\times$) |
| `AS_T1_02` | **Rift Scholar** | 5 | $1, 1, 2, 2, 3$ (Total: 9) | $+12\%$ Bonus Hunter XP & Weapon Mastery XP | **$+60\%$ Hunter & Mastery XP** |
| `AS_T1_03` | **Vacuum Aura (Auto-Magnet)** | 3 | $1, 2, 3$ (Total: 6) | Lv 1: $+15$ stud loot pickup radius.<br>Lv 2: $+35$ stud radius.<br>Lv 3: **Full-Room Instant Loot Magnet** (all Dust, Gold, and XP orbs fly to you immediately). | **Full-Room Auto-Loot + $+10\%$ Gold Find** |
| `AS_T1_04` | **Headstart Blessing** | 3 | $2, 3, 4$ (Total: 9) | Lv 1: Spawn an Upgrade Orb in Room 1 (Common+).<br>Lv 2: Room 1 Orb is guaranteed **Rare+**.<br>Lv 3: Room 1 Orb is guaranteed **Epic+**. | **Start every run in Room 1 with a free Epic+ Upgrade Orb!** |
| `AS_T1_05` | **Dimensional Pocket** | 4 | $1, 2, 2, 3$ (Total: 8) | Automatically routes $15\%$ of earned *Rift Dust* per level into your Rebirth-Safe `ProtectedDustVault` at the end of every run. | **Safely banks $60\%$ of earned Rift Dust across Free Rebirths** |

#### Tier 2: Rift Weaver (Unlocks at Rebirth III — Lv. 100)
| Node ID | Upgrade Name | Max Level | Spark Cost per Level | Effect per Level | Max Level Total Effect |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `AS_T2_01` | **Skywalker's Grace** | 3 | $2, 3, 4$ (Total: 9) | Lv 1: $+10\%$ Base Move Speed & Jump Height.<br>Lv 2: **+1 Max Dash Charge** (Flash Jump).<br>Lv 3: **Unlock Triple Jump** + Dash cooldown reduced by $20\%$. | **Triple Jump + Extra Dash Charge + $+10\%$ Move Speed** |
| `AS_T2_02` | **Fate Manipulation** | 3 | $2, 2, 3$ (Total: 7) | Grants **+1 Free Upgrade Reroll** and **+1 Free Banish Charge** per run per level. | **+3 Free Rerolls & +3 Banishes every run** |
| `AS_T2_03` | **Anchor Guardian** | 4 | $2, 2, 3, 3$ (Total: 10) | Reduces Unsecured Loot lost on defeat by $10\%$ per level and heals $+25\%$ Max HP at every Rift Anchor. | **$-40\%$ Unsecured Loot Loss & Full Heal at Anchors** |
| `AS_T2_04` | **Boss Hunter's Trophy** | 5 | $2, 2, 3, 4, 5$ (Total: 16) | $+20\%$ chance per level for Stage 5/10/15 Bosses to drop **+1 Extra Boss Core** and **+1 Extra Relic Shard**. | **Guaranteed $+100\%$ Extra Boss Core & Relic Shard from every Boss!** |

#### Tier 3: Sovereign of the Rift (Unlocks at Rebirth V — Lv. 165)
| Node ID | Upgrade Name | Max Level | Spark Cost per Level | Effect per Level | Max Level Total Effect |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `AS_T3_01` | **Elemental Crit Overload** | 3 | $3, 4, 5$ (Total: 12) | Allows all Status Effects (*Burn, Bleed, Shock, Toxin, Shatter*) to **Critically Hit** for $33\% / 66\% / 100\%$ of your Critical Damage multiplier. | **All Status DoTs & Procs Critically Hit for $100\%$ Crit Damage!** |
| `AS_T3_02` | **Relic Resonance** | 5 | $2, 3, 3, 4, 5$ (Total: 17) | Increases all equipped and in-run Relic passive effects by $+10\%$ per level, and increases Star-Force base success rates by $+3\%$ per level. | **$+50\%$ Relic Effectiveness & $+15\%$ Star-Force Luck** |
| `AS_T3_03` | **Twin Relic Vessel** | 1 | $10$ (Capstone) | Unlocks a **2nd Permanent Starting Relic Slot** in Town, allowing you to bring 2 Vault Relics into Room 1! | **+1 Permanent Starting Relic Slot** |
| `AS_T3_04` | **Legion Commander** | 2 | $5, 7$ (Total: 12) | Unlocks **+1 Active Hunter Legion Link Skill Slot** per level. | **+2 Active Link Skill Slots** |

#### Tier 4: Transcendent (Unlocks at Rebirth X — Lv. 400 + Infinite Endgame Sinks)
| Node ID | Upgrade Name | Max Level | Spark Cost per Level | Effect per Level | Max Level Total Effect |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `AS_T4_01` | **Limit Breaker (Multi-Strike)** | 3 | $8, 10, 12$ (Total: 30) | Every attack and ability hits **+1 Additional Time (Shadow Line)** for $15\%$ of hit damage per level. | **All attacks deal +3 Extra Hit Lines ($+45\%$ total multiplicative damage)** |
| `AS_T4_02` | **Miracle Evolution** | 1 | $15$ (Capstone) | Every Upgrade Orb has a $15\%$ chance to be a **Double Orb**, letting you pick **2 Upgrades instead of 1**! | **$15\%$ Double-Upgrade Proc Chance** |
| `AS_INF_01` | **Infinite Spark: Omnipotence** | $\infty$ (999) | $3$ Sparks per Level | $+5\%$ Additive Bonus to Ascension Damage Multiplier ($M_{\text{SparkDmg}}$) per level. | Endless damage scaling for Rebirth XI+ whales and grinders. |
| `AS_INF_02` | **Infinite Spark: Prosperity** | $\infty$ (999) | $3$ Sparks per Level | $+5\%$ Additive Bonus to *Rift Dust* & *Hunter XP* per level. | Endless economy scaling for Rebirth XI+ players. |

---

## 24. Mathematical Formulas & Balance Engine (Claude Code Specification)

### 24.1 Hunter Level XP Curve & Rebirth Progression Math
$$\text{XP}_{\text{Req}}(L) = \text{round}\left( 80 \times L^{1.65} + 40 \times L \right)$$
$$L_{\text{Req}}(R) = 400 + 75 \times (R - 10) \quad (\text{for } R > 10)$$
$$\Delta L_{\text{Legacy}}(R, L_{\text{cur}}) = \text{round}\left( 0.50 \times \text{clamp}\left( L_{\text{cur}}, \; L_{\text{Req}}(R), \; 1.25 \times L_{\text{Req}}(R) \right) \right)$$
$$p = \min\left( 0.90, \; \frac{L_{\text{cur}} - 1}{L_{\text{Req}}(R) - 1} \right)$$
$$\text{XP}_{\text{Gain}} = \text{BaseMobXP} \times M_{\text{World}} \times M_{\text{CorrEco}}(C) \times M_{\text{Depth}}(d) \times M_{\text{RebEco}}(R) \times M_{\text{SparkEco}} \times M_{\text{PassXP}} \times M_{\text{Party}}(P)$$

### 24.2 Player Combat Damage & Survivability Formulas
$$\text{FinalDamage} = \text{BaseAtk} \times M_{\text{Skill}} \times M_{\text{Rebirth}} \times M_{\text{Ascension}} \times M_{\text{Account}} \times M_{\text{RunBuild}} \times M_{\text{Target}} \times M_{\text{Crit}} \times \text{Variance}$$
$$\text{MaxHP} = 250 \times \left( 1 + 0.015 \times (L_{\text{Hunter}} - 1) + 0.0075 \times L_{\text{Legacy}} \right) \times M_{\text{Rebirth}} \times M_{\text{Ascension}} \times M_{\text{RunHP}} \times M_{\text{CurseHP}}$$

### 24.3 Monster HP & Attack Scaling Formula
$$\text{EnemyHP}(w, C, d, P) = \text{BaseEnemyHP} \times M_{\text{WorldHP}}(w) \times M_{\text{CorrHP}}(C) \times M_{\text{DepthHP}}(d) \times \text{PartyHPScale}(P)$$
$$\text{EnemyRawAtk}(w, C, d) = \text{BaseEnemyAtk} \times M_{\text{WorldAtk}}(w) \times (1 + 0.12 \times C) \times 1.04^C \times 1.07^{(d - 1)}$$

### 24.4 Economy, Rift Dust & Unsecured Extraction Math
$$\text{RoomDust}(w, C, d) = \text{BaseRoomDust}(d) \times M_{\text{World}}(w) \times M_{\text{CorrEco}}(C) \times M_{\text{Depth}}(d) \times M_{\text{RebEco}}(R) \times M_{\text{SparkEco}} \times M_{\text{LinkDust}} \times M_{\text{PassDust}}$$
$$L_{\text{final}}(d) = L_{\text{base}}(d) \times \left( 1 - 0.10 \times \text{Lv}(\text{AnchorGuardian}) \right) \times \begin{cases} 0.50 & \text{if HasInsurancePass} \\ 1.00 & \text{otherwise} \end{cases}$$
$$\text{DustKeptFromPouch} = \text{round}\left( D_{\text{unsec}} \times (1 - L_{\text{final}}(d)) \right)$$

### 24.5 Production-Ready Luau Module (`ReplicatedStorage.Shared.FormulaEngine`)

```luau
--!strict
-- ReplicatedStorage/Shared/FormulaEngine.luau
-- Audited v2.6 Single Source of Truth for Rift Rush XP, Rebirth, Damage, Co-op Sync & Economy Math

local FormulaEngine = {}

FormulaEngine.REBIRTH_TABLE = {
	[0]  = { ReqLevel = 1,   DmgMult = 1.00, EcoMult = 1.00, Sparks = 0  },
	[1]  = { ReqLevel = 50,  DmgMult = 1.30, EcoMult = 1.25, Sparks = 2  },
	[2]  = { ReqLevel = 75,  DmgMult = 1.65, EcoMult = 1.55, Sparks = 3  },
	[3]  = { ReqLevel = 100, DmgMult = 2.10, EcoMult = 1.90, Sparks = 4  },
	[4]  = { ReqLevel = 130, DmgMult = 2.65, EcoMult = 2.35, Sparks = 5  },
	[5]  = { ReqLevel = 165, DmgMult = 3.35, EcoMult = 2.90, Sparks = 6  },
	[6]  = { ReqLevel = 200, DmgMult = 4.20, EcoMult = 3.55, Sparks = 7  },
	[7]  = { ReqLevel = 240, DmgMult = 5.25, EcoMult = 4.30, Sparks = 8  },
	[8]  = { ReqLevel = 285, DmgMult = 6.50, EcoMult = 5.20, Sparks = 9  },
	[9]  = { ReqLevel = 335, DmgMult = 8.00, EcoMult = 6.25, Sparks = 10 },
	[10] = { ReqLevel = 400, DmgMult = 10.0, EcoMult = 7.50, Sparks = 12 },
}

FormulaEngine.WORLD_ECO_MULT = { 1.0, 1.8, 3.2, 5.5, 9.5, 16.0, 27.0, 45.0 }
FormulaEngine.WORLD_HP_MULT  = { 1.0, 2.2, 4.5, 9.0, 18.0, 35.0, 68.0, 130.0 }
FormulaEngine.WORLD_ATK_MULT = { 1.0, 1.6, 2.5, 3.8, 5.8, 8.8,  13.5, 20.0 }

export type RebirthInfo = {
	ReqLevel: number,
	DmgMult: number,
	EcoMult: number,
	Sparks: number,
}

function FormulaEngine.GetRebirthInfo(rebirthTier: number): RebirthInfo
	if rebirthTier <= 10 then
		return FormulaEngine.REBIRTH_TABLE[math.max(0, rebirthTier)]
	end
	local extra = rebirthTier - 10
	return {
		ReqLevel = 400 + 75 * extra,
		DmgMult  = 10.0 + 2.0 * extra,
		EcoMult  = 7.50 + 1.25 * extra,
		Sparks   = 12,
	}
end

function FormulaEngine.GetHunterXPRequired(level: number): number
	local clamped = math.max(1, level)
	return math.round(80 * (clamped ^ 1.65) + 40 * clamped)
end

function FormulaEngine.CalculateLegacyLevelsGained(nextRebirthTier: number, currentHunterLevel: number): number
	local reqLevel = FormulaEngine.GetRebirthInfo(nextRebirthTier).ReqLevel
	local effectiveLevel = math.clamp(currentHunterLevel, reqLevel, math.round(reqLevel * 1.25))
	return math.round(0.50 * effectiveLevel)
end

function FormulaEngine.GetInstantRebirthSkipQuote(nextRebirthTier: number, currentHunterLevel: number): (string, number, number)
	local nextInfo = FormulaEngine.GetRebirthInfo(nextRebirthTier)
	local reqLevel = nextInfo.ReqLevel
	local progress = math.clamp((currentHunterLevel - 1) / math.max(1, reqLevel - 1), 0, 0.90)

	if progress >= 0.80 then
		return "SKIP_TIER_1_49R", 49, progress
	elseif progress >= 0.60 then
		return "SKIP_TIER_2_99R", 99, progress
	elseif progress >= 0.40 then
		return "SKIP_TIER_3_179R", 179, progress
	elseif progress >= 0.20 then
		return "SKIP_TIER_4_279R", 279, progress
	else
		return "SKIP_TIER_5_399R", 399, progress
	end
end

export type DamageParams = {
	WeaponBaseDmg: number,
	HunterLevel: number,
	LegacyBonusLevels: number,
	WeaponMasteryLevel: number,
	WeaponParagonRank: number,
	SkillMultiplier: number,
	RebirthTier: number,
	IsPureRun: boolean,
	AscendantMightLv: number,
	InfOmnipotenceLv: number,
	LinkSkillDmgBonus: number,
	RelicDmgBonus: number,
	RelicResonanceLv: number,
	RunAdditiveBonus: number,
	ComboCount: number,
	CurseDmgMultiplier: number,
	TargetBonus: number,
	CritRate: number,
	CritDamageMult: number,
	LimitBreakerLv: number,
	PartyHostBaselinePower: number?,
}

function FormulaEngine.CalculateHitDamage(p: DamageParams, rng: Random?): (number, boolean, {number})
	local randomGen = rng or Random.new()

	local levelFactor = 1 + 0.015 * math.max(0, p.HunterLevel - 1) + 0.0075 * p.LegacyBonusLevels
	local masteryFactor = 1 + 0.02 * p.WeaponMasteryLevel + 0.005 * p.WeaponParagonRank
	local baseAtk = p.WeaponBaseDmg * levelFactor * masteryFactor

	local rebInfo = FormulaEngine.GetRebirthInfo(p.RebirthTier)
	local rebMult = if p.IsPureRun then 1.0 else rebInfo.DmgMult
	local ascensionMult = if p.IsPureRun then 1.0 else (1 + 0.08 * p.AscendantMightLv + 0.05 * p.InfOmnipotenceLv)

	local rawCorePower = baseAtk * rebMult * ascensionMult
	if not p.IsPureRun and p.PartyHostBaselinePower and rawCorePower < (0.70 * p.PartyHostBaselinePower) then
		rawCorePower = 0.70 * p.PartyHostBaselinePower
	end

	local relicBoosted = p.RelicDmgBonus * (1 + 0.10 * p.RelicResonanceLv)
	local accountMult = 1 + p.LinkSkillDmgBonus + relicBoosted

	local comboBonus = math.min(0.50, math.floor(p.ComboCount / 10) * 0.01)
	local runBuildMult = (1 + p.RunAdditiveBonus + comboBonus) * math.max(0.1, p.CurseDmgMultiplier)
	local targetMult = 1 + p.TargetBonus

	local isCrit = randomGen:NextNumber() <= math.clamp(p.CritRate, 0, 1.0)
	local critMult = if isCrit then math.max(1.5, p.CritDamageMult) else 1.0
	local variance = randomGen:NextNumber(0.95, 1.05)

	local primaryDamage = math.max(1, math.round(
		rawCorePower * p.SkillMultiplier * accountMult * runBuildMult * targetMult * critMult * variance
	))

	local shadowLines = {}
	if not p.IsPureRun and p.LimitBreakerLv > 0 then
		for i = 1, math.clamp(p.LimitBreakerLv, 1, 3) do
			table.insert(shadowLines, math.max(1, math.round(primaryDamage * 0.15)))
		end
	end

	return primaryDamage, isCrit, shadowLines
end

function FormulaEngine.GetMonsterMaxHP(baseHP: number, worldIndex: number, corruptionTier: number, roomNumber: number, partySize: number): number
	local wMult = FormulaEngine.WORLD_HP_MULT[math.clamp(worldIndex, 1, #FormulaEngine.WORLD_HP_MULT)] or 1.0
	local c = math.max(0, corruptionTier)
	local corrMult = (1 + 0.18 * c) * (1.055 ^ c)

	local d = math.max(1, roomNumber)
	local depthMult = 1.0
	if d <= 10 then
		depthMult = 1.11 ^ (d - 1)
	elseif d <= 20 then
		depthMult = (1.11 ^ 9) * (1.16 ^ (d - 10))
	else
		depthMult = (1.11 ^ 9) * (1.16 ^ 10) * (1.22 ^ (d - 20))
	end

	local p = math.clamp(partySize, 1, 4)
	local partyMult = 1 + 0.55 * (p - 1)

	return math.max(1, math.round(baseHP * wMult * corrMult * depthMult * partyMult))
end

function FormulaEngine.CalculateDefeatDustKept(unsecuredDust: number, roomNumber: number, anchorGuardianLv: number, hasInsurancePass: boolean): number
	local baseLoss = 0.30
	if roomNumber >= 11 then
		baseLoss = 0.75
	elseif roomNumber >= 6 then
		baseLoss = 0.50
	end

	local sparkReduction = 1 - (0.10 * math.clamp(anchorGuardianLv, 0, 4))
	local passFactor = if hasInsurancePass then 0.50 else 1.00
	local finalLoss = math.clamp(baseLoss * sparkReduction * passFactor, 0.05, 0.95)

	return math.round(unsecuredDust * (1 - finalLoss))
end

return FormulaEngine
```

---

## 25. Weapon Mastery, Hunter Legion & Infinite Paragon Ranks

* **Standard Weapon Mastery (Levels 1–20):** Grants alternate combos, starting abilities, and Account-Wide **Hunter Link Skills** at Levels 10 and 20.
* **The Hunter Legion (Link Skills):** Start with 3 Link Slots (expandable to 8) to combine passives across weapons.
* **Infinite Paragon Mastery (Levels 21–999+):** Grants $+0.5\%$ Weapon Base Damage and $+0.5\%$ *Rift Dust* Find per rank, plus togglable **Floating Weapon Auras** at Paragon 50, 100, 250, and 500.

---

## 26. Quests, Bounties & Economy Currencies

1. **Rift Dust (Purple Crystal — Primary Grind Currency)**
2. **Boss Cores (Golden Orb — Boss Milestone Currency)**
3. **Relic Shards (Blue Fragment — Collection Currency)**
4. **Rebirth Sparks (Crimson Star — Prestige Currency)**
5. **Anchor Tokens (Teal Hourglass — Earned Recovery Currency)**

---

## 27. Complete Robux Monetization Suite

### 27.1 Repeatable Developer Products
* **Instant Rebirth (Skip Level):** 49 / 99 / 179 / 279 / 399 R$ (5 Dynamic Progress Tiers)
* **Keep Everything Seal (Single Rebirth):** 99 R$
* **Rift Revive:** 39 R$
* **Checkpoint Rewind:** 49 R$
* **Insure & Extract:** 29 R$
* **Supercharged Run Token:** 79 R$
* **Server Rift Surge (Atmospheric Buff):** 99 R$
* **Upgrade Reroll Pack (5x):** 25 R$
* **Star-Force Safeguard Pack:** 49 R$

### 27.2 Permanent Gamepasses
* **Permanent Keep-On-Rebirth (True Ascendant):** 599 R$
* **2x Hunter XP (Fast Rebirth Pass):** 399 R$
* **2x Rift Dust Collector:** 449 R$
* **4th Upgrade Choice (VIP Architect):** 299 R$
* **The Banish Pass:** 199 R$
* **Starting Relic Vault Key:** 399 R$
* **Extra Link Skill Slots (+2 Slots):** 249 R$
* **Permanent Vault Insurance:** 299 R$

---

## 28. Technical Architecture for Roblox & Claude Code Implementation Guide

### 28.1 Recommended Folder Hierarchy

```text
src/
├── ReplicatedStorage/
│   ├── Shared/
│   │   ├── FormulaEngine.luau          -- Audited v2.6 mathematical engine (Section 24.5)
│   │   ├── AssetRegistry.luau          -- Central lookup table for all Models, Icons & Sounds (Section 31.6)
│   │   ├── ModelNormalizer.luau        -- Sanitizes, welds & scales free Toolbox models (Section 31.7)
│   │   ├── RoomAsciiTemplates.luau     -- 2.5D ASCII Grid layouts for procedural room generation (Section 31.1)
│   │   ├── AscensionShopConfig.luau    -- All 18 Ascension Shop nodes & costs (Section 23)
│   │   ├── WeaponConfig.luau           -- All 8 weapons, base stats & Link Skills
│   │   ├── UpgradePoolConfig.luau      -- Run upgrades, rarities & tags
│   │   ├── RelicConfig.luau            -- Relics & 1-to-5 Star-Force tables
│   │   └── EnemyConfig.luau            -- Enemy base HP/Atk & behavior archetypes
│   └── Remotes/                        -- Typed RemoteEvents & RemoteFunctions
├── ServerScriptService/
│   ├── Services/
│   │   ├── PlayerDataService.luau      -- ProfileStore / DataStore wrapper (Section 28.2)
│   │   ├── RebirthService.luau         -- Handles Standard, Keep-Everything & Instant Skip Rebirths
│   │   ├── AscensionShopService.luau   -- Handles Rebirth Spark purchases & respecs
│   │   ├── RoomBuilderService.luau     -- Reads RoomAsciiTemplates & spawns 2.5D rooms (Section 31.1)
│   │   ├── RunManagerService.luau      -- Room spawning, Rift Anchors, Extraction & Defeat logic
│   │   ├── CombatService.luau          -- Server-authoritative hit validation & status procs
│   │   └── MonetizationService.luau    -- MarketplaceService ProcessReceipt & Gamepass checks
└── StarterPlayer/
    └── StarterPlayerScripts/
        ├── Controllers/
        │   ├── Camera25DController.luau      -- 2.5D side-scrolling spring camera
        │   ├── Movement25DController.luau    -- Z=0 PlaneLock, Double/Triple jump, platform drop & Flash Jump
        │   ├── CombatVFXController.luau      -- Pooled cascading damage numbers & teammate VFX throttle
        │   ├── ProceduralAnimController.luau -- Sine-wave squash/stretch monster animations (Section 31.2)
        │   └── UIController.luau             -- HUD, Upgrade Modal, Rift Anchor & Rebirth Pedestal UI
```

### 28.2 Persistent Player Profile Schema (`PlayerProfileData`)
```luau
--!strict
export type PlayerProfileData = {
	HunterLevel: number,
	HunterXP: number,
	RebirthTier: number,
	LegacyBonusLevels: number,
	RebirthSparksAvailable: number,
	RebirthSparksTotalEarned: number,
	RunsSinceLastRebirth: number,

	RiftDust: number,
	ProtectedDustVault: number,
	BossCores: number,
	RelicShards: number,
	AnchorTokens: number,

	EquippedWeapon: string,
	UnlockedWeapons: { [string]: boolean },
	WeaponMastery: { [string]: { Level: number, XP: number, ParagonRank: number } },
	ActiveLinkSkills: { string },
	UnlockedWorlds: { [number]: number }, -- [WorldIndex] = HighestCorruptionTierUnlocked
	AscensionNodes: { [string]: number }, -- [NodeId] = Level
	RelicStars: { [string]: { Stars: number, PityCount: number } },
	EquippedStartingRelics: { string },
}
```

### 28.3 Mobile & 4-Player Co-op Performance Rules (`CombatVFXController`)
* **Object-Pooled Cascading Damage Batcher:** Pre-allocate 60 `BillboardGui` damage labels at startup. When an attack with `LimitBreaker` hits a monster, render the primary damage line and up to 3 shadow lines inside a single stacked `BillboardGui` container that cascades upward over $0.55\text{s}$ and returns to the pool.
* **Teammate VFX Opacity Throttling:** Render the local player's skill particles at $100\%$ opacity, and automatically scale other party members' particle emission rates and transparency to $25\%$ opacity so boss telegraphs remain $100\%$ readable on mobile.

---

## 29. Step-by-Step Build Roadmap (With Model & `/clear` Checkpoints for Claude Pro)

> **INSTRUCTION FOR CLAUDE CODE:** Execute ONLY the step requested by the user. When finished with that step, print the **Checkpoint Box** from Section 0.2 so the user can run `/clear` and switch models if needed.

| Build Step | Files to Create in This Step | Recommended Model | Extended Thinking | Why This Model & Setting? |
| :--- | :--- | :--- | :--- | :--- |
| **Step 1: Core Math, Configs & Data Layer** | `FormulaEngine.luau`, `AssetRegistry.luau`, `ModelNormalizer.luau`, `AscensionShopConfig.luau`, `WeaponConfig.luau`, `PlayerDataService.luau`, `Remotes` init | **`/model sonnet`** | **OFF** | Formulas and schemas are already 100% written in this spec. Sonnet writes these fast at 1/5th the quota cost of Opus. |
| **Step 2: 2.5D Camera, Physics Lock & Movement** | `Camera25DController.luau`, `Movement25DController.luau` ($Z=0$ plane lock, Double/Triple Jump, `S+Space` one-way platform drop, Flash Jump) | **`/model opus`** *(Switch back to `sonnet` after!)* | **ON** | 2.5D raycast platform drop-throughs and $Z=0$ plane constraints benefit from Opus's spatial physics reasoning. |
| **Step 3: 2.5D ASCII Room Builder & Run Loop** | `RoomAsciiTemplates.luau` (10 rooms), `RoomBuilderService.luau`, `RunManagerService.luau` (Spawning, Rift Anchor Room 5/10, Extraction, Defeat math) | **`/model sonnet`** | **OFF** | Sonnet excels at parsing 2D ASCII grids and state machines. Run `/clear` after completing Step 3! |
| **Step 4: Combat, 3 Weapons, 10 Upgrades & Bosses** | `UpgradePoolConfig.luau`, `EnemyConfig.luau`, `CombatService.luau`, `ProceduralAnimController.luau`, `CombatVFXController.luau` | **`/model sonnet`** | **ON** | Turning Thinking ON with Sonnet gives clean server hit-validation and object-pooled cascading damage numbers without Opus token burn. |
| **Step 5: Town Hub, Rebirth Pedestal & Monetization** | `RebirthService.luau`, `AscensionShopService.luau`, `MonetizationService.luau`, Town Hub generator in `RoomBuilderService.luau` | **`/model sonnet`** | **OFF** | Straightforward server transaction logic using `FormulaEngine`. Run `/clear` after completing Step 5! |
| **Step 6: Full Responsive UI & Polish Audit** | `UIController.luau` (HUD, 3/4-Card Upgrade Modal, Rift Anchor Modal, Defeat Screen, Rebirth & Ascension Shop UI) + Final Security Audit | **`/model sonnet`** for UI *(Optional `/model opus` for final audit)* | **OFF** (ON for audit) | Sonnet generates clean `ScreenGui` layouts rapidly. Use Opus only if doing a final cross-project bug check. |

---

## 30. Post-Audit Review, Future Improvements & Expansion Roadmap

1. **MapleStory-Style "Damage Skins" & Custom Hit-Effects**
2. **Familiar / Spirit Companion System (With Auto-Buff & Loot Fetch)**
3. **AFK "Rift Training Grounds" (Dojo Dummy Chamber for Roblox Premium Payouts)**
4. **Weekly 8-Player "Dimensional Raid Boss" (Zakum / Horntail Inspired)**
5. **Weapon "Cube / Potential" Awakening Lines (Endgame Rift Dust Sink)**
6. **Guild "Rift Citadels" & Weekly Guild Conquest**
7. **"Mirror Rift" Daily Challenge Seed (Equalized Skill Competition)**

---

## 31. Visual Asset, 3D Modeling, Level Design & Texture Pipeline for Claude Code

Because AI coding agents (like Claude Code) excel at writing code and math but **cannot natively sculpt 3D meshes in Blender or paint 2D textures**, you must use a **Decoupled Asset & Procedural Greybox Pipeline**. This ensures Claude Code builds a $100\%$ playable, visually clean game immediately, and lets you swap in high-quality 3D models and icons in minutes without rewriting any code.

### 31.1 How Claude Code Will Design 2.5D Levels: The "ASCII Tilemap Room Builder"
Because Rift Rush is a **2.5D side-scroller**, level design is actually a **2D grid along the $(X, Y)$ plane**! Instead of asking Claude Code to guess random 3D coordinates, instruct Claude Code to build a **`RoomBuilderService`** that reads **2D ASCII Strings** (`16 columns wide x 9 rows tall`, where each tile is `8x6x10` studs) and automatically places themed tiles, one-way platforms, ladders, jump pads, and monster spawners:

```luau
-- Example inside ReplicatedStorage/Shared/RoomAsciiTemplates.luau
-- '#' = Solid Ground Block (Grass topped)
-- '=' = One-Way Drop-Through Platform (Wood/Vine bridge)
-- '^' = Bouncy Mushroom Jump Pad (Launches player +55 Y velocity)
-- 'S' = Player Spawn Left   | 'E' = Portal Exit Right
-- 'M' = Normal Mob Spawner  | 'B' = Boss Spawner | 'C' = Chest Spawner

RoomAsciiTemplates.MushroomWilds_Room01 = {
	"################",
	"#..............#",
	"#..===....===..#",
	"#...M......M...#",
	"#......==......#",
	"#..==..M...==..#",
	"#S.^...M....^.E#",
	"################",
}
```

### 31.2 How to Handle Monsters & Bosses (Without Custom Rigging Headaches)
1. **Humanoid NPCs for Humanoid Enemies/Bosses (Zero Rigging Needed):** Use standard **Roblox R15 NPC Rigs** dressed up using free **Roblox Catalog Avatar Accessories / Meshes** and scaled up ($1.5\times$ for Elites, $2.5\times$ for Bosses).
2. **Code-Driven "Squash-and-Stretch" Procedural Animation for Cute Monsters (*MapleStory* Style):** Write a **`ProceduralAnimController`** using `TweenService` and sine-wave `CFrame` math on any static monster model:
   * **Idle:** Gentle vertical breathing scale ($\pm 6\%$ Y-scale sine wave).
   * **Hop/Move:** Squash down ($X \times 1.15, Y \times 0.80$) before jumping, stretch in mid-air ($X \times 0.85, Y \times 1.25$), and squash on landing!
   * **Hit Flash:** Briefly set `Highlight.FillTransparency = 0.2` (White/Red flash) and tilt backward $15^\circ$ for $0.08\text{s}$ when struck.

### 31.3 How to Handle Weapons, Items & Currencies (Procedural Neon Fallbacks + `AssetRegistry`)
Every currency, relic, weapon, and monster references an entry in `AssetRegistry.luau`:
* **Phase 1 (Claude Code Auto-Generated Procedural Prefabs):** If a custom `MeshId` or model is not yet placed in `ReplicatedStorage.Assets`, `AssetRegistry` automatically builds a clean **Stylized Geometric Prefab** out of Roblox `Parts`, `PointLights`, `ParticleEmitters`, and `UIGradient`.
* **Phase 2 (5-Minute Drag-and-Drop Asset Swap):** Drop any free model from the Roblox Toolbox, KayKit, or Quaternius into `ReplicatedStorage.Assets`, and `ModelNormalizer.luau` (Section 31.7) will automatically strip any malicious scripts, scale it to the exact hitbox size, and weld it cleanly!

### 31.4 How to Make Textures, Materials & UI Look Amazing Automatically
1. **Use Built-In Roblox `MaterialVariant` & Stylized Lighting:** Set `Lighting.Technology = Enum.Technology.Future`, add a warm `Atmosphere`, `BloomEffect`, and `ColorCorrectionEffect` ($+0.15$ Saturation, $+0.05$ Contrast), and use `SmoothPlastic` + `Neon` accents.
2. **Programmatic UI Polish (`UIGradient` + `UIStroke` + Spring Tweens):** Apply `UICorner` (`8px–12px`), a `2px` dark `UIStroke`, a top-to-bottom `UIGradient` on every button/card, and a hover scale tween (`1.0 -> 1.06`).
3. **2D Icons for Currencies, Upgrades & Relics:** Use crisp **Unicode Emoji / RichText Badges** paired with rarity-colored radial `UIGradient` backgrounds for the initial build, with optional `rbxassetid://` overrides in `AssetRegistry.luau`.

### 31.5 Best Free & Fast Asset Sources You Can Use Right Away

| Asset Category | Best Free / Low-Effort Sources | How to Plug Into Claude Code's Project |
| :--- | :--- | :--- |
| **3D Weapons (Swords, Staves, Bows, Hammers)** | **KayKit Dungeon / Adventurer Packs** (itch.io, CC0 Free), **Quaternius Ultimate RPG Pack** (CC0 Free), or **Roblox Creator Store** (search *"Synty"* or *"Low Poly RPG Weapon Pack"*). | Drop the model into `ReplicatedStorage.Assets.Weapons` and name it `"Greatsword"`, `"Staff"`, etc. |
| **3D Monsters (Mushrooms, Golems, Slimes, Ghosts)** | **Quaternius Cute Animated Monsters Pack** (CC0 Free) or **Roblox Creator Store** low-poly monster packs, or **Roblox Cube 3D** (built-in Studio mesh generator). | Drop the model into `ReplicatedStorage.Assets.Enemies`. `ModelNormalizer` + `ProceduralAnimController` will size, weld, and animate it automatically! |
| **2.5D Environment Props (Trees, Mushrooms, Platforms, Crystals)** | **Roblox Built-in Endorsed Nature/Forest Packs** (created by Roblox internally, $100\%$ free and virus-free in the Creator Store). | Place trees/rocks in the background layer ($Z = -12$ to $Z = -35$) behind the $Z = 0$ combat track for instant 2.5D depth! |
| **2D UI Icons (Skills, Relics, Currencies)** | **Game-Icons.net** (4,000+ free RPG icons) or **Kenney Game Assets** (CC0). | Paste `rbxassetid://` strings into `AssetRegistry.Icons`. |
| **Sound Effects & Hit Sounds** | **Roblox Creator Store Audio Library** (100,000+ free official Pro Sound Effects & APM Music tracks built right into Studio). | Reference standard Roblox sound IDs in `AssetRegistry.Sounds`. |

### 31.6 Copy-Paste `AssetRegistry.luau` Template for Claude Code

```luau
--!strict
-- ReplicatedStorage/Shared/AssetRegistry.luau
-- Central lookup table for all 3D Prefabs, 2D Icons, Colors, and Audio.
-- If a custom 3D model is not found in ReplicatedStorage.Assets, builds a stylized Neon/SmoothPlastic procedural fallback!

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ModelNormalizer = require(script.Parent.ModelNormalizer)

local AssetRegistry = {}

AssetRegistry.RarityStyles = {
	Common    = { Color = Color3.fromRGB(180, 190, 205), Glow = Color3.fromRGB(120, 130, 145) },
	Rare      = { Color = Color3.fromRGB(65, 155, 255),  Glow = Color3.fromRGB(30, 100, 220)  },
	Epic      = { Color = Color3.fromRGB(185, 85, 255),  Glow = Color3.fromRGB(130, 40, 210)  },
	Legendary = { Color = Color3.fromRGB(255, 195, 45),  Glow = Color3.fromRGB(255, 140, 0)   },
	Corrupted = { Color = Color3.fromRGB(255, 55, 95),   Glow = Color3.fromRGB(180, 10, 40)   },
}

AssetRegistry.Currencies = {
	RiftDust     = { Name = "Rift Dust",     FallbackIcon = "🔮", ImageId = "", Color = Color3.fromRGB(190, 95, 255),  Shape = Enum.PartType.Block    },
	BossCores    = { Name = "Boss Core",     FallbackIcon = "☀️", ImageId = "", Color = Color3.fromRGB(255, 200, 50),  Shape = Enum.PartType.Ball     },
	RelicShards  = { Name = "Relic Shard",   FallbackIcon = "💎", ImageId = "", Color = Color3.fromRGB(70, 200, 255),  Shape = Enum.PartType.Cylinder },
	RebirthSpark = { Name = "Rebirth Spark", FallbackIcon = "✨", ImageId = "", Color = Color3.fromRGB(255, 75, 110),  Shape = Enum.PartType.Ball     },
	AnchorToken  = { Name = "Anchor Token",  FallbackIcon = "⏳", ImageId = "", Color = Color3.fromRGB(60, 240, 200),  Shape = Enum.PartType.Cylinder },
}

-- Spawns either a custom model from ReplicatedStorage.Assets.Drops OR a clean stylized Neon drop orb
function AssetRegistry.CreateCurrencyDropModel(currencyKey: string): Model
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if assetsFolder and assetsFolder:FindFirstChild("Drops") then
		local customPrefab = assetsFolder.Drops:FindFirstChild(currencyKey)
		if customPrefab and customPrefab:IsA("Model") then
			return ModelNormalizer.SanitizeAndNormalize(customPrefab:Clone(), Vector3.new(1.5, 1.5, 1.5))
		end
	end

	-- Procedural Stylized Fallback (looks great out-of-the-box!)
	local info = AssetRegistry.Currencies[currencyKey] or AssetRegistry.Currencies.RiftDust
	local model = Instance.new("Model")
	model.Name = currencyKey .. "_Drop"

	local core = Instance.new("Part")
	core.Name = "PrimaryPart"
	core.Shape = info.Shape
	core.Size = Vector3.new(1.4, 1.4, 1.4)
	core.Color = info.Color
	core.Material = Enum.Material.Neon
	core.Anchored = true
	core.CanCollide = false
	core.Parent = model

	local light = Instance.new("PointLight")
	light.Color = info.Color
	light.Range = 8
	light.Brightness = 1.5
	light.Parent = core

	model.PrimaryPart = core
	return model
end

return AssetRegistry
```

### 31.7 Copy-Paste `ModelNormalizer.luau` Utility (Auto-Sanitizes & Welds Free Online Models)

```luau
--!strict
-- ReplicatedStorage/Shared/ModelNormalizer.luau
-- Automatically strips malicious/broken scripts from free Toolbox models, scales them to targetSize,
-- creates a clean PrimaryPart hitbox, and welds all parts together for 2.5D combat!

local ModelNormalizer = {}

function ModelNormalizer.SanitizeAndNormalize(rawModel: Model, targetSize: Vector3): Model
	-- 1. Strip any hidden scripts, ClickDetectors, or TouchTransmitters from free online models
	for _, desc in rawModel:GetDescendants() do
		if desc:IsA("LuaSourceContainer") or desc:IsA("ClickDetector") or desc:IsA("Fire") or desc:IsA("Smoke") then
			desc:Destroy()
		end
	end

	-- 2. Scale model proportionally to fit targetSize height
	local _, currentSize = rawModel:GetBoundingBox()
	if currentSize.Y > 0.05 then
		local scaleFactor = targetSize.Y / currentSize.Y
		rawModel:ScaleTo(rawModel:GetScale() * scaleFactor)
	end

	-- 3. Create a clean invisible PrimaryPart root at the bounding box center
	local cf, newSize = rawModel:GetBoundingBox()
	local root = Instance.new("Part")
	root.Name = "NormalizedRoot"
	root.Size = newSize
	root.CFrame = cf
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = true
	root.Parent = rawModel

	-- 4. Weld all visual parts to NormalizedRoot and disable internal collisions
	for _, desc in rawModel:GetDescendants() do
		if desc:IsA("BasePart") and desc ~= root then
			desc.Anchored = false
			desc.CanCollide = false
			desc.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = desc
			weld.Parent = root
		end
	end

	rawModel.PrimaryPart = root
	return rawModel
end

return ModelNormalizer
```