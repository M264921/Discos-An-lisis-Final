# Repository Guidelines

## Project Structure & Module Organization
The root hosts inventory inputs produced by drives (e.g., `index_by_hash.csv`, `inventory_by_folder.csv`) plus orchestrator scripts like `make_inventory_offline.ps1`. Reusable automation lives under `tools/`; `tools/agents/` houses entry-point wrappers (`inventory-cleaner.ps1`), while sibling scripts such as `build-hash-data.ps1`, `inventory-inject-from-csv.ps1`, and `normalize-inventory-html.ps1` implement discrete data steps. Generated artifacts such as `docs/hash_data.csv`, `docs/inventario_interactivo_offline.html`, and duplicate dashboards reside in `docs/`. Treat any file under `docs/` as read-only outputs and regenerate them through the described flows.

## Build, Test, and Development Commands
Run `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/agents/inventory-cleaner.ps1 -RepoRoot . -SweepMode None` to execute the full pipeline: hash refresh, HTML normalization, sanitization, and final offline bundle. Use `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/build-hash-data.ps1 -RepoRoot . -IndexPath index_by_hash.csv` when you only need to refresh `docs/hash_data.csv`. Regenerate duplicate analytics with `python tools/generate_duplicates_table.py --input docs/hash_data.csv --output docs/duplicate_summary.json`.

## Coding Style & Naming Conventions
PowerShell scripts use 2-space indentation, Verb-Noun command names (`Resolve-InRepo`), and single quotes for literal strings; keep modules ASCII-only. Python utilities follow 4-space indentation, snake_case identifiers, and stay self-contained without external imports. Never edit sanitized HTML or CSV by hand; pipe changes through the provided scripts.

## Testing Guidelines
After any pipeline change, rerun the cleaner wrapper and review its log for non-zero row counts and the H/I/J drive summary in the generated HTML. When altering normalization logic, perform `pwsh -File tools/normalize-inventory-html.ps1 -HtmlPath docs/inventario_interactivo_offline.html` as a smoke test. For hash or duplicate adjustments, inspect `docs/hash_data.csv` to confirm the expected columns (`FullName`, `Hash`, `Length`, `Extension`, `Error`) and spot-check representative records.

## Commit & Pull Request Guidelines
Adopt conventional commit prefixes (`feat`, `fix`, `chore`, `docs`) with optional scopes such as `fix(inventory): guard __DATA__ shim`. PRs should summarize changes, link related Trello cards or issues, and attach before/after evidence when HTML or CSV outputs shift. Commit regenerated artifacts alongside code changes to keep reviewers synchronized.

## Security & Operational Notes
`docs/hash_data.csv` contains absolute paths and file sizes; share it only with trusted collaborators. Sanitizers intentionally strip external protocols (acestream, http). Extend the blocklist rather than disabling these guards when new protocols appear.
