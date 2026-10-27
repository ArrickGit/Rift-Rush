# CLAUDE.md — Rift Rush Master Game Design & Implementation Spec (v2.7)

> **Status:** Final Production-Ready Blueprint, Audited Math Engine, Bespoke Procedural Art Upgrade & Claude Pro Workflow Guide (v2.7)
> **Platform:** Roblox (PC, Mobile, Console)
> **Genre:** 2.5D PvE Action Roguelite with Endless Permanent Progression & Rebirths
> **Working Title:** Rift Rush
> **Document Purpose:** Serve as the single source of truth (`CLAUDE.md`) for Claude Code to build and visually overhaul **Rift Rush** end-to-end while respecting the developer's **Claude Pro ($30 SGD/mo)** rate limits through explicit step boundaries, `/model` switching recommendations, and `/clear` checkpoints.

---

## 0. AI Agent Execution Rules & Claude Pro ($30 SGD/mo) Token Management Protocol

> **CRITICAL INSTRUCTIONS FOR CLAUDE CODE — READ BEFORE EVERY ACTION:**

### 0.1 Mandatory Coding, Architecture & Visual Quality Standards
1. **Strict Luau Typing:** Every `.luau` script MUST begin with `--!strict` and use explicit type annotations for function parameters, return types, and data structures.
2. **Server Authority:** Never trust the client for damage calculations, currency payouts, Rebirth eligibility, Ascension Shop purchases, or room completion. Use `ReplicatedStorage.Shared.FormulaEngine` on the server as the single source of truth.
3. **Bespoke Multi-Part Visual Standard (NO "Stock 2-Part Primitives"):**
   * **NEVER** generate lazy 1-to-3 part blocky primitives for weapons, monsters, interactables, or tiles.
   * Every procedural model MUST follow **Section 32 (Bespoke Multi-Part Kitbashing Rules)**: Weapons must have **12–20 sculpted sub-parts** (pommel, grip wraps, crossguard wings, fuller core, beveled edge wedges, rune inlays, aura trails); Monsters must have **14–24 articulated sub-parts** (layered caps/armor, glowing eyes/pupils, spots, fangs, spore vents, ambient emitters); Tiles must have **layered grass overhangs, edge trims, rock strata, and surface foliage**.
   * **NEVER** use plain naked emojis as standalone UI icons—always render icons through `IconRenderer.luau` (Section 32.6) using multi-layered rotated geometric vector frames, gradients, inner strokes, and shine overlays.
4. **2.5D Plane & Collision Discipline:** All player characters and monsters MUST be constrained to the $Z = 0$ combat plane using `AlignPosition` or `PlaneConstraint`, and assigned to the `"ActorsNoCollide"` collision group so players and monsters never push each other along the Z-axis.

### 0.2 Mandatory Token-Saving & Model-Switching Protocol (For $30 SGD Claude Pro Plan)
To prevent the user from hitting the 5-hour rolling token limit on the Claude Pro plan, **Claude Code MUST enforce the following workflow at all times**:

1. **Build Strictly One Step at a Time (Never Monolith-Dump):**
   * Follow the **Build Steps in Section 29 & Visual Overhaul Steps in Section 32.7** one step per session.
   * **NEVER** attempt to write or rewrite all files in a single conversation turn. Complete **ONLY** the files listed in the current Step, verify there are no syntax/type errors, and then **STOP**.
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
   * **Default Model (`/model sonnet` — Use for 90% of work):** Use **Claude Sonnet** for all procedural 3D kitbashing (`ProceduralArtFactory.luau`), multi-stage skill VFX, custom vector UI icons (`IconRenderer.luau`), config tables, and services.
   * **Precision Physics/Audit Model (`/model opus` — Use ONLY for Step 2 & Final Audit):** Only recommend switching to **Claude Opus** when debugging complex 2.5D platform physics/raycasting or multi-script race conditions.

---

## 1. High Concept

**Rift Rush** is a fast-paced 2.5D Roblox PvE action roguelite inspired by classic side-scrolling RPGs like *MapleStory*. Players enter unstable dimensional portals, clear short randomized rooms, assemble visually explosive combat builds, complete platforming "Jump Quest" rooms, defeat multi-phase bosses, and decide whether to extract safely with their loot or push deeper for massive reward multipliers.

While each run resets the player's temporary combat build, collected resources feed into an endless, deeply satisfying grind loop: leveling the player's **Hunter Level** to perform prestigious **Rift Rebirths** (at Levels 50, 75, 100, 130, 165, 200+), spending **Rebirth Sparks** in the **Ascension Shop**, unlocking weapons, building an account-wide **Hunter Legion** (Link Skill bonuses), Star-Forcing permanent Relics, and climbing 100+ **Portal Corruption Tiers**. Players can spend Robux to recover failed high-stakes runs, insure unsecured loot, trigger **Instant Rebirths** without reaching the level cap, pay to **Keep Everything** during a Rebirth, and supercharge their progression speed.

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

* **First-Time Onboarding Session:** 12–20 minutes (includes tutorial run + first permanent upgrades + second run to Room 10).
* **Standard Portal Run (Rooms 1–10):** 8–12 minutes.
* **Extended Deep Run (Rooms 11–20):** 15–25 minutes.
* **Endless High-Corruption Run (Rooms 21+):** 30+ minutes.

---

## 5. Game Structure

### 5.1 The Town Hub (Haven Outpost)
The Town Hub is a vibrant 2.5D multi-tiered social space (inspired by *Henesys* and *Perion*) where players gather, show off their Rebirth Wings, weapon auras, and titles, and manage permanent progression:
* **The Central Rift Gate:** Enter solo, manage parties, select Portal Worlds, and adjust **Corruption Tiers**.
* **The Ascension Pedestal & Spark Sanctum (Rebirth Altar):** Perform **Rift Rebirths** once the required Hunter Level is met (or via Robux), spend **Rebirth Sparks** in the **Ascension Shop**, and preview next Rebirth multipliers.
* **Mastery & Legion Hall:** View weapon mastery levels, equip account-wide **Hunter Link Skills**, and claim milestone rewards.
* **The Star-Forge & Relic Vault:** View discovered Relics and spend *Rift Dust* or duplicate Relic shards to Star-Force them.
* **Blacksmith & Weapon Trainer:** Unlock new weapons and test builds on training dummies with a live DPS meter.
* **Rift Shrine (Server Booster Altar):** Trigger Robux or milestone-earned **Rift Surges**.
* **Hall of Champions:** Separate physical podiums and leaderboards for **Standard Runs**, **Pure Runs**, and **Top Rebirth Rank**.

