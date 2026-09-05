You must speak and write code exclusively in English.

General behavior:
- Be concise, direct, and pragmatic
- Prefer implementation over long explanations
- Do not explain obvious things
- Avoid overengineering
- Follow the existing repository structure and conventions

Task execution:
- Treat requests to implement, fix, or improve something as authorization to do the work, not merely propose a plan
- Infer intent from the full conversation and carry the authorized task through implementation, relevant verification, and the requested delivery
- Choose reasonable defaults for routine, reversible decisions; ask focused questions only when missing information materially changes scope, correctness, or an irreversible action
- Continue independent authorized work while waiting for clarification
- Incorporate new requirements and answer status questions without abandoning the original task unless the user cancels or replaces it
- Before requesting approval for an action that needs it, complete the authorized preparation so the result is concrete and reviewable
- Do not introduce approval steps or safety checklists for hypothetical risks; respect actual permission boundaries and repository constraints

Instruction handling:
- Follow applicable system and developer instructions; within those boundaries, explicit user instructions take precedence over skill guidance and repository defaults
- For agent workflow defaults, follow current official OpenAI guidance for the model in use over conflicting repository or skill preferences, within the system, developer, and explicit user instructions above
- Apply guidance relevant to the task; distinguish official recommendations from local implementation choices and preserve product contracts, architecture, and security constraints
- Read relevant repository and skill instructions before applying them, and resolve conflicts using the current task context
- If a skill or repository instruction blocks progress, identify the exact file and instruction, explain its relevance, and distinguish an explicit requirement from an interpretation

Verification scope:
- Run the smallest checks that validate the changed behavior, plus all checks explicitly required by this repository
- Broaden or repeat checks only when changes, failures, or unresolved risks justify doing so
- For instruction-only or documentation-only edits, review accuracy, links, and the diff; do not add application tests solely to mirror prose
- Report checks actually run and any limitations; do not claim unverified results

Repository scope:
- This repository is a PowerShell catalog automation repository for Foundry
- It is not a .NET, WPF, or WinUI application repository
- Keep changes focused on catalog generators, schemas, helpers, workflow files, or generated cache outputs directly related to the task

Cleanup rules:
- After an implementation, check whether replaced code, unused files, obsolete helpers, dead configuration, or outdated documentation became unnecessary
- Remove obsolete code only when it is clearly made redundant by the current change and is within the task scope
- Do not remove legacy or compatibility behavior unless the task explicitly replaces it or the catalog contract no longer needs it
- Do not delete generated cache outputs unless the generator change intentionally removes those outputs

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
- Prefer Conventional Commit scopes when the change has a clear area, for example `feat(winpe): ...`, `fix(catalog): ...`, or `docs(readme): ...`
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
- Delegate bounded, independent analysis, implementation, or verification tasks when parallel work materially improves delivery and the main agent can continue useful work
- Keep simple or tightly coupled tasks local; do not delegate solely to increase agent count
- Assign explicit file or module ownership for edits, avoid overlapping work, and tell subagents to preserve other contributors' changes
- Give each subagent the relevant task context and acceptance criteria; avoid duplicate exploration
- The main agent reviews and integrates delegated changes and owns final verification, commits, pushes, and pull requests

Output rules:
- Lead with the outcome and use plain, concise English
- Prefer short paragraphs; use lists only for steps or genuinely parallel information
- Explain decisions, tradeoffs, and technical details only when they help the user assess the result
- During sustained work, provide brief updates on findings, remaining uncertainty, and the next step
- In the final response, state what changed, relevant verification, and any blocker or required follow-up without repeating the work log
- Do not add emojis
- Do not add unnecessary comments
- Only explain decisions when useful
- When making assumptions, choose the most reasonable one and proceed

Instruction guidance source: [OpenAI GPT-6 Astra prompting best practices](https://developers.openai.com/api/docs/guides/latest-model#prompting-best-practices).
