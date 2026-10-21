# Complete Reverse-Engineered Chess.com Architecture & Features Index

This directory contains deep architectural and reverse-engineered feature specifications extracted from Chess.com's client bundles, DevTools sources, Web Workers, and backend telemetry protocols captured during interactive inspection.

---

## Master Feature Catalog

| # | Feature Domain | Specification Document | Key Capabilities & Architecture |
|---|---|---|---|
| 1 | **Opening Explorer & W/D/L Stats** | [opening_explorer_master_games_wdl_stats.md](file:///Users/jonathanarndt/dev/chess_teacher/docs/features/chesscom_reference/opening_explorer_master_games_wdl_stats.md) | Tri-color Win/Loss/Draw bars, move frequency math, master games search, rating range filter (0–4000+), Chessable course recommendation link. |
| 2 | **Multi-PV Engine & Null-Move Threats** | [multipv_engine_lines_nullmove_threats_preview_board.md](file:///Users/jonathanarndt/dev/chess_teacher/docs/features/chesscom_reference/multipv_engine_lines_nullmove_threats_preview_board.md) | 1–5 Multi-PV lines, hover mini-board preview via pure CSS multi-background sprites, null-move threat pass, SVG knight L-shape geometry math. |
| 3 | **Analysis App & Collaborative Rooms** | [analysis_board_layout_archive_pgn_import_rooms.md](file:///Users/jonathanarndt/dev/chess_teacher/docs/features/chesscom_reference/analysis_board_layout_archive_pgn_import_rooms.md) | 27-extension dependency injection pipeline, smart PGN/FEN/Study-URL input, board editor castling bitmask, collaborative Analysis Room state machine. |
| 4 | **Stockfish 19 WASM & 8px Snapping** | [stockfish_19_wasm_engine_and_board_layout.md](file:///Users/jonathanarndt/dev/chess_teacher/docs/features/chesscom_reference/stockfish_19_wasm_engine_and_board_layout.md) | Pthreads multi-threading with Web Workers vs. single-threaded Asyncify fallback, NNUE network streaming with ETA telemetry, 8px CSS `round()` grid layout, 3-tier bot crowns. |
| 5 | **Resizable Board & 8px Grid** | [resizable_board_8px_grid.md](file:///Users/jonathanarndt/dev/chess_teacher/docs/features/done/resizable_board_8px_grid.md) | Dynamic integer-pixel snapping, mouse drag handle, RTL mirroring, responsive viewport breakpoints. |
| 6 | **Chess Clocks & Time Controls** | [chess_clocks_time_controls.md](file:///Users/jonathanarndt/dev/chess_teacher/docs/features/done/chess_clocks_time_controls.md) | Millisecond timer accuracy, low-time warning pulsation, Fischer & Bronstein time increment formulas. |
| 7 | **Move Feedback & Classifications** | [move_feedback_eval_openings.md](file:///Users/jonathanarndt/dev/chess_teacher/docs/features/done/move_feedback_eval_openings.md) | Brilliant, Great, Best, Book, Mistake, Miss, and Blunder move classifications with coach commentary. |
| 8 | **Bot Crowns & Player Events** | [bot_crowns_play_side_events.md](file:///Users/jonathanarndt/dev/chess_teacher/docs/features/done/bot_crowns_play_side_events.md) | 3-crown progression system based on hint/undo usage, side selection (White, Black, Random), rematch flow. |
| 9 | **Material Imbalance & Captured Pieces** | [captured_pieces_material_imbalance.md](file:///Users/jonathanarndt/dev/chess_teacher/docs/features/done/captured_pieces_material_imbalance.md) | Material point difference computation (`+1`, `+3`, etc.), compact piece visual grouping, responsive vertical alignment. |
| 10 | **Real-Time PubSub Telemetry** | [realtime_pubsub_telemetry_architecture.md](file:///Users/jonathanarndt/dev/chess_teacher/docs/features/chesscom_reference/realtime_pubsub_telemetry_architecture.md) | WebSocket presence tracking, Bugtivity error instrumentation, Sentry debug IDs, Protobuf gRPC wire format. |
| 11 | **Board & Piece Themes Registry** | [board_piece_themes_registry.md](file:///Users/jonathanarndt/dev/chess_teacher/docs/features/chesscom_reference/board_piece_themes_registry.md) | 30+ piece set textures (Neo, Wood, 3D, Club), CSS custom properties fallback chains, coordinate font sets. |
| 12 | **Board VFX Animations & SVG Badges** | [board_vfx_animations_svg_badges.md](file:///Users/jonathanarndt/dev/chess_teacher/docs/features/chesscom_reference/board_vfx_animations_svg_badges.md) | Piece movement tweening, capture burst animations, check highlight glow, custom SVG move rating badges. |
| 13 | **Chessboard Engine & Premoves** | [chessboard_engine_premoves_variations.md](file:///Users/jonathanarndt/dev/chess_teacher/docs/features/chesscom_reference/chessboard_engine_premoves_variations.md) | Client-side move validation, premove queueing with cancel triggers, variation tree branching and promotion picker. |
| 14 | **Cloudflare Turnstile Antibot** | [cloudflare_turnstile_antibot_internals.md](file:///Users/jonathanarndt/dev/chess_teacher/docs/features/chesscom_reference/cloudflare_turnstile_antibot_internals.md) | Turnstile challenge orchestration, fingerprint hashing, stealth verification triggers on bot challenges. |
| 15 | **Evaluation Bar & WDL Complexity** | [evaluation_bar_wdl_complexity_modes.md](file:///Users/jonathanarndt/dev/chess_teacher/docs/features/evaluation_bar_wdl_complexity_modes.md) | Non-linear sigmoid evaluation curve, mate-in-N height calculation, Win/Draw/Loss horizontal bar, game complexity index. |
| 16 | **Easter Eggs & Chessboxing Fidgets** | [board_easter_eggs_slam_chessboxing_fidgets.md](file:///Users/jonathanarndt/dev/chess_teacher/docs/features/chesscom_reference/board_easter_eggs_slam_chessboxing_fidgets.md) | Piece slamming sound physics, chessboxing mode, piece fidget spinner mode, secret keyboard shortcuts. |
| 17 | **Komodo TEP & Skills Engine** | [komodo_tep_explanation_engine_and_skills.md](file:///Users/jonathanarndt/dev/chess_teacher/docs/features/chesscom_reference/komodo_tep_explanation_engine_and_skills.md) | Komodo Teacher Evaluation Protocol, plain-English move explanations, tactile skill points progression, Rive viseme lip-sync. |
| 18 | **Bot Groups, Personalities & Audio** | [bot_groups_personalities_and_speech_system.md](file:///Users/jonathanarndt/dev/chess_teacher/docs/features/chesscom_reference/bot_groups_personalities_and_speech_system.md) | 100+ bot personalities grouped by tier, opening book preferences, contextual taunts/encouragement audio system. |
| 19 | **Game Over Modal & Game Review Narratives** | [game_over_modal_and_game_review_narratives.md](file:///Users/jonathanarndt/dev/chess_teacher/docs/features/chesscom_reference/game_over_modal_and_game_review_narratives.md) | Automated post-game recap narratives, game review summary metrics, accuracy CAPS scores, rematch modals. |

---

## Architectural Relevance to Anti-Blunder Chess

These reverse-engineered documents directly inform our Flutter implementation of Anti-Blunder Chess:
1. **Engine Shield Math:** Evaluates moves via the sigmoid centipawn curves detailed in [evaluation_bar_wdl_complexity_modes.md](file:///Users/jonathanarndt/dev/chess_teacher/docs/features/evaluation_bar_wdl_complexity_modes.md).
2. **Move Classification:** Distinguishes normal moves from tactical blunders (`delta > 300 cp`) detailed in [move_feedback_eval_openings.md](file:///Users/jonathanarndt/dev/chess_teacher/docs/features/done/move_feedback_eval_openings.md).
3. **Engine Worker Interop:** Models our FFI Stockfish command loop after the synchronization and threading patterns detailed in [stockfish_19_wasm_engine_and_board_layout.md](file:///Users/jonathanarndt/dev/chess_teacher/docs/features/chesscom_reference/stockfish_19_wasm_engine_and_board_layout.md).
4. **Threat Detection:** Adopts the null-move threat pass approach detailed in [multipv_engine_lines_nullmove_threats_preview_board.md](file:///Users/jonathanarndt/dev/chess_teacher/docs/features/chesscom_reference/multipv_engine_lines_nullmove_threats_preview_board.md).