### 5.2 Portal Runs
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

1. **Minute-to-Minute Room Loop (20–45s):** Enter Room $\rightarrow$ Execute & Mob across 2.5D platforms $\rightarrow$ Collect loot bursts $\rightarrow$ Pick 1 of 3/4 transformative upgrades $\rightarrow$ Enter next portal door.
2. **Run-to-Run Extraction Loop (8–20m):** Prep in Town $\rightarrow$ Build synergies across rooms $\rightarrow$ Defeat Boss at Room 5/10/15 to activate **Rift Anchor** $\rightarrow$ Extract safely with $100\%$ loot OR push deeper for escalating multipliers.
3. **Long-Term Grind & Rebirth Loop (10–300+ hrs):** Level **Hunter Level** $\rightarrow$ Perform **Rift Rebirths** $\rightarrow$ Spend **Rebirth Sparks** in the **Ascension Shop** $\rightarrow$ Max all 8 Weapons' **Link Skills** $\rightarrow$ **Star-Force** Relics to 5-Star $\rightarrow$ Climb **Corruption Tiers 1–100+**.

---

## 7. Player Presentation, Camera & 2.5D Physics Rules (Locked Decision)

* **Movement Axes & Z-Plane Lock:** Players and monsters move along the X-axis and Y-axis. All characters and monsters have an `AlignPosition` / `PlaneConstraint` locking their RootPart to $Z = 0$ and `CollisionGroup = "ActorsNoCollide"`.
* **Vertical Stagger Instead of Horizontal Knockback:** Heavy attacks apply **Vertical Launch / Micro-Stun** in place rather than horizontal knockback so enemies are never pushed off platforms.
* **Camera Settings:** Narrow FOV ($35^\circ$) at $Z = +42$ studs with smooth spring-damped vertical tracking.

---

## 8. Controls & Cross-Platform Ergonomics

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

## 9. Combat Design & Elemental Status Synergies

* **Physical (Bleed):** Stacks up to 10 times ($15\%$ Base Attack/s per stack); 10 stacks trigger *Hemorrhage* ($250\%$ AoE burst, capped at $5\%$ Boss Max HP).
* **Fire (Burn):** $40\%$ Base Attack/s for $4\text{s}$; spreads within $10$ studs on death.
* **Ice (Chill / Freeze):** Slows by $6\%$ per stack; 5 stacks freeze non-bosses for $2.5\text{s}$ and shatter for $180\%$ AoE on heavy hit.
* **Lightning (Shock):** Chains lightning bolts to 3 nearby targets across platforms for $45\%$ hit damage.
* **Poison (Toxin):** Infinitely stacking DoT ($20\%$ Base Attack/s) + reduces enemy damage dealt by $15\%$.
* **Arcane (Mark):** Next ability hit deals guaranteed Critical Damage and reduces skill cooldowns by $1.0\text{s}$.

---

## 10. Weapons

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

### Example Evolution Tree: Staff — *Fireball*
* **Base Skill:** Fires a multi-layered blazing orb horizontally ($220\%$ Weapon Damage, $3.5\text{s}$ cooldown).
* **Evolution 1 (Multi-Cast):** *Triple Threat* — Fires 3 Fireballs in a $20^\circ$ fan across multiple platform heights (each dealing $75\%$ of full skill damage).
* **Evolution 2 (Terrain):** *Napalm Wake* — Leaves a scorching carpet of fire along the platform for $4\text{s}$ ($45\%$ Weapon Damage/s).
* **Evolution 3 (Chain Reaction):** *Volatile Cinders* — Enemies dying while Burning explode into 2 homing mini-fireballs ($80\%$ Weapon Damage each).
* **Evolution 4 (Capstone Synergy):** *Cataclysmic Meteor* — Every 5th cast calls down a giant diagonal meteor ($500\%$ Weapon Damage across the platform tier).

---

## 12. Run Upgrades & RNG Control

* **Base Rarity Weights:** Common ($55\%$), Rare ($28\%$), Epic ($12\%$), Legendary ($4\%$), Corrupted ($1\%$).
* **Depth & Luck Scaling:** Every 5 rooms cleared shifts $+5\%$ weight from Common into Rare/Epic/Legendary.
* **Upgrade Rerolls & Banish System:** Players earn free Rerolls/Banishes via Rebirths and the Ascension Shop (`Fate Manipulation`).

---

## 13. Relics & The Star-Force Awakening System

* **Non-Destructive Pity Rule:** Failing a Star-Force attempt *never* destroys or downgrades a Relic; it fills the **Star Pity Bar** by $+25\%$ (4 failures = guaranteed $100\%$ success).

| Star Level | Upgrade Cost | Effect on *Thunder Boots* (Example) | Base Success Rate |
| :--- | :--- | :--- | :--- |
| **1-Star (Base)** | First Discovery | Double-jump fires 2 bolts for $50\%$ weapon damage. | $100\%$ |
| **2-Star** | 3 Shards + 500 Dust | Double-jump fires 3 bolts for $65\%$ weapon damage. | $90\%$ |
| **3-Star** | 8 Shards + 1,500 Dust | Bolts now inflict *Shock* and chain to 1 extra target. | $75\%$ |
| **4-Star** | 20 Shards + 4,000 Dust | Double-jump fires 4 bolts for $90\%$ weapon damage. | $50\%$ |
| **5-Star (Awakened)** | 50 Shards + 12,000 Dust | **Awakening:** Every 3rd double-jump leaves a stationary Lightning Totem on the platform for $6\text{s}$. | $30\%$ ($100\%$ with *Star Shield*) |

---

## 14. Curses

