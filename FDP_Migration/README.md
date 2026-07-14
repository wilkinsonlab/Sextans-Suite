# Sextans Sight Migration Tool

Migrates a Sextans Sight install (FDP + GraphDB + MongoDB) from a localhost
test URI to a real domain/w3id, and/or relocates it to a different physical
server. These are two independent operations:

- **Content rewrite** (`rewrite`) — the FDP mints its resource IRIs from
  `persistentUrl`, so that old URI ends up baked into every GraphDB triple
  (subjects, predicates, object IRIs, named graphs, and some literals) and
  into MongoDB's `ACL`/`metadata` collections. `rewrite` finds and replaces
  all of it, and updates `application.yml` to match.
- **Volume relocation** (`export` / `import`) — moves the actual docker
  volumes to a new host. Built as an **offline, two-step transfer**
  (tarball + manifest on disk, no SSH/network link between the two hosts
  required) because these installs commonly run in hospital networks where
  the source and destination servers can't reach each other directly, and
  the tarball may have to travel on a USB key.

Do either, both, or neither, in whichever order fits your situation.

## Contents

- **[Typical workflows](#typical-workflows) — start here**
- [Prerequisites](#prerequisites)
- [Command: `rewrite`](#command-rewrite)
- [Commands: `export` / `import`](#commands-export--import-optional-volume-relocation)
- [`Migration Plan.txt`](#migration-plantxt)

## Typical workflows

**"I tested on localhost, now I have a real domain, same server":**
```bash
python3 sextans_migrate.py rewrite --path ./myorg-Sextans-Sight \
    --new-persistent-url https://w3id.org/myorg
```

**"Moving to new hardware, URI stays the same":**
```bash
# on the old server
python3 sextans_migrate.py export --path ./myorg-Sextans-Sight --outdir ./myorg-export
# carry ./myorg-export to the new server (USB key, etc.), then:
python3 sextans_migrate.py import --indir ./myorg-export
# copy over docker-compose-myorg.yml and fdp/application-myorg.yml, then:
docker compose -f docker-compose-myorg.yml up -d
```

**"Moving to new hardware AND changing the URI":**
```bash
# on the old server
python3 sextans_migrate.py export --path ./myorg-Sextans-Sight --outdir ./myorg-export
# carry ./myorg-export to the new server, then:
python3 sextans_migrate.py import --indir ./myorg-export
# copy over docker-compose-myorg.yml and fdp/application-myorg.yml, then:
python3 sextans_migrate.py rewrite --path ./myorg-Sextans-Sight \
    --new-persistent-url https://w3id.org/myorg
```

The sections below cover what each command actually does and every flag it
accepts.

## Prerequisites

- Python 3 with the `requests` package installed (`pip install requests`).
- Docker with either the `docker compose` plugin or the standalone
  `docker-compose` binary.
- The install's `docker-compose-{PREFIX}.yml` and `fdp/application-{PREFIX}.yml`
  are read directly to figure out the prefix, GraphDB port/repo/credentials,
  and current `clientUrl`/`persistentUrl` — you never need to pass those in
  by hand, and there is deliberately no `--prefix` flag on `rewrite`: it
  always operates on whatever prefix the install folder already uses, so it
  can't accidentally rename a live install.
- The docker-compose stack for the install must be **stopped** before running
  `rewrite` or `export` (the tool checks this and refuses to proceed unless
  you pass `--force`). Rewriting GraphDB/Mongo content while FDP is live and
  possibly writing to them is not safe.
- **GraphDB's port must be exposed on `127.0.0.1` in the compose file**
  (`- 127.0.0.1:{GDB_PORT}:7200` under the `graphdb` service), because
  `rewrite` talks to GraphDB's SPARQL endpoint directly over HTTP from the
  host running the script — it does not go through `docker exec`. Many
  production installs deliberately lock this port down after go-live (it's
  reasonable hardening, since GraphDB has no reason to be reachable from
  outside its own docker network in normal operation). If you've done that,
  temporarily restore the `127.0.0.1:{GDB_PORT}:7200` port mapping in
  `docker-compose-{PREFIX}.yml` before running `rewrite`, run it, then remove
  the mapping again afterward if you want. Without it, the tool can't even
  determine the port to connect to and will fail immediately with a clear
  error rather than doing anything partial.

## Command: `rewrite`

Rewrites the old URI wherever it appears in GraphDB and MongoDB, and updates
`application-{PREFIX}.yml`.

```bash
python3 sextans_migrate.py rewrite \
    --path /path/to/PREFIX-Sextans-Sight \
    --new-persistent-url https://w3id.org/my-organization
```

By default `--old-persistent-url` is not needed — it's read from the current
`persistentUrl` in `application-{PREFIX}.yml` (this is what was baked into
the content when the install was first bootstrapped). Pass it explicitly if
you need to override that.

If your new `clientUrl` (the address FDP is actually reachable at, e.g.
behind a reverse proxy) differs from the new `persistentUrl` (the permanent
public identifier, e.g. the w3id itself), pass `--new-client-url` too;
otherwise it defaults to the same value as `--new-persistent-url`.

```bash
python3 sextans_migrate.py rewrite \
    --path /path/to/PREFIX-Sextans-Sight \
    --new-persistent-url https://w3id.org/my-organization \
    --new-client-url https://realserver.example.org:7070
```

### What it does, in order

1. Parses the install folder and refuses to run if containers for it are
   already up (`--force` overrides this).
2. Backs up all three named volumes (`{PREFIX}-graphdb`, `{PREFIX}-mongo-data`,
   `{PREFIX}-mongo-init`) to `migration-backup/{PREFIX}-{timestamp}/` inside
   the install folder, via a throwaway `busybox` container (`--skip-backup`
   to skip — not recommended).
3. Starts only `graphdb` and `mongo`, detects whether the mongo image ships
   `mongosh` or only the legacy `mongo` shell (older `fairdatasystems/mdb`
   tags don't have `mongosh`) and uses whichever is present, then waits for
   both services to become healthy (`--db-timeout`, default 300s, if a large
   real dataset needs longer than that to come up).
4. Runs a **dry-run count** of how much content matches the old URI (named
   graphs, subjects, predicates, object IRIs, literals in GraphDB; `ACL` and
   `metadata` documents in Mongo) and prints it for you to sanity-check.
5. Prompts for confirmation before changing anything (`--confirm-rewrite` to
   skip the prompt, e.g. for scripting).
6. Runs the 5-pass SPARQL rewrite against GraphDB and the matching
   `updateMany` rewrite against Mongo's `ACL`/`metadata` collections.
7. Rewrites `clientUrl`/`persistentUrl` in `application-{PREFIX}.yml`.
8. Re-runs the counts — expect all zeros — and reports whether anything old
   still remains.
9. Stops `graphdb`/`mongo` again, leaving the install fully down just like it
   started (`--leave-up` to skip this and leave them running).

At the end it prints the exact command to bring the full stack back up.

### Notes

- If the dry-run counts in step 4 are all zero, that almost always means
  `--old-persistent-url` doesn't match what's actually stored — the tool will
  ask before continuing anyway.
- The GraphDB repository name and the volume names are never changed by this
  tool — only `clientUrl`/`persistentUrl` inside `application.yml` and the
  URI baked into the stored content are rewritten.

## Commands: `export` / `import` (optional volume relocation)

Use these only if the server itself is moving to different hardware. If
you're only changing the URI on the same server, skip straight to `rewrite`.

### On the source host

```bash
python3 sextans_migrate.py export \
    --path /path/to/PREFIX-Sextans-Sight \
    --outdir ./PREFIX-export
```

This requires the stack to be stopped (same check as `rewrite`). It tars each
volume via `busybox`, computes a SHA-256 checksum for each tarball, and writes
`manifest.json` recording the prefix, source hostname, timestamp, and
per-volume checksums/sizes. Copy the resulting `./PREFIX-export/` directory to
the destination host by whatever means you have — network share, USB key,
whatever's available. No SSH or network connectivity between the two hosts is
required or assumed.

If you don't have the install folder available on the machine you're
exporting from, you can pass `--prefix PREFIX` instead of `--path`, but then
the tool can't verify the stack is stopped — you must check that yourself.

### On the destination host

```bash
python3 sextans_migrate.py import --indir ./PREFIX-export
```

This verifies each tarball's checksum against the manifest before touching
anything — if a file was corrupted or truncated during transfer (a real risk
with USB keys), it stops with an error rather than restoring bad data. Then
it creates fresh docker volumes and untars each one into place.

By default the destination volumes keep the same prefix as recorded in the
manifest. Pass `--prefix NEWPREFIX` only if you deliberately want to rename
it — if you do, you're responsible for updating `docker-compose*.yml` and
`fdp/application-*.yml` to reference the new prefix too, since `import` only
moves volumes.

After `import`, put the install's `docker-compose-{PREFIX}.yml` and
`fdp/application-{PREFIX}.yml` (etc.) in place on the destination host if you
haven't already — `export`/`import` intentionally only handle the docker
volumes, not this config, since it's just plain text you can copy/scp/carry
over yourself. Then, if the URI is also changing as part of this move, run
`rewrite` against the destination install; otherwise just bring the stack up.

## `Migration Plan.txt`

The original hand-written notes this tool automates — the raw SPARQL passes
and the manual `mongosh` recipe — are kept in this folder for reference and
for anyone who needs to do a one-off rewrite by hand instead of using the
script.
