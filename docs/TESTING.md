# Testing

## Commands

```bash
godot --headless --path . --import                                     # once, after cloning
godot --headless --path . --script res://tests/run_tests.gd            # unit suites (~1.5 s)
godot --headless --path . --script res://tests/run_tests.gd -- --deep  # + deep perft (~3 s)
godot --headless --path . --script res://tests/run_tests.gd -- --suite=rules --verbose
godot --headless --path . res://tests/integration_test.tscn            # end-to-end (~35 s)
```

All three exit with a non-zero code on failure, and CI runs them on every push (`.github/workflows/ci.yml`).

## Suites

| Suite | What it proves |
|---|---|
| `test_perft` | Exact node counts for 7 reference positions: start, Kiwipete, CPW 3/4/4-mirror/5/6. Position and hash are fully restored after search, and the incremental Zobrist hash matches a full recompute. |
| `test_rules` | FEN round trip and validation, illegal moves and pins, check evasion, every castling restriction, en passant (including the horizontal-pin case), promotion and underpromotion, checkmate/stalemate, insufficient material, 3/5-fold repetition, 50/75-move rules, resign/draw offers/timeouts, undo/redo, SAN disambiguation, PGN round trip with comments/variations/NAGs, save round trip with tamper rejection, clock. |
| `test_ai` | Finds mate in 1 and mate in 2, wins a hanging queen, saves an attacked queen, respects time limits, returns only legal moves. |
| `test_combat` | For all 30 capturable matchups × 3 arena modes × 3 seeds: only the defender dies (exactly once), the attacker celebrates after the fall, only the defender fades, the timeline ends. Also: durations within each mode's range, determinism per seed, matchups producing different battles, only known cue types, sorted cues. |
| `integration_test.tscn` (imported characters) | When local assets exist, each imported archetype is checked: it uses `SkinnedCharacterRig`, finds its skeleton, maps all 17 joints, moves its bones when an attack clip plays, and resolves the weapon tip and height. The procedural fallback is used when imported characters are disabled, and promotion swaps the pawn model for the promoted piece's model. |
| `integration_test.tscn` | Boots the real game scene. Plays moves through the click entry point: an opening with en passant and castling, illegal clicks, undo/redo, save/load, Quick arena battles including a mid-battle skip, Classic strikes, the promotion dialog with underpromotion, fool's mate with the checkmate scene, AI reply and undo vs AI. After every step the visual board must match the logical position exactly, with no duplicate or missing rigs. |

## Latest results (2026-10-08, Godot 4.7.2, BigLinux, RX 9060 XT)

```
test_ai          6 tests      9 checks   OK
test_combat      5 tests   2981 checks   OK   (epic 35-50 s, dynamic 14-23 s, quick 4-5 s)
test_perft       2 tests   2076 checks   OK   (--deep)
test_rules      16 tests     95 checks   OK
integration     339 checks, 0 failures, 34 s  (with imported Pawn/Bishop/Rook/King)
```

## Manual and visual verification done

- The title screen, all 4 environments and several board themes were rendered and inspected through screenshots (`--shots`).
- Full Epic, Dynamic and Quick battles were captured frame by frame (knight vs pawn, queen vs rook, knight vs bishop, bishop vs pawn).
- An AI vs AI match was played automatically with Quick battles: 18 plies, 5 arena captures, no errors.

## Automation options

These options of the main scene are used for captures and soak tests. They are session-only and never saved:

```
--autostart=pve|pvp|ai_vs_ai --ai-level=0..5 --cinematic=epic|dynamic|quick|classic|skip
--board=N --env=N --clicks=e2,e4 --preset=0..4 --novsync --log-hitches
--demo-battle=knight,pawn,epic --attacker-color=0|1 --seed=N
--shots=1,3,5 --shot-dir=/path --quit-after=SECONDS
--resolution=1920x1080 --procedural-characters --intro --no-intro
```

Character gallery (visual review of imported and procedural characters):

```
godot --path . --script res://tools/character_gallery.gd -- --out=/tmp/g.png [--types=1,3,4,6] [--clips=idle,slash] [--time=0.4] [--procedural] [--view=close]
```

## Not yet automated

- Gamepad navigation and resolution/UI-scale sweeps (checked manually only).
- Windows runtime (export configured; CI builds it, but it has not been run on Windows).
- Long soak tests of full AI vs AI games in Epic mode.