* **Glass Flame:** $2.0\times$ total damage, Max HP capped at $50\%$.
* **Mimic's Fortune:** $2\times$ Treasure Chests, $40\%$ are Elite Mimics.
* **King's Challenge:** Boss spawns a $50\%$ HP phantom clone, drops $2\times$ **Boss Cores** + guaranteed Epic+ Relic.
* **Unstable Momentum:** Move Speed $+40\%$, Attack Speed $+25\%$, standing still $>1.5\text{s}$ triggers a lightning strike ($10\%$ Max HP).
* **Greedy Portal:** *Rift Dust* $+100\%$, next Rift Anchor extraction point is locked.

---

## 15. Room Types & Objectives

* **Combat Rooms:** Extermination, Rift Surge Survival, Elite Hunt, Crystal Defense, Combo Trials.
* **Movement Rooms ("Jump Quests"):** Rising Corruption climb, Laser Gauntlet, Shadow Race. *(Failing a Jump Quest never ends the run; only forfeits bonus chest).*
* **Collection & Event Rooms:** Loot Goblin Chase, Mimic Roulette, Spirit Harvest.
* **Special Utility Rooms:** Travelling Merchant, The Fusion Anvil, Gambling Shrine.

---

## 16. Portal Worlds & Corruption Tiers

1. **Mushroom Wilds (World 1):** Base Multiplier $1.0\times$.
2. **Toy Kingdom (World 2):** Base Multiplier $1.8\times$.
3. **Haunted Metro (World 3):** Base Multiplier $3.2\times$.
4. **Frozen Citadel (World 4):** Base Multiplier $5.5\times$.
5. **Neon Cyber-Grid (World 5):** Base Multiplier $9.5\times$.
6. **Dessert Wastes (World 6):** Base Multiplier $16.0\times$.
7. **Sunken Archive (World 7):** Base Multiplier $27.0\times$.
8. **Volcanic Forge (World 8):** Base Multiplier $45.0\times$.

---

## 17. Bosses

* **Spore Golem (World 1 Room 5 Mini-Boss)**
* **Mushroom Titan (World 1 Room 10 World Boss)**
* **Clockwork King (World 2 Room 10)**
* **Conductor Phantom (World 3 Room 10)**
* **Candy Dragon (World 6 Room 10)**
* **The Collector (Secret Endless Boss — Room 20+)**

---

## 18. Difficulty, Dynamic Party Scaling & Rift Sidekick Sync

$$
\text{PartyHPScale}(P) = 1 + 0.55 \times (P - 1), \quad \text{PartySpawnCountScale}(P) = 1 + 0.25 \times (P - 1)
$$

* **Rift Sidekick Sync:** Lower-level party members have their in-run combat power and Max HP bolstered to at least **$70\%$ of the Party Host's baseline**, while their XP/Dust rewards are capped at **$3.0\times$ the baseline of their highest personally unlocked World/Corruption Tier**.

---

## 19. Failure, Extraction, and Checkpoints

* **Tiered Unsecured Loot Loss Penalty:** Rooms 1–5 ($30\%$ loss), Rooms 6–10 ($50\%$ loss), Rooms 11+ ($75\%$ loss). *Hunter XP is never lost on defeat.*
* **Individual Party Extraction:** Each player chooses independently at every Rift Anchor whether to extract or continue.

---

## 20. The Defeat Screen & High-Conversion Recovery

1. **Accept Defeat (Free)**
2. **Use Anchor Token (Earned Free Currency)**
3. **Rift Revive (39 R$)**
4. **Checkpoint Rewind (49 R$)**
5. **Insure & Extract Now (29 R$)**

---

## 21. Endless Permanent Progression Architecture

1. **Hunter Level (1–400+)** $\rightarrow$ 2. **Rift Rebirths (I–X+)** $\rightarrow$ 3. **Ascension Shop (18 Nodes)** $\rightarrow$ 4. **Weapon Mastery (1–20)** $\rightarrow$ 5. **Hunter Legion (Link Skills)** $\rightarrow$ 6. **Relic Star-Forcing (1★–5★)** $\rightarrow$ 7. **Infinite Paragon (21–999) & Corruption Tiers (1–100+)**.

---

## 22. The Rift Rebirth & Ascension System

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

## 23. The Ascension Shop (Rebirth Spark Upgrades)

* **Tier 1 (Rebirth I):** `AS_T1_01` Ascendant Might (10 Lv, $+8\%$ Dmg/HP), `AS_T1_02` Rift Scholar (5 Lv, $+12\%$ XP), `AS_T1_03` Vacuum Aura (3 Lv, Full-Room Magnet), `AS_T1_04` Headstart Blessing (3 Lv, Room 1 Epic+ Orb), `AS_T1_05` Dimensional Pocket (4 Lv, $15\%/\text{lv}$ Dust Vault).
* **Tier 2 (Rebirth III):** `AS_T2_01` Skywalker's Grace (3 Lv, Triple Jump + Extra Dash), `AS_T2_02` Fate Manipulation (3 Lv, $+1$ Reroll/Banish per lv), `AS_T2_03` Anchor Guardian (4 Lv, $-10\%$ Loot Loss/lv), `AS_T2_04` Boss Hunter's Trophy (5 Lv, $+20\%$ Extra Core/Shard chance).
* **Tier 3 (Rebirth V):** `AS_T3_01` Elemental Crit Overload (3 Lv, Status DoTs Crit), `AS_T3_02` Relic Resonance (5 Lv, $+10\%$ Relic power), `AS_T3_03` Twin Relic Vessel (1 Lv, 2nd Starting Relic), `AS_T3_04` Legion Commander (2 Lv, $+2$ Link Slots).
* **Tier 4 (Rebirth X):** `AS_T4_01` Limit Breaker (3 Lv, $+1$ Shadow Line at $15\%$ dmg/lv), `AS_T4_02` Miracle Evolution (1 Lv, $15\%$ Double Upgrade Orb), `AS_INF_01` Omnipotence ($\infty$, $+5\%$ Dmg/lv), `AS_INF_02` Prosperity ($\infty$, $+5\%$ Dust/XP per lv).

---

