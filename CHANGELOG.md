# Changelog

All notable changes to Sextans Suite are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed

- **The security pipeline now scans at every severity, with two new build gates.** `security-patch.sh`
  drops the CRITICAL/HIGH Trivy filter on the published scans; `parse-security-scans.rb` records OS
  findings at CRITICAL/HIGH/UNKNOWN (UNKNOWN catches unscored advisories like the eMudhra CA bundle)
  and language/gem findings at **every** severity (a gem MEDIUM can be directly reachable). Two gates
  abort the run before an image is pushed: a **boot-check** (the image must actually start) and a
  **CA-check** (the image must not trust the compromised `emSign ECC Root CA - G3`). The vulnerability
  register grew from 86 to 160 rows as the previously-filtered MEDIUM/LOW/UNKNOWN findings became
  visible. Ported from Severance.
- **`build_register.py` disposition logic reworked.** Precedence is now researched `(image,cve)` >
  researched `cve` > package-wide rule > a prior **human** decision > shadowed > `(exposure, control,
  has_fix)` default; a row whose Notes are a generated default is recomputed each run, so an improved
  default or new research can finally replace a stale auto-default (previously the existing register
  row always won). Defaults now split on whether a fix exists: an owned-image finding with no
  published fix is `TRACK`, not `PATCH` ("nothing to patch to"). This moved `fdpserv2`'s two
  no-fix `lz4-java` findings from PATCH to TRACK.
- **The deployment compose templates now pin each image by content digest** (`fairdatasystems/<name>:<date>@sha256:<digest>`),
  not by tag alone. A tag can be silently re-pointed by anyone who gains registry push access; a digest can't,
  so Docker refuses an image whose bytes don't match -- a direct response to the Vantage6 registry compromise
  of Mar–Apr 2026, where malware was pushed under existing tags. `security-patch.sh` now reads each image's
  digest from `.RepoDigests` after pushing it and aborts the whole run if any image has no digest (no silent
  tag-only fallback). Ported from Severance. Mark flagged that the suite had already moved to digest-based
  pulls, which caught that the freshly regenerated templates would otherwise have shipped tag-only.
- **All seven images (`virtuoso`, `fdpserv2`, `fdpclient`, `mdb`, `cdeb2`, `care2`, `yrml`) rebuilt, rescanned
  and re-pushed under the `2026-11-08` tag, and the compose templates re-pinned to their new digests.**
  `virtuoso` and `fdpclient` scan completely clean (no recorded findings); `care2` and `cdeb2` carry zero
  CRITICAL/HIGH (only lower-severity gem findings, newly visible under every-severity scanning). The remaining
  CRITICAL/HIGH are confined to `mdb` (30), `fdpserv2` (28) and `yrml` (12), each dispositioned in
  `vulnerability-register.csv`; see `Security/VULNERABILITY_TRIAGE.md` ("2026-11-08 re-scan review") for the
  per-finding reasoning.
- The vulnerability register's `ACCEPT` decision is now called `NOT REACHABLE` (same meaning: the vulnerable
  code can't be reached in our deployment). Partners would read "accepted" as "known risk, tolerated", which
  it never meant. The 29 existing rows were relabelled (no other change; no rescan), and the partner legend
  now says plainly that the 28 Tier-3 rows rest on a per-component judgment rather than per-CVE research.
  Same rename as in Severance (2026-11-08). Mark's call.

### Added

- **Published partner-facing vulnerability transparency documentation.** `Security/VULNERABILITY_TRIAGE.md`
  now opens with a "For partners: how to decide whether to deploy a given image" section explaining,
  in plain terms, what the `Decision` column in `vulnerability-register.csv` means for a deploy
  decision, where to find the raw per-image/per-date Trivy scan backing it, and how to read
  `ExposureTier`. Linked from the top-level README and from the "Securing your server" section of
  both `Fix-install/README.md` and `Sight-install/README.md` -- previously this documentation
  existed but wasn't linked from anywhere a partner would actually find it.

### Fixed

- **`cdeb2` carried 35 CRITICAL/HIGH findings that were entirely build-time cruft; now 0.** Its
  Dockerfile is now a multi-stage build: the compiler toolchain, and the second (Alpine) Ruby that
  `ruby-dev` pulled in purely for build headers, stay in a builder stage, and the runtime image
  copies only the compiled gems plus the handful of shared libraries `ldd` shows they load. All 35
  CRITICAL/HIGH findings (every one a build-toolchain or Alpine-ruby-package CVE) dropped to zero;
  the image still boots and runs identically. Only lower-severity gem findings (addressable, json,
  nokogiri), newly visible under every-severity scanning, remain.
