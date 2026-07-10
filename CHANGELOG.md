# Changelog

All notable changes to Sextans Suite are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