## 24. Mathematical Formulas & Balance Engine (`FormulaEngine.luau`)

*(Refer to `ReplicatedStorage/Shared/FormulaEngine.luau` implemented in Step 1 for the exact XP curve $\text{XP}_{\text{Req}}(L) = \text{round}(80 L^{1.65} + 40 L)$, 6-bucket damage calculation, monster scaling, and defeat dust retention).*

---

## 25. Weapon Mastery, Hunter Legion & Infinite Paragon Ranks

* **Levels 1–20:** Unlocks alternate attacks and **Hunter Link Skills** at Lv 10 and Lv 20.
* **Paragon Ranks (21–999+):** $+0.5\%$ Weapon Base Damage and $+0.5\%$ *Rift Dust* Find per rank, plus floating weapon auras at Paragon 50, 100, 250, 500.

---

## 26. Quests, Bounties & Economy Currencies

1. **Rift Dust** | 2. **Boss Cores** | 3. **Relic Shards** | 4. **Rebirth Sparks** | 5. **Anchor Tokens**

---

## 27. Complete Robux Monetization Suite

* **Developer Products:** Instant Rebirth (49–399 R$), Keep Everything Seal (99 R$), Rift Revive (39 R$), Checkpoint Rewind (49 R$), Insure & Extract (29 R$), Supercharged Run Token (79 R$), Server Rift Surge (99 R$).
* **Gamepasses:** Permanent Keep-On-Rebirth (599 R$), 2x Hunter XP (399 R$), 2x Rift Dust (449 R$), 4th Upgrade Choice (299 R$), Banish Pass (199 R$), Starting Relic Key (399 R$), Extra Link Slots (249 R$), Permanent Vault Insurance (299 R$).

---

## 28. Technical Architecture for Roblox

```text
src/
├── ReplicatedStorage/
│   ├── Shared/
│   │   ├── FormulaEngine.luau
│   │   ├── AssetRegistry.luau
│   │   ├── ProceduralArtFactory.luau   -- NEW v2.7: High-detail multi-part 3D weapons, monsters, tiles & props (Section 32)
│   │   ├── IconRenderer.luau           -- NEW v2.7: Custom layered vector/gradient UI icon builder (Section 32.6)
│   │   ├── ModelNormalizer.luau
│   │   ├── RoomAsciiTemplates.luau
│   │   ├── AscensionShopConfig.luau
│   │   ├── WeaponConfig.luau
│   │   ├── UpgradePoolConfig.luau
│   │   ├── RelicConfig.luau
│   │   └── EnemyConfig.luau
│   └── Remotes/
├── ServerScriptService/
│   └── Services/
└── StarterPlayer/
    └── StarterPlayerScripts/
        └── Controllers/
```

---

## 29. Core Build Roadmap (Steps 1–6)

*(If the core functional prototype Steps 1–6 are already complete in your repository, proceed directly to **Section 32: Visual Overhaul Roadmap (Steps V1–V4)** below!)*

---

## 30. Post-Audit Review & Future Expansion Roadmap

1. Collectible Damage Skins | 2. Boss Familiar Cards | 3. AFK Dojo Training Grounds | 4. 8-Player Dimensional Raid Bosses | 5. Weapon Potential Cubing | 6. Guild Citadels | 7. Daily Mirror Rift Seeds.

---

## 31. Asset Swap & `ModelNormalizer.luau` Pipeline

*(Retains full support for dropping external models into `ReplicatedStorage.Assets` to override procedural models automatically).*

---

## 32. Advanced Visual Polish & Bespoke Procedural Art Upgrade Specification (v2.7 — Fixing the "Stock" Look)

> **CRITICAL DIRECTIVE FOR CLAUDE CODE:**
> The developer has reviewed the initial functional prototype and found that the **textures, weapons, skills, monsters, interactables, and UI icons look too "stock" and basic** (simple blocks/spheres, flat materials, single-part projectiles, and plain text emojis).
>
> When executing the **Visual Overhaul (Steps V1–V4)**, you MUST replace all primitive placeholder generators with the **High-Detail Multi-Part Kitbashing, Layered Surface Detailing, Multi-Stage VFX, and Vector UI Icon Architecture** defined below.

---

### 32.1 Why the Initial Build Looked "Stock" vs. The v2.7 High-Detail Standard

| Visual Category | ❌ Forbidden "Stock" Approach (v1 Prototype) | ✅ Mandatory v2.7 Bespoke Standard (What Claude Code Must Write) |
| :--- | :--- | :--- |
| **Environment Tiles & Platforms** | Single brown `Part` with a flat green `Part` on top; empty background. | **7-to-12 Part Layered Strata Tile:** Dark slate under-rock with rotated `WedgePart` bevels, overhanging mossy grass lip with staggered edge teeth, glowing crystal vein inlays, hanging vine strips, surface grass blades/pebbles, and **3 Parallax Background Depth Layers** ($Z = -12, -26, -45$) with giant glowing mushroom silhouettes, ruins, and floating spore motes. |
| **Weapons (Swords, Staves, Bows)** | 2–3 basic blocks/cylinders welded together. | **14-to-22 Part Sculpted Kitbash:** Detailed pommel gem, spiral grip rings, swept wing crossguards (`WedgePart` pairs), metallic blade core with beveled edges, glowing runic fuller channel, floating elemental sub-parts, `Beam` slash ribbons, and weapon aura particles. |
| **Monsters & Bosses** | 1 cylinder + 1 ball with two black dots for eyes. | **16-to-28 Part Articulated Creature:** Multi-tiered scalloped mushroom cap with rim trim, glowing under-gills (`Beam`/`Neon` fins), raised embossed spots, angry brow ridges, multi-layered eyes (sclera + glowing iris + pupil + highlight dot), root feet, spore chimneys on the back, and ambient spore emitters. |
| **Skills & Combat VFX** | A single Neon ball moving in a straight line. | **4-Stage Anime/MapleStory VFX Sequence:** (1) **Cast Burst:** Expanding ground magic circle + hand flash; (2) **Projectile:** Spinning core + outer plasma shell + spiraling orbital shards + dual `Trail` ribbons; (3) **Impact:** Expanding shockwave ring mesh + 3D flying debris chunks + radial spark burst + screen micro-shake; (4) **Lingering Wake:** Scorched ground decals + rising embers. |
| **Interactables (Anchors, Chests, Pedestals)** | A single glowing cylinder or box. | **20+ Part Animated Architectural Shrine:** Stepped octagonal stone plinth, floating rotating rune rings (`RunService.Heartbeat` CFrame spin), chained floating crystal obelisk, orbiting wisp spheres, and vertical sky-beam (`Beam` + `PointLight`). |
| **2D UI Icons** | Plain Unicode Emoji (`⚔️`, `🔮`) sitting in a flat square frame. | **Multi-Layer Procedural Vector Badge (`IconRenderer.luau`):** Rotated $45^\circ$ diamond backplates, multi-stop metallic/neon `UIGradient`, double inner/outer `UIStroke`, custom geometric weapon/crystal silhouettes assembled from rotated `Frame`/`UICorner` primitives, specular gloss overlay, and rarity particle shimmer. |