- **`cdeb2` and `yrml` no longer trust the compromised `emSign ECC Root CA - G3`.** Although rebuilt
  after the fix date, both still shipped the compromised eMudhra CA because the corrected Alpine
  `ca-certificates-bundle` (20261020-r0) isn't in their base releases' repos yet (Alpine 3.24 / 3.19),
  so `apk upgrade` couldn't remove it. Their Dockerfiles now strip that one CA from the OS trust
  bundle directly (`strip-compromised-ca.sh`); verified the images still trust ordinary public CAs.
  A pipeline CA-check now fails the build if any image trusts it.
- **Pre-auth multipart denial-of-service in the `cdeb2` and `yrml` Sinatra services.** Both pinned
  rack 3.2.6, whose multipart parser retains the full parsed body in its scan buffer
  (`GHSA-5v64-555j-wjxm`, HIGH -- enough to exhaust a small container's memory). Sinatra merges
  `request.params` (including a parsed multipart body) before any route runs, and classic-style apps
  enable `Rack::MethodOverride`, which reads the body earlier still -- so the parser was reachable
  before any application logic. Neither advisory is in the GitHub/OSV databases, so Dependabot never
  proposed the bump. Fixed by bumping rack to `>= 3.2.8` in both `Daemon/` and `yarrrml-rml/`,
  disabling `method_override` (neither app uses `_method`), and adding a `RefuseMultipart` Rack
  middleware that returns 415 for any `multipart/*` body -- taking the whole multipart parser off the
  reachable surface, since neither service has a multipart route (both are GET-only). Mirrors the fix
  already shipped in Severance. Mark identified both apps as carrying the same exposure found there.
- **`care2` (CARE-SM-2 Toolkit) shipped an unpatched Alpine OS layer.** Its Dockerfile never ran
  `apk upgrade` at all, unlike the other owned images -- found while re-triaging the 2026-11-06
  scan. Fixed upstream in `CARE-Semantic-Model-Version-2` (Toolkit bumped to 2.1.1), rebuilt,
  rescanned clean (was 1 CRITICAL + ~18 HIGH, all OS-layer), and re-pushed under the same
  `fairdatasystems/care2:2026-11-06` tag.
- **`build_register.py`'s `MANUAL_DECISIONS` could silently misapply a disposition researched for
  one image to a different image reporting the same CVE.** Concretely: `CVE-2026-31789` was marked
  `RESOLVED` globally based on evidence specific to `fdpclient`'s fix; when the same CVE later
  appeared in `care2` (still genuinely unpatched there), the register wrongly inherited `RESOLVED`.
  Fixed by letting `MANUAL_DECISIONS` take an `(image, cve)` key that overrides the CVE-only one,
  and removed the two stale global entries that caused this (both already covered on their own by
  the "a CVE drops out of the register once it's gone from an image's scan" mechanism).
- **Sextans Fix: data folder permissions no longer apply only at install time.** `install-sextans-fix.sh`
  previously ran `chmod -R o+rwX` on `Sextans-Fix/data` once, during installation, to let the
  fixed-UID `cde-box-daemon`/`yarrrml-rdfizer` containers read and write a folder owned by the host
  user. Any CSV/YARRRML dropped into that folder afterwards -- including a `data/custom/` folder
  the user creates themselves for a custom datatype -- never got the same treatment, which could
  make a transformation fail to find a newly-added file. The installer now also sets a default ACL
  on `data/` (when the `acl` package is available) so new files and folders inherit the same
  permissions automatically; it prints a warning with the manual `chmod` workaround when `setfacl`
  isn't available. Documented in `Fix-install/README.md`.

## [3.2.0] - 2026-09-21

### Documentation

- Fix and Sight READMEs now explain that Virtuoso Conductor's SPARQL box (Linked Data > SPARQL)
  returns no rows -- even when logged in as `dba` -- because of the anonymous-read lockdown, list the
  authenticated ways to query (`/sparql-auth`, ISQL, `curl --digest`), and warn against restoring
  anonymous read access to make it "work".

### Changed

- **Sextans Virtuoso image now uses the `-alpine` variant** (`openlink/virtuoso-opensource-7:7.2.17-alpine`),
  patched with `apk upgrade`. It is much smaller than the Ubuntu image, and the Ubuntu builds from
  `7.2.17-r25` onward ship without `/var/lib/dpkg`, so they could not be patched with `apt` at all
  (and Trivy could not see their OS packages). `security-patch.sh` also now runs under `set -e`, so
  a failed patch step stops the run instead of pushing an unpatched image.

- **GraphDB-era variable names renamed to triplestore-neutral ones**, since both Fix and Sight run on Virtuoso:
  `.env` keys `GraphDB_User`/`GraphDB_Pass`/`GRAPHDB_REPONAME` are now `TRIPLESTORE_USER`/`TRIPLESTORE_PASS`/`TRIPLESTORE_GRAPH`
  (matching Severance's names); installer variables `GDB_PORT`/`GRAPHDB_PASSWORD` are now `VIRTUOSO_PORT`/`VIRTUOSO_PASSWORD`;
  compose-template placeholders `{GDB_PORT}`/`{GDB_PASS}` are now `{VIRTUOSO_PORT}`/`{VIRTUOSO_PASS}`. The installers still accept
  the old `GDB_PORT`/`GRAPHDB_PASSWORD` if set in the environment, and `Daemon/transform-cdev2.rb` still reads the old `.env` keys as a
  fallback, so an existing Fix install keeps working if only the `cdeb2` image is updated. An existing install's own compose file and
  `.env` are not rewritten -- they keep the old names until reinstalled. The stale GraphDB example endpoints in the `exemplar_env`
  files now show Virtuoso's.

- `parse-security-scans.rb` now writes a header-only CSV for an image with no CRITICAL/HIGH findings (previously it wrote nothing), so a clean scan is distinguishable from a missing one.

### Removed

- **Beacon is no longer built, patched, or scanned.** `security-patch.sh` no longer touches
  `pabloalarconm/beacon-api4care-sm`, and the commented-out `beacon_count` service and its
  `BEACON_PORT` prompt are gone from the Fix compose templates and installer. That form of Beacon
  will not be used again: Beacon v2 for CARE-SM-2 is now our own facade
  (`CARE-Semantic-Model-Version-2/implementation/Beacon2/`) built on top of
  [Severance](https://github.com/FAIR-Data-Systems/Severance), the secure SPARQL relay, and is
  scanned in that project's own `Security/` pipeline.
- The vulnerability triage docs (`VULNERABILITY_TRIAGE.md`, `build_register.py`) drop the retired
  `gdb` (GraphDB) and `beacon` images, and a "Retired images" section records why.

## [3.1.0] - 2026-09-09

### Added

- **MongoDB authentication is now enabled by default in Sextans Sight.** `install-sextans-sight.sh`
  generates a random Mongo root password (same convention as the JWT signing secret -- no new
  prompt) and wires it into both Mongo's own `MONGO_INITDB_ROOT_USERNAME`/`_PASSWORD` and FDP's
  new `mongo-auth` Spring profile (built from `markwilkinson/FAIRDataPoint`'s
  `feature/virtuoso-repository` branch, same as `fdpserv2`'s existing Virtuoso patch). Verified
  live end-to-end: a real install's admin login returns a valid JWT through the newly
  authenticated connection, with no change to any other part of the install flow.

## [3.0.0] - 2026-09-09

Sextans Sight moves off GraphDB to Virtuoso, matching Sextans Fix's own move in 2.0.0. GraphDB
is now retired from the entire suite.

### Changed (breaking)

- **Sextans Sight's triple store is now Virtuoso, not GraphDB.** Same reasoning as Fix's earlier
  move: GraphDB couldn't be made to run as a non-root user, Virtuoso is actively maintained,
  vendor-backed, and has real authentication. The bootstrap-phase `graph-db-repo-manager` is gone
  entirely (Virtuoso needs neither a repository-creation step nor a password-change REST call --
  its DBA password is set directly via the container's own `DBA_PASSWORD` environment variable).
  **Existing GraphDB-backed Sight installations have no automated path to preserve their
  (typically hand-entered) FDP metadata across this change yet** -- a fresh install is required,
  and anyone with real production metadata should hold off upgrading until a proper
  dump-and-reload migration path exists (tracked as a follow-up, not yet built).
- **FAIR Data Point itself required a real code patch** to support Virtuoso as a repository type
  (RDF4J has no built-in Virtuoso adapter). Built and verified against `markwilkinson/
  FAIRDataPoint`'s `feature/virtuoso-repository` branch (not yet merged upstream -- `fdpserv2` is
  built from that branch directly until the PR is accepted, at which point it moves back to
  tracking an official vendor release). Two real Virtuoso incompatibilities needed working
  around: RDF4J's `SPARQLRepository` has no Digest-auth support (Virtuoso rejects Basic auth
  outright), and RDF4J's `SPARQLConnection` appends a trailing `; ` to every SPARQL Update that
  Virtuoso's stricter compiler rejects. Live-verified, including the specific SPARQL construct
  FDP's own metadata-delete path uses (`RepositoryConnection#remove(null, null, null, context)`)
  -- confirmed working correctly, independent of `RepositoryConnection#size(context)`, which
  turned out to be an unreliable signal against this Virtuoso setup.
- `care`/`cdeb` images were already renamed to `care2`/`cdeb2` in 2.1.0 for the same reason;
  `fdpserv` is now `fdpserv2` -- its build source fundamentally changed (vendor image ->
  our own patched fork), and a same-named image whose source silently changed underneath it
  would be a worse record than a clean break in the tag history.

### Added

- Per-container CPU/memory limits (`mem_limit`/`cpus`) across all of Sight's services, matching
  Fix's own resource-limit pass earlier in this release line -- no service in either stack had
  a resource ceiling before that.
- Anonymous SPARQL reads are locked down on Sight's Virtuoso instance too (same `initdb.d`
  mechanism as Fix), closing the raw triple-store's direct SPARQL endpoint as an unnecessary
  attack surface -- FDP's own REST API remains the intended public-read interface, with its own
  access model.

## [2.1.0] - 2026-09-09

### Added

- **Custom datatypes in Sextans Fix.** You can now bring your own CSV and your own YARRRML
  mapping for data that doesn't fit any CARE-SM-2 model -- drop both into `Sextans-Fix/data/custom/`
  (matching basenames: `<name>.csv` + `<name>_yarrrml.yaml`) and every transformation picks them
  up automatically, entirely independent of the CARE-SM-2 Toolkit pipeline. See
  `Fix-install/README.md` for the exact convention.
- **The CARE-SM-2 auto-update is now smoke-tested before use.** Every transformation still pulls
  the latest CARE-SM-2 mapping automatically (unchanged), but a freshly-pulled mapping is now
  validated against a small known-good fixture before it's trusted -- if that check ever fails
  (a broken or corrupted upstream pull), the previous, already-verified mapping keeps being used
  instead, with a warning logged, rather than silently running unverified content against real
  data.

### Fixed

- **Sextans Fix now replaces data on each transformation instead of accumulating it forever.**
  The original GraphDB-backed pipeline replaced its entire repository's contents on every run;
  the Virtuoso migration in 2.0.0 lost that property (every record lands in its own uniquely
  generated graph, so nothing was ever actually being overwritten). Fixed: graphs under your
  configured `baseURI` are now cleared before each write, matching the original snapshot
  behavior. Custom datatypes participate in this too, if their own mapping mints graphs under the
  same `baseURI`.
- `yarrrml-rdfizer` previously operated on fixed, shared scratch paths for every transformation
  type; different jobs running around the same time (the new smoke test, a custom datatype, the
  real CARE-SM run) could have corrupted each other's output. Each type now works in its own
  scratch directory.
- Found and fixed a real bug while making the above change: a `mktemp` incompatibility with this
  image's `/bin/mktemp` (BusyBox, not GNU coreutils) was silently producing **empty transformation
  output with no visible error** in some circumstances, since the failure was never surfaced by
  the calling code. Both are now fixed -- the incompatibility, and the silent failure mode itself.

## [2.0.0] - 2026-09-09

Two breaking changes to Sextans Fix, bundled into one release: it no longer uses GraphDB, and
it no longer uses the original CARE-SM data model. Sextans Sight is unaffected by either change.

### Changed (breaking)

- **Sextans Fix's triple store is now Virtuoso, not GraphDB.** GraphDB was the one remaining
  service in the whole suite that could not be made to run as a non-root user (its own startup
  re-creates log files as root regardless of container `--user` settings), so it's been replaced
  outright rather than patched further. Virtuoso is actively maintained, vendor-backed, and has
  real authentication built in. Record data now lands in Virtuoso's single database per install
  rather than a GraphDB "repository"; the bootstrap-phase `graph-db-repo-manager` service is gone
  entirely (Virtuoso needs neither a repository-creation step nor a password-change REST call --
  its DBA password is set directly via the container's own `DBA_PASSWORD` environment variable).
  Existing GraphDB installations are not migrated automatically; a fresh install is required.
- **Sextans Fix now uses CARE-SM-2** (`wilkinsonlab/CARE-Semantic-Model-Version-2`), superseding
  the original CARE-SM model, YARRRML mapping, and Toolkit. The public CSV schema changed --
  e.g. Diagnosis's old `valueIRI` column is gone, replaced by `target`/`value`/`value_datatype`
  with real `xsd:boolean` support -- so existing CSVs written for the original CARE-SM will not
  load against the new Toolkit. See the [CARE-SM-2 migration guide](https://care-sm-semantic-model-v2.readthedocs.io/en/latest/migration.html)
  and `Fix-install/README.md`. The `care` and `cdeb` images are retired in favor of `care2` and
  `cdeb2` so the two model versions are never ambiguous in the image tag history; `care2` is now
  built from our own source rather than a collaborator's vendor image.

### Fixed

- `yarrrml-rdfizer` (`yrml`) was silently 403'ing every container-to-container request
  (`Rack::Protection::HostAuthorization`, on by default in current Sinatra/rack-protection),
  which broke the entire RDFization trigger -- the whole point of Sextans Fix. Fixed by
  neutralizing the check for this internal-only service (never exposed to a browser or the
  public internet, no host-derived logic anywhere in the app).
- `cde-box-daemon`'s Virtuoso write path (`Daemon/http_utils.rb#put_digest`) sent the full RDF
  payload on the initial, unauthenticated probe request; Virtuoso rejects that request and
  closes the connection as soon as it reads the headers, without waiting for the body, so any
  payload large enough to still be mid-transfer when the rejection arrived produced a client-side
  `ECONNRESET` instead of the expected 401 challenge. Fixed by probing with an empty body.
- `install-sextans-fix.sh`'s pre- and post-install clean-up steps threw several harmless-but-
  alarming errors on a normal run (`mkdir` on an existing directory, removing a network/container
  that doesn't exist yet, `docker rm` with no arguments when nothing matched). Also found and
  fixed a real bug in the same area: the bootstrap compose file was deleted immediately after
  bootstrapping, before the post-install clean-up step that still needed it to tear down the
  bootstrap Virtuoso container -- every install was silently leaving that container and its
  network orphaned.

### Removed

- `Fix-install/Sextans-Fix/data/CARE_yarrrml.yaml` and `CARE_yarrrml_template.yaml` -- these were
  never actually read by the running pipeline (`cde-box-daemon` fetches the mapping live from the
  CARE-SM git repo on every request and overwrites them), so keeping stale committed copies
  around was actively misleading rather than just unused.

## [1.0.0] - 2026-07-10

### Added

- `FDP_Configs/ERDERA_Base/run-erdera-configuration.sh` — wrapper script for the ERDERA FDP configuration step, so users no longer have to answer an interactive prompt that `docker compose` can't actually deliver keystrokes to.

### Fixed

- `Fix-install/install-sextans-fix.sh` and `Sight-install/install-sextans-sight.sh` now auto-detect whether the host provides the `docker compose` plugin or the standalone `docker-compose` binary, and use whichever is available.
- GraphDB bootstrap containers now bind to the port chosen during the install questionnaire (`GDB_PORT`) instead of a hardcoded `7200`, preventing a bind failure when GraphDB's default port is already in use on the host.
- `install-sextans-fix.sh` no longer leaves a stray temp compose file behind after bootstrapping (the cleanup line was a no-op string instead of an `rm` call).
- `FDP_Configs/ERDERA_Base/docker-compose.yml` now requires `FDP_PORT` via the environment instead of silently hanging on an interactive prompt.

### Removed

- Stray leftover config files from earlier manual test installs: `Sight-install/config/fdp/application-sextans1100.yml`, `Sight-install/config/fdp/application-sight2.yml`.
- Obsolete scratch note `Fix-install/change compose with or without hyphen`, superseded by the `docker compose` auto-detection fix above.

### Docker Images

- `markw/erdera-fdp-config:0.0.1` — content unchanged this release; the orchestration around it (compose file + wrapper script) was fixed to be usable non-interactively. This image is shared verbatim with the Rare2FAIR project; both repos' Docker Compose files are kept pointing at the same tag.
