# Repository Guidelines

## Project Structure & Module Organization
- `make_inventory_offline.ps1` in the repo root builds the offline inventory HTML directly from `index_by_hash.csv`.
- `tools/` hosts reusable scripts. Key folders: `tools/agents/` (automation entry-points such as `inventory-cleaner.ps1`), and data utilities like `build-hash-data.ps1`, `inventory-inject-from-csv.ps1`, and `normalize-inventory-html.ps1`.
- `docs/` stores generated artifacts (`hash_data.csv`, `inventario_interactivo_offline.html`, duplicate reports). Treat the files here as outputs; regenerate them via the agent workflows instead of manual editing.

## Build, Test, and Development Commands
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/agents/inventory-cleaner.ps1 -RepoRoot . -SweepMode None` regenerates the full inventory pipeline, including hash refresh, wrapper normalization, and sanitizing.
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/build-hash-data.ps1 -RepoRoot . -IndexPath index_by_hash.csv` rebuilds `docs/hash_data.csv` from the master index without rerunning the agent.
- `python tools/generate_duplicates_table.py --input docs/hash_data.csv --output docs/duplicate_summary.json` refreshes duplicate analytics when needed.

## Coding Style & Naming Conventions
- PowerShell: 2-space indentation, one statement per line, and functions/commands in Verb-Noun form (e.g., `Resolve-InRepo`). Prefer single quotes for literal strings and keep modules ASCII-only.
- Python: follow 4-space indentation, snake_case for variables, and keep scripts import-free unless absolutely required.
- Generated HTML or CSV content should be produced through provided scripts; do not hand-edit sanitized sections.

## Testing Guidelines
- Run the cleaner wrapper (see above) after code changes; verify the log shows non-zero rows and the final HTML summary lists drives H, I, and J.
- Use `pwsh -File tools/normalize-inventory-html.ps1 -HtmlPath docs/inventario_interactivo_offline.html` as a smoke check when touching normalization logic.
- When adjusting hash or duplicate logic, spot-check `docs/hash_data.csv` for the expected columns (`FullName`, `Hash`, `Length`, `Extension`, `Error`).

## Commit & Pull Request Guidelines
- Follow conventional commit prefixes (`feat`, `fix`, `chore`, `docs`, etc.), optionally scoped (e.g., `fix(inventory): guard __DATA__ shim`).
- Include concise descriptions of what changed and why. Reference related issues or Trello cards, and attach before/after evidence for inventory outputs when practical.
- Ensure generated artifacts that must ship (`docs/hash_data.csv`, sanitized HTML) are updated in the same commit to keep reviewers in sync.

## Security & Operational Notes
- `docs/hash_data.csv` exposes absolute paths and file sizes; avoid sharing it outside trusted collaborators.
- Sanitizing steps strip external protocols (acestream, http). Do not disable them; update the sanitizers when new protocols must be blocked.