---

### 32.2 Detailed 3D Kitbashing Blueprints for Weapons (`ProceduralArtFactory.BuildWeaponModel`)

Claude Code MUST construct each weapon in `ProceduralArtFactory.luau` with at least **14–22 welded sub-parts** using combinations of `Part`, `WedgePart`, `CornerWedgePart`, `Cylinder`, `Ball`, `SpecialMesh (FileMesh/Sphere/Cylinder)`, `Trail`, and `ParticleEmitter`:

1. **Greatsword (*"Riftcleaver Broadsword"* — 18 Parts):**
   * **Pommel:** Octagonal dark-iron cap + glowing purple *Rift Core* sphere nestled inside a claw setting.
   * **Hilt Grip:** Dark leather `Cylinder` wrapped with 4 angled gold collar rings.
   * **Crossguard:** Swept twin dragon-wing `WedgePart` assemblies with gold `Metal` trim and a central glowing rune eye.
   * **Blade Core & Bevels:** Wide dark-steel center fuller (`Reflectance = 0.25`, `Material = Metal`), flanked by 2 sharp silver beveled `WedgePart` cutting edges, topped with a twin-wedge diamond tip, and inlaid with 3 glowing violet `Neon` rune slots running up the spine.
   * **Attachments:** `SlashTrailTop` and `SlashTrailBottom` attachments connected by a wide crescent `Trail` (`ColorSequence` from White to Violet, `Lifetime = 0.18s`).

2. **Staff (*"Astral Archon Staff"* — 19 Parts):**
   * **Shaft:** Tapered dark-wood & brass segmented pole with 5 spiral gold bands and a pointed bottom ferrule.
   * **Head Crescent:** A curved crescent cradle built from 6 angled gold/obsidian `WedgePart` segments forming a tuning-fork arc.
   * **Floating Core:** A levitating, rotating 3-part crystal gyroscope (inner blazing orange-violet `Neon` sphere + 2 perpendicular spinning brass/neon rings driven by `RunService.Heartbeat`).

3. **Bow (*"Sylvan Windrunner Greatbow"* — 16 Parts):**
   * **Riser (Grip):** Sculpted emerald-and-gold grip with forward-swept limb sockets.
   * **Upper & Lower Limbs:** Multi-segmented recurve limbs built from 4 angled `WedgePart` feathers each, tipped with glowing cyan spirit crystals.
   * **Bowstring & Energy Arrow:** A glowing cyan `Beam` string stretched between the limb tips that dynamically pulls back during attack animations.

---

### 32.3 Detailed 3D Kitbashing Blueprints for Monsters & Bosses (`ProceduralArtFactory.BuildEnemyModel`)

Every monster in `ProceduralArtFactory.luau` must have distinct silhouette details, facial expression parts, and surface breakup:

1. **Bounce-Cap Mushroom (18 Parts):**
   * **Stalk/Body:** Tapered cream-colored organic body (3 stacked/blended cylinders/spheres) with 2 stubby root feet that alternate during hops, plus a mossy collar ring around the neck.
   * **Multi-Layered Cap:** Wide crimson dome base + ruffled under-cap gill ring (8 radial thin plates) + 6 raised ivory `Cylinder`/`Ball` spots of varying sizes tilted to match the dome's surface normal + a glowing corrupted purple crystal cluster bursting out of the top-left of the cap.
   * **Expressive Face:** Deep-set dark eye sockets, glowing amber irises, vertical slit pupils, and 2 angled furrowed brow wedges so it looks fierce rather than blank.

2. **Spore Golem Mini-Boss (26 Parts) & Mushroom Titan World Boss (34 Parts):**
   * **Articulated Limbs:** Separate Left/Right Shoulder Pauldrons (mossy cliff slabs), Upper Arms, Forearm Gauntlets studded with glowing purple crystals, Torso Core with an exposed glowing ribcage crystal heart, Pelvis, and heavy Pillar Legs.
   * **Crown & Back Vents:** 3 smoking spore chimney tubes on its back emitting purple spore clouds, and a jagged crown of crystals around its head.

---

### 32.4 Detailed 4-Stage Skill & Combat VFX Specification (`CombatVFXController.luau`)

Every active ability and basic attack MUST execute a **4-Stage Visual Sequence** using `TweenService` and pooled emitters:

1. **Stage 1 — Cast / Swing Telegraph ($0.0\text{s} - 0.08\text{s}$):**
   * Spawn a flat, rapidly expanding glowing ring + rotated square rune frame at the caster's feet or hand (`Size` tweens from `1x0.1x1` to `7x0.1x7`, `Transparency` `0 -> 1` over `0.25s`).
2. **Stage 2 — Multi-Layered Projectile / Slash Arc ($0.08\text{s} - 0.6\text{s}$):**
   * **For Melee Slashes:** Spawn a curved 3D crescent wave mesh (built from 5 overlapping angled `WedgePart` blades in a $120^\circ$ arc) that scales outward and leaves lingering spark particles.
   * **For Projectiles (e.g., *Fireball*):** Never use a single sphere! Construct a **4-Layer Projectile Assembly**:
     * Layer 1: White-hot inner core (`Neon` sphere).
     * Layer 2: Translucent orange/crimson outer shell (`ForceField` or `Neon` at `Transparency = 0.45`, `1.4x` size).
     * Layer 3: Two rotating tilted fire-ring halos spinning around the projectile on `Heartbeat`.
     * Layer 4: Spiral ribbon `Trail` + ember `ParticleEmitter`.
