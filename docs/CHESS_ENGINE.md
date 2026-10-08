# Chess engine and AI

## Representation

- **Piece:** `type | color << 3`, with type 1..6 = P N B R Q K; 0 means empty.
- **Square:** `rank * 8 + file`, so a1 = 0 and h8 = 63.
- **Move:** packed integer `from | to << 6 | promo << 12 | flags << 15`. The flags are capture, double push, en passant, castle and promotion.
- **Move generation:** a 10×12 mailbox, so off-board detection is a single table lookup.
- **Legality:** each pseudo-legal move is made, checked for "own king attacked?", then unmade. `make_move()` returns `false` and restores the position when the move is illegal.
- **Hashing:** incremental Zobrist (pieces, side, castling rights, and the en passant file only when a capture is actually possible, as FIDE repetition requires). Tests compare the incremental hash against a full recompute.

## Rules (`ChessMatch`)

| Rule | Behaviour |
|---|---|
| Checkmate / stalemate | Automatic |
| Insufficient material | Automatic: K vs K, K+minor vs K, bishops all on one square colour |
| Threefold repetition | Claimable ("Claim draw" button) |
| Fivefold repetition | Automatic |
| 50-move rule | Claimable |
| 75-move rule | Automatic (checkmate takes precedence) |
| Draw offer | Pending until the opponent accepts or moves |
| Flag fall | Loss, or a draw if the opponent has no mating material (FIDE 6.9) |

Saves and PGN imports are replayed move by move through the legality checks, so a tampered file cannot produce an illegal position.

## AI (`ChessSearch`, `ChessEvaluator`, `ChessAIPlayer`)

**Search:**
- Iterative-deepening negamax with alpha-beta and PVS.
- Transposition table (packed into a 64-bit integer per entry) and quiescence search on captures and promotions, with delta pruning.
- Null-move pruning (disabled when only pawns remain), late move reductions, check extension and mate-distance pruning.
- Move ordering: TT move, then MVV-LVA, then killers and history.

**Evaluation:**
- Tapered between middlegame and endgame.
- Hand-written piece-square tables, bishop pair, doubled and isolated pawns, passed pawns by rank, rooks on open files, king pawn shield and tempo.

**Threading:** the search runs on a `Thread` against a cloned position. Results from cancelled or stale requests are dropped by request id. `cancel()` stops the search and joins the thread.

**Levels:**

| Level | Behaviour |
|---|---|
| Beginner | Depth 1 with noise and frequent slips. A deliberate, documented handicap. |
| Casual | Depth 2 with smaller noise |
| Intermediate | Depth 4, 1.2 s |
| Advanced | Depth 6, 2.5 s |
| Expert | Iterative deepening, 5 s |
| Grandmaster | Stockfish over UCI if installed (`/usr/bin/stockfish`, etc.); otherwise the built-in engine with 8 s |

Stockfish is GPLv3 and is never bundled. It is only launched as an external process if the player already has it.

Measured on a Ryzen + RX 9060 XT desktop (GDScript): about 150k perft nodes/s and about 20k search nodes/s. The start position reaches depth 6 in 0.4 s thanks to pruning.

## Tests

`tests/suites/test_perft.gd` checks these positions against the published counts:
- start position
- Kiwipete
- CPW positions 3, 4 (and its mirror), 5 and 6

Use `-- --deep` for the deeper counts, for example 197,281 nodes at depth 4 from the start. `test_rules.gd` covers every special rule, notation, PGN, undo/redo, save round-trips and the clock.
