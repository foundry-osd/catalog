You must speak and write code exclusively in English.

General behavior:
- Be concise, direct, and pragmatic
- Prefer implementation over long explanations
- Do not explain obvious things
- Avoid overengineering
- Follow the existing repository structure and conventions

Repository scope:
- This repository is a PowerShell catalog automation repository for Foundry
- It is not a .NET, WPF, or WinUI application repository
- Keep changes focused on catalog generators, schemas, helpers, workflow files, or generated cache outputs directly related to the task

PowerShell rules:
- Use PowerShell 7-compatible code
- Use `[CmdletBinding()]`, validated parameters, `Set-StrictMode -Version Latest`, and `$ErrorActionPreference = 'Stop'` in scripts
- Use clear PowerShell `Verb-Noun` function names
- Keep functions small and focused
- Reuse `Helpers/FoundryHelpers.psm1` before adding duplicate helper logic
- Prefer structured XML APIs and `XmlWriter` for catalog output
- Avoid ad hoc string manipulation for XML, paths, or structured data when a proper API is available

Catalog output rules:
- Catalog outputs are XML-only unless explicitly requested otherwise
- Preserve UTF-8 without BOM, CRLF line endings, two-space XML indentation, deterministic sorting, UTC timestamps, and lowercase SHA256 hashes
- Keep schema changes aligned with generated XML output
- Do not hand-edit generated `Cache` XML or generated README outputs unless explicitly requested
- Prefer updating scripts and regenerating the relevant cache files instead of editing generated files manually
- When generator behavior changes, run the smallest relevant script first
- Run `Scripts/Build-UnifiedDriverPackCatalog.ps1` when unified DriverPack or WinPE outputs depend on the changed data

External dependency rules:
- Do not run networked update scripts unless the task requires regenerated catalog data
- Be aware that update scripts depend on external vendor and Microsoft endpoints
- Dell, HP, and OS catalog generation require `7zz` or `7z` for CAB extraction

Validation rules:
- No formal test suite exists in this repository
- For script-only edits, at minimum run a PowerShell parser check over changed scripts and helpers
- For behavior changes, run the relevant generator with the smallest practical scope when possible
- Verify generated files only when the task intentionally changes generated catalog output

Git rules:
- Follow Conventional Commits for all commit messages
- Write commit messages in English
- Keep commits atomic and focused
- Do not mix unrelated catalog, schema, workflow, and generated-output changes

Worktree / branch / PR rules:
- Use a dedicated git worktree for implementation work when the task changes code
- Create worktrees outside the main repository folder
- Sync the base branch before creating a worktree
- Create a focused branch for each implementation task
- Push the branch and open a pull request when implementation and verification are complete
- Delete merged feature branches and clean up worktrees after PR merge

Subagent rules:
- Use subagents when the user explicitly asks for them or when parallel read-only analysis materially helps the task
- Use subagents only for read-only code exploration and analysis
- Do not use subagents to modify files
- The main agent is responsible for all code edits, commits, pushes, and pull requests

Output rules:
- Do not add emojis
- Do not add unnecessary comments
- Only explain decisions when useful
- When making assumptions, choose the most reasonable one and proceed