3. **Stage 3 — High-Impact Explosion & Shockwave ($T_{\text{hit}}$):**
   * **Instant Flash Sphere:** Expands to `10x10x10` in `0.07s` then fades.
   * **3D Ground Shockwave Ring:** 8–12 angled stone/energy shards (`WedgePart`) erupting radially outward in a circle and sinking back into the floor.
   * **Hit-Stop & Camera Punch:** `0.04s` animation freeze on the attacker + subtle `0.35` stud camera impulse toward the hit direction.
4. **Stage 4 — Environmental Aftermath ($0.5\text{s} - 3.0\text{s}$):**
   * Leave a fading scorched/crystallized ground patch and rising smoke wisps.

---

### 32.5 Detailed Interactables & Environment Architecture (`RoomBuilderService.luau`)

1. **Bespoke 2.5D Environment Tiles (No Flat Boxes):**
   * Every `#` ground block generated by `RoomBuilderService` must call `ProceduralArtFactory.BuildTerrainTile(x, y, worldTheme, isTopExposed)` which builds:
     * A dark stone core with 2–3 random protruding rock strata plates on the front ($Z = +4.5$) face so every tile looks like carved cliff rock.
     * If `isTopExposed == true`: A vibrant lush grass cap that overhangs the stone by `0.4` studs, 3 staggered hanging moss teeth along the front rim, and a $40\%$ chance to spawn decorative surface props (a cluster of 3 mini glowing mushrooms, a fern bush, a cracked rune stone, or hanging vines).
   * **3-Layer Parallax Background Generator:** Behind every room ($Z = -14$, $Z = -28$, $Z = -48$), automatically spawn giant stylized background silhouettes (twisted ancient trees, giant glowing bioluminescent mushrooms, floating stone arches, and drifting volumetric fog/spore particles) so the stage feels like a rich *MapleStory* illustration.

2. **Bespoke Interactables:**
   * **The Rift Anchor (Room 5/10 Checkpoint):** A 22-part structure featuring a 3-stepped stone dais, 4 corner rune pillars, a levitating bobbing diamond core, 2 counter-rotating concentric neon rune rings, and a vertical sky-pillar `Beam` that turns from Crimson to Emerald when activated.
   * **Treasure & Cursed Chests:** A hinged 14-part chest with curved lid bands, golden lockplate, side handles, and glowing interior seam light (Cursed Chests add writhing purple chains, horns, and a glowing cyclops eye on the lock).
   * **The Ascension Pedestal (Rebirth Altar in Town):** A grand 30-part celestial shrine with twin winged statues, a swirling portal vortex disc at the base, and floating staircase steps.

---

### 32.6 Production-Ready Luau Modules for Bespoke 3D Art & Vector UI Icons

#### A. `ReplicatedStorage/Shared/ProceduralArtFactory.luau` (Copy-Paste Pattern for Claude Code)

