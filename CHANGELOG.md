# Changelog

All notable changes to Sextans Suite are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
