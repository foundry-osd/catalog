# Claude Code instructions

You must speak and write code exclusively in English.

## General behavior

- Be concise, direct, and pragmatic
- Prefer implementation over long explanations
- Do not explain obvious things
- Avoid overengineering
- Follow the existing repository structure and conventions

## Task execution

- Treat implementation requests as authorization to complete the scoped work, relevant verification, and requested delivery
- Choose reasonable defaults for routine reversible decisions; ask only when missing information materially affects scope, correctness, or an irreversible action
- Continue independent authorized work while awaiting clarification and prepare a reviewable result before requesting necessary approval
- Incorporate follow-up requirements without abandoning the original task unless the user cancels or replaces it
- Respect actual permission boundaries without adding approval steps for hypothetical risks
- Honor task-specific delivery instructions, including requests for no pull request or review before committing and pushing

## Instruction handling

- Follow applicable system and developer instructions; within those boundaries, explicit user instructions take precedence over skill guidance and repository defaults
- For Claude Code workflow defaults, follow current official Anthropic guidance within applicable higher-priority instructions, explicit user requirements, and repository contracts
- Apply guidance relevant to the task; distinguish official recommendations from local implementation choices and preserve product contracts, architecture, and security constraints
- Read applicable nested `CLAUDE.md` files and relevant skill instructions before editing, and resolve conflicts using the current task context
- If a skill or repository instruction blocks progress, identify the exact file and instruction, explain its relevance, and distinguish an explicit requirement from an interpretation

## Skill and documentation tools

- Use only tools, MCP servers, and skills available in the current Claude Code session; do not assume another coding tool's plugins or configuration are installed
- Use the Context7 MCP server, when available, for library or framework APIs, setup, or version-specific behavior; resolve the relevant library and consult documentation matching the repository version before relying on memory
- If Superpowers skills are installed in Claude Code, use the relevant skill for brainstorming, debugging, planning, implementation, review, or verification; read and apply it rather than merely naming it
- Keep skill use proportional to the task and follow the instruction precedence above; do not invoke unrelated skills or add unnecessary workflow steps
- If Context7 or a required skill is unavailable, state the limitation and continue with official documentation or an equivalent workflow where possible; do not claim to have used unavailable tools

## Verification scope

- Run the smallest checks that validate the changed behavior, plus all checks explicitly required by this repository
- Broaden or repeat checks only when changes, failures, or unresolved risks justify doing so
- For instruction-only or documentation-only edits, review accuracy, links, and the diff; do not add application tests solely to mirror prose
- Report checks actually run and any limitations; do not claim unverified results

## Repository scope

- This repository is a PowerShell catalog automation repository for Foundry
- It is not a .NET, WPF, or WinUI application repository
- Keep changes focused on the relevant generators in `Scripts`, helpers in `Helpers`, release definitions in `Config`, contracts in `Schemas`, regression scripts in `Tests`, workflows, and generated `Cache` outputs

## Cleanup rules

- After an implementation, check whether replaced code, unused files, obsolete helpers, dead configuration, or outdated documentation became unnecessary
- Remove obsolete code only when it is clearly made redundant by the current change and is within the task scope
- Do not remove legacy or compatibility behavior unless the task explicitly replaces it or the catalog contract no longer needs it
- Do not delete generated cache outputs unless the generator change intentionally removes those outputs

## PowerShell rules

- Use PowerShell 7-compatible code
- Use `[CmdletBinding()]`, validated parameters, `Set-StrictMode -Version Latest`, and `$ErrorActionPreference = 'Stop'` in scripts
- Use clear PowerShell `Verb-Noun` function names
- Keep functions small and focused
- Reuse `Helpers/FoundryHelpers.psm1` for shared mechanisms and `Helpers/OperatingSystemCatalog.psm1` for OS catalog rules; keep release source definitions in `Config/Windows11Releases.psd1`
- Prefer structured XML APIs and `XmlWriter` for catalog output
- Avoid ad hoc string manipulation for XML, paths, or structured data when a proper API is available