```luau
--!strict
-- ReplicatedStorage/Shared/ProceduralArtFactory.luau
-- v2.7 High-Detail Multi-Part Kitbashing Factory for Weapons, Monsters, Tiles, Interactables & Projectiles

local TweenService = game:GetService("TweenService")
local ProceduralArtFactory = {}

local function makePart(name: string, size: Vector3, color: Color3, material: Enum.Material, parent: Instance, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Massless = true
	p.Parent = parent
	return p
end

local function makeWedge(name: string, size: Vector3, color: Color3, material: Enum.Material, parent: Instance): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Size = size
	w.Color = color
	w.Material = material
	w.Anchored = true
	w.CanCollide = false
	w.CanQuery = false
	w.Massless = true
	w.Parent = parent
	return w
end

local function weldTo(root: BasePart, part: BasePart, offsetCFrame: CFrame)
	part.CFrame = root.CFrame * offsetCFrame
	part.Anchored = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = root
end

-- Builds a 18-part sculpted "Riftcleaver Greatsword" instead of a stock block sword
function ProceduralArtFactory.BuildGreatsword(): Model
	local model = Instance.new("Model")
	model.Name = "Greatsword_HighDetail"

	local handle = makePart("Handle", Vector3.new(0.35, 1.8, 0.35), Color3.fromRGB(45, 35, 55), Enum.Material.Fabric, model, Enum.PartType.Cylinder)
	-- Rotate cylinder upright along Y
	handle.CFrame = CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(90))
	model.PrimaryPart = handle

	local root = makePart("GripRoot", Vector3.new(0.35, 1.8, 0.35), Color3.fromRGB(45, 35, 55), Enum.Material.SmoothPlastic, model)
	root.Transparency = 1
	model.PrimaryPart = root
	weldTo(root, handle, CFrame.Angles(0, 0, math.rad(90)))

	-- 1. Pommel & Glowing Core (3 parts)
	local pommelRing = makePart("PommelRing", Vector3.new(0.65, 0.3, 0.65), Color3.fromRGB(215, 175, 65), Enum.Material.Metal, model)
	weldTo(root, pommelRing, CFrame.new(0, -1.0, 0))
	local pommelGem = makePart("PommelGem", Vector3.new(0.5, 0.5, 0.5), Color3.fromRGB(195, 75, 255), Enum.Material.Neon, model, Enum.PartType.Ball)
	weldTo(root, pommelGem, CFrame.new(0, -1.25, 0))

	-- 2. Grip Wrap Rings (3 parts)
	for i = -1, 1 do
		local ring = makePart("GripBand_" .. i, Vector3.new(0.42, 0.12, 0.42), Color3.fromRGB(215, 175, 65), Enum.Material.Metal, model)
		weldTo(root, ring, CFrame.new(0, i * 0.45, 0))
	end

	-- 3. Swept Wing Crossguard & Center Rune (5 parts)
	local guardCenter = makePart("GuardCenter", Vector3.new(0.6, 0.55, 1.4), Color3.fromRGB(55, 50, 70), Enum.Material.Metal, model)
	weldTo(root, guardCenter, CFrame.new(0, 1.0, 0))
	local guardGem = makePart("GuardGem", Vector3.new(0.7, 0.35, 0.35), Color3.fromRGB(255, 95, 180), Enum.Material.Neon, model, Enum.PartType.Ball)
	weldTo(root, guardGem, CFrame.new(0, 1.0, 0))

	for _, side in { -1, 1 } do
		local wing = makeWedge("GuardWing_" .. side, Vector3.new(0.45, 0.7, 1.3), Color3.fromRGB(215, 175, 65), Enum.Material.Metal, model)
		weldTo(root, wing, CFrame.new(0, 1.15, side * 1.1) * CFrame.Angles(math.rad(side * 18), 0, 0))
	end

	-- 4. Multi-Bevel Blade Core, Edges, Tip & Glowing Fuller Runes (7 parts)
	local bladeCore = makePart("BladeCore", Vector3.new(0.22, 4.6, 0.75), Color3.fromRGB(40, 42, 58), Enum.Material.Metal, model)
	weldTo(root, bladeCore, CFrame.new(0, 3.5, 0))

	local edgeLeft = makeWedge("BladeEdgeL", Vector3.new(0.18, 4.6, 0.38), Color3.fromRGB(220, 230, 245), Enum.Material.Metal, model)
	weldTo(root, edgeLeft, CFrame.new(0, 3.5, 0.56) * CFrame.Angles(0, math.rad(180), 0))
	local edgeRight = makeWedge("BladeEdgeR", Vector3.new(0.18, 4.6, 0.38), Color3.fromRGB(220, 230, 245), Enum.Material.Metal, model)
	weldTo(root, edgeRight, CFrame.new(0, 3.5, -0.56))

	local tipL = makeWedge("BladeTipL", Vector3.new(0.20, 1.1, 0.56), Color3.fromRGB(220, 230, 245), Enum.Material.Metal, model)
	weldTo(root, tipL, CFrame.new(0, 6.35, -0.28))
	local tipR = makeWedge("BladeTipR", Vector3.new(0.20, 1.1, 0.56), Color3.fromRGB(220, 230, 245), Enum.Material.Metal, model)
	weldTo(root, tipR, CFrame.new(0, 6.35, 0.28) * CFrame.Angles(0, math.rad(180), 0))

	for r = 1, 3 do
		local rune = makePart("FullerRune_" .. r, Vector3.new(0.26, 0.65, 0.16), Color3.fromRGB(190, 85, 255), Enum.Material.Neon, model)
		weldTo(root, rune, CFrame.new(0, 1.6 + r * 1.1, 0))
	end

	-- 5. Weapon Slash Trail Attachments
	local att0 = Instance.new("Attachment", bladeCore)
	att0.Name = "TrailBase"
	att0.Position = Vector3.new(0, -2.1, 0)
	local att1 = Instance.new("Attachment", bladeCore)
	att1.Name = "TrailTip"
	att1.Position = Vector3.new(0, 2.8, 0)

	local trail = Instance.new("Trail")
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Lifetime = 0.18
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 230, 255), Color3.fromRGB(170, 50, 255))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1.0),
	})
	trail.Parent = bladeCore

	return model
end

return ProceduralArtFactory
```

#### B. `ReplicatedStorage/Shared/IconRenderer.luau` (Replaces Stock Emoji Text with Layered Vector Badges)

