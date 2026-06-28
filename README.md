# Exceed Chess

> *Chess where you earn the right to break its own rules.*

A strategy game that starts as standard chess and transforms into something far stranger. Captures earn **Soul Points** which fund piece upgrades, powerful new units, and eventually the board itself fractures into floating islands that players must bridge across to survive.

---

## Running Locally

### Requirements
- [Godot 4](https://godotengine.org/download) (standard build, **not** the .NET/C# version)

### Steps
1. Clone or download this repository
2. Open Godot 4
3. Click **Import** in the Project Manager
4. Navigate to the `exceed_chess/` folder and select `project.godot`
5. Click **Import & Edit**
6. Press **F5** (or the ▶ Play button) to run

The game opens directly to the board. Two players share a mouse on one machine.

---

## How to Play

### Phase 1 — Standard Chess (Turns 1–49)
- Plays like normal chess: click a piece to see legal moves, click a destination to move
- **Castling** and **en passant** are supported
- Capturing a piece earns **Soul Points (SP)** equal to its value

### Soul Points (SP)
| Piece | SP |
|---|---|
| Pawn | 1 |
| Knight / Bishop | 3 |
| Rook | 5 |
| Queen | 9 |
| Dragon | 20 |
| Hydra | 40 |
| Neutral Beast | 15 |

Click **Buy Upgrades** (top-left, available during your turn) to spend SP. Upgrades do **not** cost your move — you can buy them and still move on the same turn.

### Pre-Turn-50 Upgrades
| Upgrade | Cost | Effect |
|---|---|---|
| Promote: Knight | 3 SP | Pawn instantly becomes a Knight |
| Promote: Bishop | 3 SP | Pawn instantly becomes a Bishop |
| Convert to Mage | 8 SP | Pawn becomes a Mage (moves 2 orthogonal squares) |
| Vigilant Bishop | 5 SP | Bishop also gains King-range step movement |
| Stomper | 5 SP | Knight can capture 1 adjacent piece after landing |
| Wandering Rook | 5 SP | Rook gets 1 extra step after its slide |
| Queen Supreme | 6 SP | Queen also gains Knight jump |
| Mounted King | 7 SP | King also gains Knight jump |

### Mages & Portals
- Convert a Pawn to a Mage (8 SP)
- Move the Mage to an **edge tile** of an island → a **purple portal toggle** appears on its cell
- Click the Mage's own cell to open a portal (costs your move)
- With **two active portals**, any friendly piece adjacent to one can teleport to the other
- Capturing a Mage collapses its portal

### Bridges
- Pieces tagged as bridge builders: **Pawn, Knight, Queen, King, Mage**
- Moving one of these to an island edge tile (shown in **tan/gold** when selected) starts bridge construction
- After **2 turns**, the bridge completes and connects the islands — any piece can cross
- Enemy pieces can destroy bridge tiles by moving onto them

### Phase 2 — The First Sinister (Turn 50)
- The board **fractures** into 4 separate quadrant islands + a small **3×3 Sinister Island** in the center
- Islands visually drift apart; right-click drag to pan the view
- A **Relic** appears on the Sinister Island
- Controlling the Relic island (your pieces present, no enemies) earns **+50 Relic Points per turn**
- Post-Turn-50 upgrades unlock: **Assassin**, **Elemental Mages**, **Summon Dragon**

### Post-Turn-50 Upgrades
| Upgrade | Cost | Effect |
|---|---|---|
| Assassin | 7 SP | Bishop can capture again after capturing |
| Fire Mage | 8 SP | Mage attacks any piece in its row/column without moving |
| Water Mage | 8 SP | Enemy pieces on same island move at half range |
| Wind Mage | 8 SP | Push or pull any unit up to 2 tiles |
| Earth Mage | 8 SP | Root any unit for 1 turn |
| Void Mage | 9 SP | Portal from any tile; can teleport itself anywhere |
| Summon Dragon | 25 SP | 3×3 beast arrives on a new 5×5 island |

### Dragon
- Moves like a Rook as a 3×3 block; **sweeps Pawns** in its path (they die, Dragon keeps moving)
- Stops at the first non-Pawn enemy
- **Immune to Pawns** — Pawn captures do nothing
- Non-Pawn pieces can hit it: **attacker is destroyed**, Dragon loses 1 life (3 total)
- Awards 20 SP when killed

### Phase 3 — The Second Sinister (Turn 100)
- Each of the 4 quadrant islands **splits again** into 8 smaller strips
- If the Relic was never claimed since Turn 50, a **Neutral Beast** spawns on it and rampages
- New Relic appears on the Sinister Island again
- Post-Turn-100 upgrades unlock (War Chief, Juggernaut, Inferno Mage, etc.)
- **Summon Hydra** (50 SP) unlocks: 4×4 beast, 7 lives, moves like a Queen

### Hydra
- Same rules as Dragon but 7 lives, moves as a 4×4 block in all 8 directions
- Awards 40 SP when killed

### Neutral Beasts
- Appear in dark red, labelled **BST**
- Move one random step after every player's turn
- Capture any piece they land on (except Kings)
- Any player can capture them for **15 SP**

### Win Conditions
- **Checkmate** — instant win (available at any point)
- **Score** — if no checkmate by Turn 200, the player with more Relic Points wins

---

## Controls
| Input | Action |
|---|---|
| Left click | Select piece / confirm move |
| Right-click drag | Pan the camera |
| Escape | Cancel bonus action / upgrade selection |

---

## Architecture Notes (for contributors)

The project uses **Godot 4 GDScript** with a strict data-driven design:

- All piece behaviour lives in `.tres` Resource files under `resources/pieces/`
- All upgrades are `.tres` files under `resources/upgrades/`
- Balance values (SP costs, turn thresholds) live in `resources/game_config.tres`
- Board state is a `Dictionary[Vector2i, CellState]` — fractures delete keys, expansions add keys
- Logic layer (`scripts/logic/`) is pure `RefCounted` with no scene imports
- Visual layer (`scripts/logic/board_renderer.gd`) subscribes to `EventBus` signals and never writes board state
- To add a new piece: drop a new `.tres` in `resources/pieces/` — no code changes needed
- To add a new upgrade: drop a `.tres` in `resources/upgrades/` — no code changes needed
