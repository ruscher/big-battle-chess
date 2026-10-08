# Character pipeline

Big Battle Chess renders each piece with one of two kinds of rig, both behind the same `CharacterRig` contract. The contract is used by the board, the move presenter and the battle director.

| Rig | Source | When it is used |
|---|---|---|
| `SkinnedCharacterRig` | Imported, PBR-textured, skinned glTF models built locally from third-party sources with Blender | When `assets/characters_ext/<archetype>/` exists |
| `CharacterRig` | Procedural articulated warriors made of primitives (original) | Fallback when imported assets are missing, plus the Queen and the Knight (no suitable asset yet) |

`CharacterLibrary.create(type, color, context)` chooses the rig. Here `context` is `"board"` (light LOD) or `"arena"` (detailed LOD). The game always runs: a fresh clone without the local assets plays entirely with procedural characters.

## Source models (status 2026-10-08)

| Model (in `personagens/`) | Use | State | Work done |
|---|---|---|---|
| Iron Juggernaut | **Rook** | Rigged by its author (UE-style 88-bone skeleton), LowPoly 30k / MidPoly 78k tris, 2×2K PBR tile sets | Unity textures converted to glTF ORM. Scale normalised. Board/arena LODs from the author's Low/Mid meshes. Its bundled Epic mannequin animations and body (`PaintWeightMale`, MM_/MF_ actions) are **not used**. |
| Dark Fantasy Sun Knight Warrior | **King** | One sculpted shell, 792k tris, no rig, 2K PBR JPEGs | Decimated to 24k (board) / 90k (arena). Original skeleton. Skinned with weight smoothing. Sword detached from the robe. Halo bound to the head. Restrained regal motion. |
| Medieval Knight Warrior | **Bishop** (war-cleric with halo) and **Pawn** | 50k tris in 1,868 separate pieces, no rig, 4K PBR | Original skeleton. Island-aware skinning (rigid plates, rigid sword and shield, cape on the torso). LOD 18k/50k. Two looks driven by heraldry recolouring and scale. |
| Warrior Woman | — (rejected) | 8.85M tris, 920 pieces, a whole C4D scene, no rig, procedural C4D materials, DAZ "V6 Anna" textures, sci-fi/body-suit design | Not game-ready, and it conflicts with the brief (medieval, practical armour, no sexualisation). There is also a licence risk (DAZ-derived). **Queen stays procedural** until a suitable asset exists. |
| — | **Knight** | No horse asset available | **Procedural horse and rider remain**. A rigged horse model is required (see Roadmap). |

## Build steps (reproducible)

```bash
# 1. Working copies (never modify personagens/): extract archives into build/asset_work/
#    (see tools/blender/build_characters.py header for the expected layout)
# 2. Audit and previews
blender -b --factory-startup --python tools/blender/audit_model.py -- <model> <report.json>
blender -b --factory-startup --python tools/blender/render_preview.py -- <model> <out_prefix> eevee 700
blender -b --factory-startup --python tools/blender/landmark_views.py -- <model> <out_prefix> <face_fix_deg> <height>
# 3. Build archetypes (glTF + shared textures -> assets/characters_ext/, editable .blend -> build/character_blend/)
blender -b --factory-startup --python tools/blender/build_characters.py -- rook king warrior
# 4. Godot import settings (VRAM compression + mipmaps) and re-import
python3 tools/configure_character_imports.py
# 5. Visual review in the engine
godot --path . --script res://tools/character_gallery.gd -- --out=/tmp/g.png --types=6 --clips=idle,slash,overhead --time=0.4
```

What `build_characters.py` does:

1. **Normalise:** rotate so the model faces −Y (which is +Z in Godot), scale to real height, put the feet at z = 0 and centre the model.
2. **Decimate** to per-context triangle budgets (collapse, UVs preserved).
3. **Materials:** a Principled BSDF with base colour, normal and packed ORM (R = AO, G = roughness, B = metallic), exported 1:1 to glTF. Textures are written once and shared by both LODs.
4. **Skeleton** (unrigged models): an original 19-bone humanoid (`pelvis, spine_01, spine_02, neck, head, clavicle_*, upperarm_*, lowerarm_*, hand_*, thigh_*, calf_*, foot_*`). It is placed from landmarks measured on orthographic grid renders and on vertex-slice centrelines. Sword axes are fitted by PCA on the blade vertices.
5. **Skinning** (`skin()`):
   - inverse distance to the bone segments, normalised by limb thickness;
   - side restrictions, so nothing is pulled from the opposite side;
   - per-bone reach cutoffs, so drapery near a limb does not follow it;
   - optional Laplacian weight smoothing;
   - small mesh islands moved rigidly (armour plates);
   - override regions: capsules or boxes, applied by island majority or per vertex, rigid or as a height gradient for capes;
   - `detach_below` cuts contact bridges between a prop and the body (for example a sword tip resting on a robe in a single sculpted shell).
6. **Validation:** test-pose renders (arm raised, leg forward, torso twisted) in `build/asset_work/previews/<name>_posetest_*.png`.
7. **Export:** glTF (separate) with the skin and no animations.

## Animation: one clip library, any skeleton

The authored clip library (`PoseLibrary` / `PoseAnimator`) drives the procedural rig and the imported rigs alike. That library includes idle, guard, walk/run, six attacks and a combo, cast, block, parry, dodge, hit, stagger, death, victory, power-up, jump, land strike and surrender, with timed `hit`/`step`/`release` events.

`SkinnedCharacterRig` animates an invisible joint rig with that library. Every frame it retargets the joints onto the model's `Skeleton3D`:

```text
posed_global(bone) = delta(joint) · limb_fix(bone) · rest_global(bone)
```

- **`delta`:** the joint's rotation away from its identity rest, expressed in skeleton space.
- **`limb_fix`:** brings A/T-pose limbs to the "arms down" rest the clips assume.
- **Unmapped bones** (twists, fingers, clavicles) keep their rest pose and follow their parents.
- **Pelvis translation** carries crouches and lunges. The procedural `base` joint (falls) moves the whole model.
- **`joint_scale`:** per-archetype attenuation, for example a shield strapped along the forearm keeps it upright, and the King moves with a restrained, regal range.

Impact events, slow motion, skip and speed-up keep working unchanged in battles.

## Faction identity on shared textures

Both armies use the same texture set. `shaders/faction_pbr.gdshader` re-tones metal using the metallic map, with a remappable mask range for weak maps. It recolours fabric by luminance, which keeps weave, folds and dirt. It replaces saturated heraldic accents by hue in sRGB, for example the crusader cross becomes royal blue or gold for Dawn and crimson or violet for Umbral. It also adds a readability rim. The per-archetype looks live in `CharacterLibrary.ARCHETYPES[*].look`.

## Known limitations

- **Queen and Knight:** still procedural. They need a female armoured model and a rigged horse with usable licences.
- **King:** some cloth/arm shearing remains in extreme poses, because it is a single sculpted shell. A manual weight-painting pass in Blender (`build/character_blend/king_work.blend`) would finish it.
- **Pawn and Bishop:** they share one model, distinguished by heraldry colours, scale and the bishop's halo. Distinct helmets or weapons need modelling work.
- **No cloth simulation:** capes are skinned to the torso.