```luau
--!strict
-- ReplicatedStorage/Shared/IconRenderer.luau
-- v2.7 Procedural Layered Vector Icon & Rarity Badge Renderer (Zero Stock Plain Emojis)

local IconRenderer = {}

export type IconSpec = {
	Category: string, -- "Sword" | "Staff" | "Bow" | "Fireball" | "RiftDust" | "BossCore" | "Spark" | "Relic"
	PrimaryColor: Color3,
	AccentColor: Color3,
	GlowColor: Color3,
	SymbolGlyph: string?,
}

function IconRenderer.RenderIcon(parent: GuiObject, spec: IconSpec): Frame
	local container = Instance.new("Frame")
	container.Name = "VectorBadgeIcon"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundColor3 = Color3.fromRGB(22, 20, 34)
	container.BorderSizePixel = 0
	container.ClipsDescendants = true
	container.Parent = parent

	local corner = Instance.new("UICorner", container)
	corner.CornerRadius = UDim.new(0.22, 0)

	local bgGrad = Instance.new("UIGradient", container)
	bgGrad.Rotation = 45
	bgGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, spec.PrimaryColor:Lerp(Color3.new(0, 0, 0), 0.55)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(28, 24, 42)),
		ColorSequenceKeypoint.new(1, spec.AccentColor:Lerp(Color3.new(0, 0, 0), 0.35)),
	})

	local outerStroke = Instance.new("UIStroke", container)
	outerStroke.Thickness = 2.5
	outerStroke.Color = spec.AccentColor

	-- Layer 1: Rotated 45-degree Geometric Backplate Diamond
	local diamond = Instance.new("Frame")
	diamond.Name = "DiamondBackplate"
	diamond.AnchorPoint = Vector2.new(0.5, 0.5)
	diamond.Position = UDim2.fromScale(0.5, 0.5)
	diamond.Size = UDim2.fromScale(0.64, 0.64)
	diamond.Rotation = 45
	diamond.BackgroundColor3 = spec.PrimaryColor
	diamond.BackgroundTransparency = 0.25
	diamond.Parent = container
	Instance.new("UICorner", diamond).CornerRadius = UDim.new(0.18, 0)

	local diamondStroke = Instance.new("UIStroke", diamond)
	diamondStroke.Thickness = 1.5
	diamondStroke.Color = spec.GlowColor
	diamondStroke.Transparency = 0.2

	-- Layer 2: Bespoke Geometric Silhouette Shapes by Category
	local artLayer = Instance.new("Frame")
	artLayer.Name = "VectorSilhouette"
	artLayer.AnchorPoint = Vector2.new(0.5, 0.5)
	artLayer.Position = UDim2.fromScale(0.5, 0.5)
	artLayer.Size = UDim2.fromScale(0.78, 0.78)
	artLayer.BackgroundTransparency = 1
	artLayer.Parent = container

	if spec.Category == "Sword" then
		-- Crossed Blade + Guard Vector Shapes
		local blade = Instance.new("Frame", artLayer)
		blade.AnchorPoint = Vector2.new(0.5, 0.5)
		blade.Position = UDim2.fromScale(0.52, 0.46)
		blade.Size = UDim2.fromScale(0.18, 0.76)
		blade.Rotation = 38
		blade.BackgroundColor3 = Color3.fromRGB(240, 245, 255)
		Instance.new("UICorner", blade).CornerRadius = UDim.new(0.4, 0)

		local guard = Instance.new("Frame", artLayer)
		guard.AnchorPoint = Vector2.new(0.5, 0.5)
		guard.Position = UDim2.fromScale(0.38, 0.62)
		guard.Size = UDim2.fromScale(0.46, 0.12)
		guard.Rotation = -52
		guard.BackgroundColor3 = spec.AccentColor
		Instance.new("UICorner", guard).CornerRadius = UDim.new(0.5, 0)
	elseif spec.Category == "RiftDust" or spec.Category == "Spark" then
		-- Multi-Faceted Overlapping Crystal Star
		for _, rot in { 0, 45, 90, 135 } do
			local facet = Instance.new("Frame", artLayer)
			facet.AnchorPoint = Vector2.new(0.5, 0.5)
			facet.Position = UDim2.fromScale(0.5, 0.5)
			facet.Size = UDim2.fromScale(0.26, 0.72)
			facet.Rotation = rot
			facet.BackgroundColor3 = spec.GlowColor
			facet.BackgroundTransparency = 0.15
			Instance.new("UICorner", facet).CornerRadius = UDim.new(0.5, 0)
		end
	end

	-- Layer 3: Centered Stylized Emblem Glyph with Drop Shadow & Stroke
	if spec.SymbolGlyph and spec.SymbolGlyph ~= "" then
		local glyph = Instance.new("TextLabel", artLayer)
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Position = UDim2.fromScale(0.5, 0.5)
		glyph.Size = UDim2.fromScale(0.68, 0.68)
		glyph.BackgroundTransparency = 1
		glyph.Text = spec.SymbolGlyph
		glyph.TextScaled = true
		glyph.Font = Enum.Font.FredokaOne
		glyph.TextColor3 = Color3.new(1, 1, 1)
		local ts = Instance.new("UIStroke", glyph)
		ts.Thickness = 2
		ts.Color = Color3.fromRGB(15, 10, 25)
	end

	-- Layer 4: Top Gloss Specular Highlight Arc
	local gloss = Instance.new("Frame", container)
	gloss.AnchorPoint = Vector2.new(0.5, 0)
	gloss.Position = UDim2.fromScale(0.5, -0.15)
	gloss.Size = UDim2.fromScale(1.2, 0.45)
	gloss.Rotation = -12
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	gloss.BackgroundTransparency = 0.86
	Instance.new("UICorner", gloss).CornerRadius = UDim.new(0.5, 0)

	return container
end

return IconRenderer
```

---

### 32.7 Visual Overhaul Roadmap (Steps V1–V4 for Claude Code)

> **INSTRUCTION FOR USER & CLAUDE CODE:** Run these 4 dedicated Visual Upgrade steps using **`/model sonnet`** (with **`/clear`** between each step) to completely overhaul the look of the game without burning your $30 SGD Pro quota:

| Visual Step | Files to Create / Overhaul | Model & Thinking | Exact Copy-Paste Prompt to Give Claude Code |
| :--- | :--- | :--- | :--- |
| **Step V1: Multi-Part Weapons & Expressive Monsters** | Create `ProceduralArtFactory.luau` & update `AssetRegistry.luau` + `EnemyConfig.luau` | **`/model sonnet`** (Thinking: **OFF**) | *"Read `CLAUDE.md` Section 32.2, 32.3, and 32.6. Execute **Step V1**: Create `ProceduralArtFactory.luau` and replace all basic weapon, monster, and boss models with 15-to-30 part sculpted kitbashes (Greatsword, Staff, Bow, Bounce-Cap Mushroom, Spore Golem, Mushroom Titan) with expressive eyes, runes, and trails."* |
| **Step V2: Layered 2.5D Terrain Tiles, Parallax & Interactables** | Update `RoomBuilderService.luau` & `ProceduralArtFactory.luau` | **`/model sonnet`** (Thinking: **OFF**) | *"Read `CLAUDE.md` Section 32.5. Execute **Step V2**: Upgrade `RoomBuilderService.luau` so every ground/platform tile uses layered rock strata, overhanging moss lips, surface grass/mushroom props, 3 parallax background layers ($Z=-14, -28, -48$), and 20-part animated Rift Anchors, Chests, and Rebirth Pedestals."* |
| **Step V3: 4-Stage Anime/MapleStory Skill & Combat VFX** | Overhaul `CombatVFXController.luau` & `ProceduralAnimController.luau` | **`/model sonnet`** (Thinking: **ON**) | *"Read `CLAUDE.md` Section 32.4. Execute **Step V3**: Overhaul `CombatVFXController.luau` so every weapon swing and skill executes a 4-stage VFX sequence (cast rune circle, multi-layered spinning projectile or 3D crescent slash wave, radial shard shockwave on hit, and lingering ground wake)."* |
| **Step V4: Vector Badge Icons & Stylized Lighting Polish** | Create `IconRenderer.luau` & update `UIController.luau` + `Lighting` setup | **`/model sonnet`** (Thinking: **OFF**) | *"Read `CLAUDE.md` Section 32.6. Execute **Step V4**: Create `IconRenderer.luau` and update `UIController.luau` to replace all plain emoji icons with multi-layered vector badges, gradients, and gloss overlays, and configure `Lighting` with Future shadows, Atmosphere, Bloom, and ColorCorrection."* |