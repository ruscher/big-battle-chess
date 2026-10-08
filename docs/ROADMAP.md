# Roadmap

Status as of v0.1.0 (2026-10-08). "Done" means implemented and verified as described in [TESTING.md](TESTING.md).

| Stage | Status | Notes |
|---|---|---|
| 1. Foundation | **Done** | Project, folder layout, main scene, input map (keyboard/mouse/gamepad), settings, tests, CI, docs |
| 2. Chess 100% functional | **Done** | All FIDE rules, perft-verified. FEN/PGN/SAN, history, undo/redo, draws, clock, saves. |
| 3. 3D medieval board | **Done** | 7 board themes, orbit camera, picking, markers, 4 environments |
| 4. Medieval characters | **Done (procedural)** | 12 original archetypes with idle/walk/run/attack/defend/death/victory. Skinned models are planned; see the character pipeline. |
| 5. First complete cinematic battle | **Done** | Every capture can play a full Epic battle with intro, duel, finisher, defeat, victory and return |
| 6. Universal combat system | **Done (v1)** | Profiles for all classes, contextual beats, finishers per class and faction, Epic/Dynamic/Quick/Classic/Skip, skip and speed-up, special titles |
| 7. Interface and AI | **Done** | Title screen, new game, settings, pause, promotion, game over, save/load, chronicle and cinematic replay, 6 AI levels, accessibility, en/pt-BR |
| 8. Graphics, environments, audio | **In progress** | Procedural art and original synthesized audio are in place. Real modelled and skinned assets, richer animation and voice acting come next. |
| 9. Performance, tests, distribution | **In progress** | Hitch fixes and pre-warm, automated tests in CI, export presets. A Windows run, low-end benchmarks and gamepad QA are still to do. |
| 10. Expansion | Planned | Online and LAN multiplayer with an authoritative server, tournaments, spectator mode, photo mode, new armies and arenas, console ports through official SDKs and partners |

## Next technical steps (priority order)

1. **Skinned characters:** a Blender pipeline and the `SkinnedCharacterRig` adapter, with the procedural rig kept as a fallback.
2. **More choreography:** class-pair special sequences (pawn vs queen reversal, queen vs rook storm), more camera shot variety, environment-reactive VFX.
3. **Photo mode** during paused battles, and a cinematic replay of selected captures.
4. **Performance:** merge procedural meshes per joint, LODs, a blob-shadow Low preset, baked noise textures, Steam Deck verification.
5. **Beginner assistance:** a hint move from the engine, and explanations of check/pin/fork in the help line.
6. **Network:** a deterministic server with the same chess core, move records over WebSocket, seeded battles on the clients.