## Catalog output rules

- Keep machine-readable catalog outputs XML; preserve the generated Markdown README summaries alongside them
- Preserve UTF-8 without BOM, CRLF line endings, two-space XML indentation, deterministic sorting, UTC timestamps, and lowercase SHA256 hashes
- Keep schema changes aligned with generated XML output
- Do not hand-edit generated `Cache` XML or generated README outputs unless explicitly requested
- Prefer updating scripts and regenerating the relevant cache files instead of editing generated files manually
- When generator behavior changes, run the smallest relevant script first
- Run `Scripts/Build-UnifiedDriverPackCatalog.ps1` when unified DriverPack or WinPE outputs depend on the changed data

## External dependency rules

- Do not run networked update scripts unless the task requires regenerated catalog data
- Be aware that update scripts depend on external vendor and Microsoft endpoints
- Dell, HP, and OS catalog generation require `7zz` or `7z` for CAB extraction

## Validation rules

- Run `pwsh -NoProfile -File Tests/Test-OSCatalogHistory.ps1` for OS history or release configuration changes
- Run `pwsh -NoProfile -File Tests/Test-IntelWirelessCatalogFallback.ps1` for Intel wireless fallback changes; both regression scripts run in `.github/workflows/powershell-analysis.yml`
- Match the workflow PSScriptAnalyzer checks for changed scripts and helpers; report analyzer errors and unavailable tooling
- At minimum, parse changed `.ps1`, `.psm1`, and `.psd1` files with the PowerShell parser
- Prefer local regression tests for behavior changes; run a networked generator only when regenerated catalog data is part of the task
- Verify generated files only when the task intentionally changes generated catalog output

## Git rules

- Follow Conventional Commits for all commit messages
- Prefer Conventional Commit scopes when the change has a clear area, for example `feat(winpe): ...`, `fix(catalog): ...`, or `docs(readme): ...`
- Write commit messages in English
- Keep commits atomic and focused
- Do not mix unrelated catalog, schema, workflow, and generated-output changes

## Worktree / branch / PR rules

- Use a dedicated git worktree for implementation work when the task changes code
- Create worktrees outside the main repository folder
- Fetch the remote base before creating a worktree; preserve existing checkout changes and reuse the task worktree for follow-ups
- Create a focused branch for each implementation task
- Unless the user specifies another delivery workflow, push the branch and open or update its pull request when implementation and verification are complete
- Use an English Conventional Commit PR title and include summary, reason, main changes, and testing notes
- Merge only when requested and follow the requested merge strategy; retain the worktree until merge unless cleanup is requested
- After a requested merge, clean up only the merged task branch and its clean worktree; preserve other work

## Subagent rules

- Use available Claude Code subagents for bounded, independent analysis, implementation, or verification when parallel work materially improves delivery and the main agent can continue useful work
- Keep simple or tightly coupled tasks local; do not delegate solely to increase agent count
- Assign explicit file or module ownership for edits, avoid overlapping work, and tell subagents to preserve other contributors' changes
- Give each subagent the relevant task context and acceptance criteria; avoid duplicate exploration
- The main agent reviews and integrates delegated changes and owns final verification, commits, pushes, and pull requests

## Output rules

- Lead with the outcome and use plain, concise English
- Prefer short paragraphs; use lists only for steps or genuinely parallel information
- Explain decisions, tradeoffs, and technical details only when they help the user assess the result
- During sustained work, provide brief updates on findings, remaining uncertainty, and the next step
- In the final response, state what changed, relevant verification, and any blocker or required follow-up without repeating the work log
- Do not add emojis
- Do not add unnecessary comments

Claude Code references: [Best practices](https://code.claude.com/docs/en/best-practices) and [project memory](https://code.claude.com/docs/en/memory).
