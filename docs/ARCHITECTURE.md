# Architecture

Big Battle Chess is built in strict layers. Each layer may only depend on the layers below it.

```
UI (scripts/ui)                menus, HUD, dialogs, cinematic overlay
App (scripts/app)              composition root (main.gd), Settings, input map
Gameplay (scripts/gameplay)    GameSession state machine, MovePresenter, saves
Presentation                   board/, characters/, animation/, combat/, camera/, environment/, audio/
AI (scripts/ai)                evaluation, search, worker-thread player, UCI client
Chess core (scripts/core)      Chess, ChessPosition, ChessMatch, ChessNotation, ChessClock, ChessMoveRecord
```

**The chess core knows nothing about scenes, animation or UI.** It is plain `RefCounted` data, so it is tested headless (perft, rules) and is cheap to clone for the AI thread.

## Move flow

1. A human clicks a square (`BoardView.square_clicked`), or the AI delivers a move (`ChessAIPlayer.move_ready`).
2. `GameSession._commit()` validates the move and commits it in `ChessMatch`. **The result is now final.** The match emits a `ChessMoveRecord`: piece, captured piece and square, flags, SAN, check/mate, and a deterministic presentation seed.
3. If the AI moves next, its search starts immediately on a worker thread, so it thinks during the cinematic.
4. `MovePresenter.present(record, position)` animates the move:
   - walking or galloping
   - castling rook
   - capture as either a board strike (Classic) or an arena battle (`BattleDirector`, Epic/Dynamic/Quick)
   - promotion
   - the checkmate scene
5. Every presentation path ends with `BoardView.sync_to_position()`. This reconciles the visual rigs with the authoritative position, so skipping, speeding up or interrupting a presentation can never duplicate or lose a piece.
6. The session autosaves and starts the next turn.

The clock only runs while a player is thinking (`AWAIT_HUMAN`, `AWAIT_AI`, `PROMOTION`). It never runs during presentation, menus or pauses.

## Main components

| Component | Responsibility |
|---|---|
| `ChessPosition` | 10×12 mailbox board, make/unmake, legal moves, attacks, Zobrist hash, FEN, repetition and material helpers |
| `ChessMatch` | Authoritative match: commit, undo/redo, results and draw rules, resign/draw/timeout, PGN, save dict |
| `GameSession` | State machine `AWAIT_HUMAN / AWAIT_AI / PROMOTION / PRESENTING / GAME_OVER / REPLAY`, input routing, AI, clock, autosave |
| `MovePresenter` | Turns a `ChessMoveRecord` into animation and battles; skip-safe |
| `BoardView` | Board surface and themes, piece rigs, markers, analytic picking (rays against piece cylinders, then the board plane) |
| `CharacterRig` / `HorseRig` | Procedural articulated warriors and horses built from shared meshes and materials |
| `PoseAnimator` + `PoseLibrary` | Keyframed poses with eased segments, cross-fades, timed events and time scale |
| `CombatChoreographer` | Builds a `CombatTimeline` (data) from combat profiles, mode and seed |
| `BattleDirector` | Executes timelines in the `BattleArena`: motion, cues, camera, VFX, audio, slow motion, skip |
| `CinematicCamera` | Shot library evaluated from live fighter anchors, blends, shake, DOF, clipping avoidance |
| `HallEnvironment` / `BattleArena` | Procedural environments; the arena uses its own render layer (2), lights and Environment |
| `Settings` / `Audio` | Autoloads: persistent preferences, audio buses and music cross-fades |

## Rendering separation

The board world is on render layer 1 and the arena on layer 2. Each layer has its own lights (`light_cull_mask`) and its own `Environment`, which the `CinematicCamera` overrides. The arena is hidden when no battle is running, so it costs nothing. Before the title screen appears, battle shaders and pipelines are pre-warmed behind a black fade (`BattleDirector.prewarm_begin`).

## Data-driven design

- **Combat profiles** (`CombatProfile`): attacks, defences, specials, finisher and speed for each class.
- **Choreography** produces plain cue dictionaries that the tests check headless.
- **Board themes** (`BoardTheme`) and **environments** (`HallEnvironment.PRESETS`) are tables of parameters.
- **UI strings** come from `tools/translations_source.py` → `locale/translations.csv`.

## Future multiplayer

`ChessMatch` is authoritative and deterministic. A server can run the same core and validate moves. Clients receive `ChessMoveRecord`s and present them locally. Because battles are seeded with `presentation_seed()` (hash of the FEN before the move plus the UCI move), every client sees the same battle without syncing animation. Local cinematic length cannot change the board.
