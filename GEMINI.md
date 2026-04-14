# Project Context: Anti-Blunder Chess

## 🎯 Project Overview
This is a Flutter-based chess application designed as a learning tool. Its flagship feature is an "Anti-Blunder Shield" that intercepts user moves, silently evaluates them using a local Stockfish engine, and rejects the move if it drops the evaluation score below a specific threshold (e.g., blundering a piece). The user plays against local bots of varying ELOs.

## 🛠 Tech Stack
* **Framework:** Flutter (Dart)
* **State Management & DI:** Riverpod (`flutter_riverpod`)
* **Chess UI:** `flutter_chess_board`
* **Chess Logic (Pure Dart):** `chess` (Used for FEN manipulation and legal move generation)
* **Chess Engine:** `stockfish` (FFI wrapper for local C++ Stockfish engine)

## 🏗 Architecture Rules: Clean Architecture (Feature-First)
The project is strictly structured using Clean Architecture to keep the asynchronous engine logic decoupled from the UI.

* **Folder Structure:** `/lib/features/<feature_name>/<layer>/...`
* **Domain Layer (`/domain`):** Contains pure Dart code ONLY. No Flutter dependencies. Holds Entities, Repository Interfaces, and Use Cases (e.g., `AttemptMoveUseCase`).
* **Data Layer (`/data`):** Implements domain interfaces. Handles the raw `stockfish` FFI streams, parses complex UCI text output, and returns clean Dart objects.
* **Presentation Layer (`/presentation`):** UI is "dumb." It only listens to Riverpod state changes and fires events.

## 🧠 Core Domain Logic Constraints
1. **The Anti-Blunder Shield:**
    * **FEN-Based Evaluation:** Never extract Algebraic Notation (SAN) from the UI to pass to the engine. Instead, generate the hypothetical new FEN, pass both the old FEN and new FEN to the engine via `AttemptMoveUseCase`, and compare the evaluation scores.
    * **Evaluation Logic:** Evaluation math must account for perspective. UCI engines return scores relative to the side whose turn it is. The blunder delta is calculated as `delta = -newEval - currentEval`. A drop of `> 300` centipawns triggers a `MoveResult.blunder`.
2. **Engine Communication:**
    * **Stockfish State Management:** Always wait for the Stockfish engine to reach `StockfishState.ready` before sending UCI commands.
    * **Engine Synchronization:** Use `isready` / `readyok` handshakes between major commands (e.g., after `position fen ...` and before `go ...`).
    * **Hash Management:** Always send `ucinewgame` and sync before starting an evaluation or search. This wipes the transposition tables and prevents evaluation bleeding/hash collisions between back-to-back searches.
    * **Search Completion:** Always wait for the `bestmove` signal to complete a search.
    * **Difficulty Scaling:** Map human Elo to Stockfish's `Skill Level` (0-20) as the native `Elo` parameter can be unstable in some FFI builds. Use `Skill Level = ((elo - 800) / 100).clamp(0, 20)`.
3. **Multi-Platform Compatibility:**
    * **Conditional Imports:** Use `dart.library.js_interop` to toggle between `native_engine_repository.dart` (FFI) and `web_engine_repository.dart` (Mock/WASM) for Chrome support.
    * **Web Mock Strength:** The web repository uses randomization to pick legal moves, preventing predictable play.

## 🧑‍💻 Coding Standards
* **DRY & SOLID:** Ensure Single Responsibility. UI does not talk to the engine directly.
* **File Naming:** Strictly `snake_case.dart` for all files.
* **Widgets:** Use `super.key` in constructors (Dart 2.17+ standard).
* **Riverpod:** For projects using Riverpod 3.0+, use `import 'package:flutter_riverpod/legacy.dart';` when using `StateNotifier` and `StateNotifierProvider`.
* **State Updates:** State classes must be immutable. Use `.copyWith()` for updates inside Notifiers.
* **UI Layout:** Use fixed-size constraints for the `ChessBoard`. **NEVER** wrap the `ChessBoard` in a `SingleChildScrollView`.
* **UI-State Syncing:** Avoid using `loadFen()` for routine board updates. Use `makeMove()` or `makeMoveWithPromotion()` for bot moves.
* **Feature Limitation:** `flutter_chess_board` does not support an `onPieceTap` listener; therefore, visual legal-move dots are not supported with the current UI package.
* **Error Resilience:** Wrap asynchronous engine calls in `try-catch` blocks.
