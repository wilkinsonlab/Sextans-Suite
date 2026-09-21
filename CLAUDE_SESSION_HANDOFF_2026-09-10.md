# Session handoff notes -- 2026-09-10 (Sextans-Suite)

**Not committed to git, not part of the project.** This file exists only so a future Claude Code
session, once anchored to this project's own memory (see the workspace-folder-order issue below),
can read it and turn it into real project memory. Delete it once that's done, or leave it -- it's
untracked either way.

## Why this file exists

This whole session's memory got misfiled under a different project (`Rare2FAIR`) because Claude
Code's VSCode extension binds a session's memory to the *first* folder listed in the
`.code-workspace` file's `folders` array, regardless of which folder is actually open/focused
(`/home/osboxes/CODE/Sextans-Rare2FAIR.code-workspace` lists `Rare2FAIR` first). Fix: reorder that
file so `Sextans-Suite` (or a project you actually want memory for) comes first, then restart. Once
that's done, ask a fresh session to read this file and `Severance`'s equivalent
(`CLAUDE_SESSION_HANDOFF_2026-09-10.md` there) and save whatever's useful as real memory.

## What happened this session (Sextans-Suite side)

Most of this session's *new* work happened in the sibling `Severance` repo (see its own handoff
note for the full list) and in `FAIRDataPoint` (upstream PR work, see below). Sextans-Suite itself
saw lighter, targeted work on branch `database_migration`:

1. **Refreshed all patched images to the `2026-09-10` tag** (`virtuoso`, `fdpserv2`, `fdpclient`,
   `mdb`, `cdeb2`, `care2`, `yrml`, `beacon`) via `Sextans/Security/security-patch.sh`, regenerating
   the five deployment compose templates (Fix, Sight, config, bootstrap_fix, bootstrap_sight) from
   their masters.
2. **Added the missing `fdpserv2`/`virtuoso` entries** to `Sextans/Security/build_register.py`'s
   `IMAGE_INFO`/`DEFAULT_DECISIONS` (they existed as real images but had no register classification
   until now), rebuilt `vulnerability-register.csv`.
3. Both committed and pushed to `database_migration` (commit `6e4505c` at push time).

**Branch state**: `database_migration` is 7 commits ahead of `main`/`master`, containing *all* of
the GraphDB->Virtuoso migration (Fix in v2.0.0, Sight in v3.0.0), the MongoDB-auth default
(v3.1.0), a full hardening pass, and a live pentest's fixes -- `main` has nothing this branch
doesn't. **`database_migration` is the branch to point testers at**, not `main`.

Checked (thoroughly, not assumed) whether the top-level `README.md`/`Fix-install/README.md`/
`Sight-install/README.md` needed syncing to this architecture -- they didn't; that sync already
happened in an earlier session, before this one started. Don't redo that check reflexively next
time without a specific reason to suspect drift.

## Cross-project relationships worth remembering

- **Rare2FAIR is a manually-maintained parallel copy of Sextans-Suite, not a fork or clone.** The
  Rare2FAIR team dislikes the "Sextans" branding, so it's a deliberately separate project --
  fixes/image bumps made here do not propagate automatically and must be manually ported into
  Rare2FAIR's own installer scripts and docker-compose files. Flag when Sextans-Suite work would
  matter to Rare2FAIR; don't port it over unprompted.
- **FAIRDataPoint upstream**: two PRs open against `FAIRDataTeam/FAIRDataPoint` from
  `markwilkinson/FAIRDataPoint`, both targeting `master` (team said ignore `develop` entirely, it's
  legacy, they abandoned their planned Postgres migration):
  - PR #980 -- Mongo-auth fix, branch `fix/mongo-auth-profile`.
  - PR #983 -- Virtuoso repository-type support, branch `feature/virtuoso-repository-master`.
  - **The FDP team has already merged some fixes for vulnerabilities we separately reported to
    them by email** (the remaining Java/Maven dependency findings, cc'd to Dennis and Luiz). Their
    `main`/`master` has moved since. **Always fetch/pull the latest upstream before doing any
    further FDP work** -- don't assume the locally-cloned state is current.
  - Sextans-Suite's own `fdpserv2` image is built from a fourth branch,
    `feature/virtuoso-repository` -- that's the branch actually used for deployments, separate
    from the three PR branches and not needing to change when they do. (Correction to an earlier
    note: this branch is **not** based on an old `v1.22.0` tag lineage -- checked directly, its
    real merge-base with `upstream/master` is a 2026-07-24 commit on master's own history.)
  - **Checked precisely how stale each relevant branch actually is against `upstream/master`,
    after an initial "323 commits behind" reading turned out to be misleading** (that number is
    real, but only for the fork's own neglected `master` branch, which nothing is actually built
    from or targets):

    | Branch | Commits behind `upstream/master` | Base date |
    | --- | --- | --- |
    | `origin/master` (fork's default branch, unused) | **323** | old |
    | `feature/virtuoso-repository` (what `fdpserv2` is built from) | **12** | 2026-07-24 |
    | `feature/virtuoso-repository-master` (PR #983's branch) | **1** | 2026-09-07 |
    | `fix/mongo-auth-profile` (PR #980's branch) | **1** | 2026-09-07 |

    **So this is a small rebase (1-12 commits), not a from-scratch redo of the porting work** --
    don't over-react to the fork's own stale `master` as if the real patch branches were built on
    it; they weren't. Still worth actually doing that rebase before further FDP-touching work here,
    to pick up upstream's own fixes (including ones prompted by our vulnerability report). Full
    detail in `FAIRDataPoint`'s own `CLAUDE_SESSION_HANDOFF_2026-09-10.md`.
  - Both PR bodies include an explicit AI-assisted-contribution disclosure, required by the FDP
    team's own `CONTRIBUTING.md`. Follow that pattern in any future PR there.
  - Pushing a branch with `.github/workflows/*` files not yet on the fork gets rejected without
    `workflow` OAuth scope (`gh auth refresh --hostname github.com --scopes workflow` fixes it) --
    don't delete the workflow files to route around it, the FDP team explicitly objected to that.

## A general (not Sextans-specific) gotcha surfaced again this session

Sinatra 4.x/rack-protection 4.x's `Rack::Protection::HostAuthorization` rejects any Host header
outside `localhost`/an IP literal with a bare `403 Host not permitted`, before any app code runs.
`set :protection, except: :host_authorization` does **not** reliably disable it -- confirmed
independently in three places now: `yarrrml-rml/t.rb` and `Daemon/transform-cdev2.rb` here
(already fixed, predates this session), and `Severance/external/outie.rb` (fixed this session,
hit while testing Severance's own network-hardening change). The fix that actually works:
monkeypatch `Rack::Protection::HostAuthorization#accepts?` to return `true` directly. Treat this as
a known, general Sinatra gotcha for any future service in this project family, not something to
rediscover each time.

## Not done / open, worth picking up

- No real data-migration/dump-and-reload tooling exists yet for an *existing* Sight install moving
  from GraphDB to Virtuoso (Fix doesn't need this -- its data is always re-derivable from source
  CSVs). Flagged in earlier sessions, still not built.
- MongoDB version-upgrade tooling (old installs on older Mongo majors) -- same "no migration path"
  gap, also still not built.
- `FDP_Migration/sextans_migrate.py` is deeply coupled to GraphDB's own REST API and would need
  real rework for Virtuoso semantics before it could help with either gap above.
