# Character pipeline

## Current state: procedural, original warriors

There is no rigged medieval character set whose license allows commercial redistribution in a public repository at game-ready poly counts (see [ASSET_LICENSES.md](ASSET_LICENSES.md)). Blender is also not installed on the development machine. So the first playable version builds its warriors procedurally in Godot:

- `CharacterRig` creates an articulated hierarchy:
  - `base → hips → spine → chest → neck → head`
  - arms: `shoulder → elbow → hand`
  - legs: `thigh → knee → foot`
- Plate armour is assembled from shared primitive meshes (`MaterialLibrary` caches every mesh and material across all 32 pieces):
  - breastplate, pauldrons with trim, couters, vambraces, gauntlets
  - faulds or robes, cuisses, poleyns with fans, greaves, sabatons
- Each class has its own helmet, weapon and shield (`GearBuilder`): sallet or hood, tower helm, winged or horned helm, mitre, queen's mask and tiara, crown.
- Capes, veils, tabards and horse caparisons use a wind-driven cloth shader.
- Heraldry is procedural (`emblem.gdshader`): the Dawn sun and the Umbral crescent-eye.
- Knights ride a `HorseRig`. Locomotion clips go to the horse, while the rider keeps a riding stance (`PoseAnimator.overrides`) and animates only the upper body in combat.
- Shields follow the left forearm but face the torso's front, a light IK substitute that reads clearly in every pose.

**Animation** (`PoseAnimator` + `PoseLibrary`):
- About 45 authored poses and 30 clips, including idle, guard, walk/run cycles, six attacks and a combo, cast, block, parry, dodge, hit, stagger, death/fall, victory, salute, power-up, jump, land strike and surrender. Horses have stand, walk, gallop, rear and fall.
- Segments are eased, every clip cross-fades from the current pose, and there is procedural breathing and sway.
- Timed events (`hit`, `step`, `release`...) drive sound and VFX.
- A time scale per animator enables slow motion and speed-up.

## Path to imported, skinned characters

The rest of the game only talks to `CharacterRig` through a small API:

```
build(type, color), play(clip, blend, speed), play_horse(clip), set_time_scale(s),
set_fade(k), weapon_tip(), chest_position(), head_position(), height(), anim_event signal
```

To swap in real models:

1. Model and rig in Blender, Humanoid bone naming, retarget-friendly. Export glTF 2.0 (`.glb`) per archetype and faction, with modular weapons as separate meshes attached to a `BoneAttachment3D`.
2. Import into `assets/characters/<faction>/<class>.glb`. In the import dock use a `BoneMap` with the `SkeletonProfileHumanoid` profile, so one animation library can be shared and retargeted across all 12 archetypes.
3. Author clips with the **same names** as `PoseLibrary` (`slash`, `block`, `death`...) and add **method or marker tracks** that emit the same events (`hit`, `whoosh`, `step`, `release`).
4. Implement a `SkinnedCharacterRig` with the same API using `AnimationTree` (a blend tree for locomotion, a state machine for actions). Choose it in `BoardView.create_piece_rig` and `BattleDirector._spawn` when the asset exists, and fall back to the procedural rig otherwise. The game must keep running without optional assets.
5. Record the author, URL and license of every external asset in `ASSET_LICENSES.md`.

Budget guidance:
- About 8–15k triangles per board character with LODs, about 30–40k for arena close-ups.
- 2k PBR textures (ORM packed). Compress with VRAM-compressed BPTC/S3TC on desktop.
