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
