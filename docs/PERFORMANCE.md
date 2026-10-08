# Performance

## Measurements

The measurements below come from the game's own frame statistics (`--quit-after` prints the average FPS, worst frame and VRAM).

**Test machine:** AMD Radeon RX 9060 XT (Mesa RADV, Vulkan 1.4), 16 threads, BigLinux. Window 1600×900, Epic battle (queen vs rook), V-Sync off.

| Preset | Average FPS (battle) | VRAM |
|---|---|---|
| High | ~231 | ~480 MB |
| Cinematic (SDFGI, SSIL, MSAA 8x) | ~204–218 | ~1.27 GB |
| Title screen, High (V-Sync on) | capped at refresh (~160) | ~410 MB |

**Frame-time spikes:**
- *Before the fix:* 25–40 ms spikes every time sparks, lightning or an aura spawned. Each spawn created a fresh `StandardMaterial3D` for streak particles.
- *After the fix:* streak and aura materials are cached, and battle shaders are pre-warmed at boot. Battles at High run with **no frame above 28 ms**. One ~35 ms frame remains at the arena-to-board switch, hidden behind the fade.

These are measured on one machine only. The 60 FPS and 30 FPS targets for mid-range and low-end hardware still need real benchmarks on that hardware (Steam Deck, integrated GPUs).

## Imported characters (2026-10-08)

Measured on the same machine at 1920×1080 windowed with V-Sync off (`--resolution=1920x1080 --novsync --preset=N`). The scene is a full board of 32 pieces in the Royal Hall; 26 pieces use imported, skinned models (Pawn, Bishop, Rook, King).

| Configuration | Average FPS | Worst frame | VRAM |
|---|---|---|---|
| Procedural characters, High | 154 | 9.9 ms | 500 MB |
| Imported characters, High, first version (uncompressed textures, full-rate retarget) | 128 | 15.5 ms | 764 MB* |
| **Imported characters, High, optimised** | **184** | 8.6 ms | 764 MB |
| Imported characters, Cinematic | 126 | 12.4 ms | 1.63 GB |
| Epic battle (King vs Rook, arena LOD 90k/78k), High | 112–115 | loading frame excluded | 1.62 GB |
| Owner's settings: Cinematic, 3440×1440 fullscreen | ~75 | — | 2.5 GB |

\* Before `tools/configure_character_imports.py`, Godot imported the glTF textures as lossless with no mipmaps (2.7 GB at 3440×1440).

Optimisations applied:
- **Textures:** VRAM-compressed textures with mipmaps; normal maps flagged; ORM maps capped at 2K.
- **Retarget cost:** fell from 1.76 to 0.46 ms/frame. The bone and joint evaluation order is precomputed into flat arrays, joint bases are accumulated top-down, and idles on the board update at half rate on alternating frames.
- **LODs:**
  - board LOD 18–30k triangles per model;
  - arena LOD 50–90k triangles;
  - Godot also auto-generates mesh LODs on import.
- **Shared resources:** one PackedScene per glTF file, shared by archetypes that use the same model (Pawn/Bishop), and faction materials cached per source material, army and archetype.

Imported characters are faster than the procedural ones because each procedural warrior is about 70 mesh instances (draw calls), while each skinned model has 1–40 surfaces.

## Techniques in use

- **Shared resources:** one mesh and one material per part type for all 32 pieces (`MaterialLibrary`).
- **Arena isolation:** its own render layer, lights and environment. It is hidden (zero cost) outside battles.
- **Pre-warm:** every fighter archetype and VFX type is rendered once behind the loading fade.
- **No physics for picking:** analytic ray tests against piece cylinders, then the board plane.
- **Threaded AI:** the search never blocks the main thread, and it overlaps with cinematics.
- **Particle budget:** scaled by preset and the accessibility slider. VFX free themselves after their lifetime.
- **Presets** (`GraphicsQuality`): only features Godot 4.7 actually provides (SSAO, SSIL, SSR, SDFGI, volumetric fog, TAA/MSAA/FXAA, FSR 1/2 scaling, shadow atlas and filter quality).
- **Audio:** OGG Vorbis, about 4 MB total, with a pooled set of 20 voices.

## Known costs and next steps

- Each procedural character is about 60–90 mesh instances. That is fine on desktop, but for handheld devices merge the static parts of each rig into one `ArrayMesh` per joint to cut draw calls by about 5×.
- Add LODs (`mesh_lod_threshold` already scales per preset) and impostor shadows (blob decals) for the Low preset.
- The `NoiseTexture2D` normal maps generate at load. Bake them to PNG for faster startup.
- Profile with Godot's profiler and visual profiler, RenderDoc, and MangoHud on Steam Deck.
