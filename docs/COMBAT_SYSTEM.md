# Combat and cinematic system

## Principle

A battle is **presentation only**. It starts after the capture is committed, and its outcome is fixed: the attacker always wins and the defender always falls. The defender may block, parry, dodge and counter-attack, which gives the drama of a duel, but cannot change the result. Kings are never captured. Checkmate plays a separate board scene in which the king kneels in surrender.

## Pipeline

```
ChessMoveRecord ──► request {attacker/defender type+color, mode, seed, en_passant, board_theme}
                     │
CombatChoreographer.build(request) ──► CombatTimeline (sorted cue dictionaries)
                     │
BattleDirector.play() ──► executes cues each frame in the BattleArena
```

The timeline is plain data, so it is unit-tested for every pairing in every mode: who dies, who celebrates, the duration ranges, determinism and the known cue types.

## Cue vocabulary

| Op | Effect |
|---|---|
| `anim`, `horse` | Play a pose clip on a fighter or their horse (blend, speed) |
| `move`, `place`, `face`, `spin` | Fight-space motion: axis between fighters, eased, optional jump arc |
| `camera` | Shot name and blend time (see below) |
| `vfx` | `sparks`, `impact`, `shockwave`, `dust`, `slash_arc`, `slash_burst`, `pillar`, `lightning`, `magic_burst`, `charge`, `dissolve`, `dash_trail`, `afterimage`, `golden_wave`, `aura_on/off` |
| `projectile` | Energy orb flying between anchors |
| `sfx`, `music` | Synced sound, battle/climax/victory music cues |
| `shake`, `flash`, `timescale` | Camera shake, screen flash, slow motion / hit-stop |
| `light` | Arena lighting mood: normal, charge, finisher, victory |
| `title`, `fade`, `end` | Title cards, the defender dissolving, end of battle |

Animation clips emit events (`hit`, `whoosh`, `step`, `release`, ...). The choreographer reads the event times from the pose library, so impacts, sparks and sounds land exactly on contact frames.

## Structure of a battle

- **Epic** (30–50 s):
  1. Intro: establishing orbit, close-ups, salute or power-up, matchup title.
  2. Face-off: over-the-shoulder shots and heartbeat.
  3. Approach run.
  4. Middle beats until the time budget is used.
  5. Power-up: aura, darker arena with a rim light in the faction colour, finisher name card.
  6. Finisher: slow motion at impact.
  7. Defeat: fall, then dissolve into motes.
  8. Victory pose.
- **Dynamic** (10–20 s): a shorter intro, 3–5 beats, then the climax.
- **Quick** (3–6 s): the fighters start in guard, then the finisher, defeat and a brief victory.
- **Classic:** the attacker strikes on the board itself, and the defender falls and fades.
- **Skip:** the board updates instantly.

**Middle beats** are chosen from the attacker's profile:
- exchange: an attack against block, parry, dodge or a landed hit
- counter: the defender attacks and the attacker avoids it
- dash: flash step through the opponent
- leap: jump strike with a shockwave
- blade lock
- spell volley
- cavalry charge
- ground slam

Underdog matchups such as pawn vs queen add more defender counters before the reversal.

**Finishers by class:**

| Class | Dawn | Umbral |
|---|---|---|
| Pawn | Valor Lunge | Hollow Fang |
| Knight | Thunder Charge | Nightmare Stampede |
| Bishop | Pillar of Dawn | Umbral Eclipse |
| Rook | Earthshatter | Gravequake |
| Queen | Crown of Storms | Void Tempest |
| King | Royal Verdict | Tyrant's Decree |

**Special titles:**
- Legendary Capture (pawn vs queen)
- Giant Slayer
- Storm against Fortress
- Steel against Faith
- The Fortress Strikes the Crown
- Mirror of Faith
- Clash of Crowns
- En Passant!
- Heroic Promotion
- Checkmate

## Camera shots

The shots are:
- `establish`, `wide`, `wide_low`, `side`, `track_side`
- `ots_a/ots_d` (over the shoulder)
- `low_a/low_d` (hero low angle)
- `closeup_a/closeup_d` (face, with near and far depth of field)
- `hero_a` (slow orbit)
- `orbit_close`, `dutch` (rolled), `high`, `low_mid`, `lock`
- `projectile` (follows a spell)
- `sky_a/sky_d` (looking up at leaps and pillars)
- `impact` (FOV punch-in)

Every shot is recomputed each frame from the live fighter anchors, so it tracks the action. The camera is pushed out of a cylinder around each fighter, with a larger one for mounted fighters, and kept above the floor. The choreographer never repeats the same shot twice in a row, and the side of the fight axis flips with the seed.

## Controls, accessibility and safety

- **Skip** (Space, Enter, Esc, gamepad A/B) ends the battle instantly. **Hold Shift / X** for 3× speed. A global cinematic speed is in Settings.
- Shake scales with the setting and is disabled by *reduce motion*. Flashes are attenuated by *reduce flashes*. Particle counts follow the preset and the accessibility slider.
- The director stops itself after 120 real seconds as a watchdog. The board is reconciled after every battle no matter how it ended.
- Battles are deterministic for a given move (`presentation_seed`), so replays and future online opponents see the same fight.

## Extending

- **New class or style:** add a profile in `CombatProfile.PROFILES` and, if needed, poses and clips in `PoseLibrary`.
- **New beat:** add a `_beat()` method to `CombatChoreographer` and a cue handler to `BattleDirector`. The combat tests will cover it.
- **Replace procedural animation with real animation:** `CharacterRig.play()` is the only animation entry point. See [CHARACTER_PIPELINE.md](CHARACTER_PIPELINE.md).
