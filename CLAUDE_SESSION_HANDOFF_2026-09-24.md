# Session handoff notes -- 2026-09-24 (DPIA v2.0 follow-ups)

**Not committed to git, not part of the project.** Like `CLAUDE_SESSION_HANDOFF_2026-09-10.md`, this
is a note for the next session working in Sextans-Suite. Don't commit it: it points at gaps in the
default install that are only described in general terms in the public DPIA.

## Context

On 2026-09-24 the Data Privacy Impact Assessments were updated to v2.0
(`~/CODE/Data Privacy Impact Assessment/Risk Assessment for Sextans Suite.docx`, plus the
Rare2FAIR copy, which must stay in sync and must never mention Sextans). The previous versions are
in `Previous versions/` in that folder. The DPIA now describes the Virtuoso-based architecture and
the default hardening, and says openly where the default install does not yet follow its own
advice. The items below were either written into the DPIA without being tested, or need doing
before it is distributed.

**Rule for any fix below:** when something is fixed or verified, update the DPIA to match, in both
documents, with identical wording apart from component names. The places to check are the
"Component Shared Logins", "Minimize permissions on mounted folders", SMS2-SMS5 and "Future Work"
sections, and the Virtuoso, CDE-Box Daemon, Severance and FDP Client rows of the risk table.

## 1. Verify: mitigation for the world-readable Fix data folder (UNTESTED claim in the DPIA)

`install-sextans-fix.sh:180` runs `chmod -R o+rwX ./${P}-Sextans-Fix/data`, because `cde-box-daemon`
and `yarrrml-rdfizer` run as a fixed UID that usually doesn't match the host user. So any local user
on the Fix host can read the source CSV and `data/*/triples/*.nq`.

The DPIA tells hosts to "place the installation inside a directory that other local users cannot
enter". The reasoning is that a bind mount is resolved by dockerd (root) when the container is
created, so host permissions on the *parent* directories are not checked for the container process.
**This has not been tested.** To test:

1. `mkdir -m 700 ~/private && cp -r ACME-Sextans-Fix ~/private/`, then bring the stack up from
   there.
2. Run a real transformation (the `Diagnosis.csv` sample) and confirm it lands in Virtuoso.
3. As a *different* local user, confirm that `cat ~<you>/private/ACME-Sextans-Fix/data/*.csv` fails.
4. `docker compose down && up` again and confirm it still works after a restart (a restart
   re-resolves the mount).

If it fails, remove that advice from the DPIA and leave only "dedicated host, no other interactive
users" plus "delete files after load".

Better long-term fixes, which would let the DPIA drop the "we must note" paragraph entirely:

- Give the fixed-UID containers a shared group, `chgrp -R <gid> data && chmod -R 2770 data` (setgid
  directory), instead of `o+rwX`. The containers would need `group_add: [<gid>]` or a matching GID in
  their Dockerfiles.
- Or run `cdeb2`/`yrml` with `user: "${UID}:${GID}"` from `.env`, the way Severance Internal already
  does, and chmod the folder `700`. We own both images, so this is feasible. Check that nothing in
  either image depends on UID 1000 specifically.
- `TODO.md` already tracks optional automatic deletion of the CSV and `.nq` files after a
  confirmed-successful load (a `t.rb`/`transform-cdev2.rb` change).

## 2. Verify: components work with a limited Virtuoso user instead of `dba`

The DPIA now says that `dba` is used **for installation**, and that before real data is loaded or
the system is made public, the admin must create a Virtuoso user with SPARQL read/write permissions
and switch the components to it. It also says that "none of these components need
administrator-level permissions for normal operation". **Neither the procedure nor that claim has
been tested.**

To do:

1. Work out the exact Virtuoso commands and test them against a disposable install. Probably
   something like the following (in Conductor > Interactive SQL, or `isql`):
   ```sql
   DB.DBA.USER_CREATE ('fdpwriter', '<strong password>');
   GRANT SPARQL_SELECT TO "fdpwriter";
   GRANT SPARQL_UPDATE TO "fdpwriter";
   DB.DBA.RDF_DEFAULT_USER_PERMS_SET ('fdpwriter', 3);   -- 1=read, 2=write, 3=both
   ```
   Note: the install's anonymous lockdown is `RDF_DEFAULT_USER_PERMS_SET('nobody', 0)`, so a new
   user probably gets no graph access unless it is granted explicitly (hence the last line). The
   INTERNAL_NOTES pentest section also found that permission changes need a **Virtuoso restart**
   to take effect. Check whether the same applies here.
2. **Sight:** change `spring.rdf...username/password` in `fdp/application-<P>.yml` (currently
   `username: "dba"`) and restart. Then create, edit and delete a metadata record through the FDP
   UI. The FDP metadata-delete path (`RepositoryConnection#remove(null, null, null, context)`) is the
   one most likely to need more than plain SPARQL_UPDATE.
3. **Fix:** change `TRIPLESTORE_USER`/`TRIPLESTORE_PASS` in `.env` and run a transformation. The
   daemon writes with the Graph Store Protocol (Digest `PUT`) **and clears graphs under `baseURI`
   before each load** (the snapshot-replace fix from 2.1.0). Confirm that both work without dba;
   Graph Store Protocol writes may need an extra grant.
4. **dba/dav hardening:** check what Virtuoso 7.2.17 actually allows. I believe `dba` cannot be
   dropped or renamed (only its password changed), and `dav` can be disabled
   (`USER_SET_OPTION('dav', 'DISABLED', 1)`) or given a new password. **Gotcha to check:** the
   INTERNAL_NOTES record that the image applies `DBA_PASSWORD` **on every container start**, not just
   on first init. If the admin changes the dba password by hand but `DBA_PASSWORD=${TRIPLESTORE_PASS}`
   remains in the compose file, the next restart may reset it, or the two may fight. The procedure
   probably has to remove or replace `DBA_PASSWORD` in the compose/`.env` once the components have
   their own user. Verify, then write that into the procedure.
5. **Put the tested procedure into the installation instructions** (`Sight-install/README.md` and
   `Fix-install/README.md`, "Securing your ... server" sections). The DPIA's wording assumes they
   will say this; **they currently don't.** Better still, have the installers do it automatically
   (the DPIA's Future Work lists this).

## 3. MongoDB: root account is a convenience, not a constraint (worth fixing)

The user asked whether Mongo has to use its root account. **Nothing in memory or the code says it
can't be changed.** FDP's `mongo-auth` profile (`FAIRDataPoint` `src/main/resources/application.yml`,
built into `fdpserv2`) takes any `FDP_MONGO_USERNAME`/`FDP_MONGO_PASSWORD`/`FDP_MONGO_AUTH_DB`
(default `admin`). Root is used only because `MONGO_INITDB_ROOT_*` is the one user the official
`mongo` image creates without an init script.

The likely fix is a script in the already-mounted `${P}-mongo-init` volume
(`/docker-entrypoint-initdb.d/`), which runs once on first init:
`db.getSiblingDB('fdp').createUser({user: 'fdp', pwd: ..., roles: [{role: 'readWrite', db: 'fdp'}]})`.
Then point `application-<P>.yml` at that user, with `authentication-database: fdp`. Check the
database name FDP actually uses. Remember that the `MONGO_INITDB_*` variables and init scripts only
take effect on an **empty** data directory. Test a fresh install end to end: admin login returns a
JWT, and the FDP connection log shows the new user. Then update the DPIA's Component Shared Logins
paragraph and Future Work bullet, which currently say root is used and that a limited account is
planned.

## 4. Other doc/installer inconsistencies noticed while writing the DPIA

- **The Sight README contradicts the compose file.** It says the Virtuoso port "is disabled after
  installation", but `Sight-install/docker-compose-template.yml` publishes it on `127.0.0.1`. The
  Fix README says the same. The DPIA describes the actual behaviour (localhost-only). Fix the
  READMEs, or change the compose file if the port really should be closed.
- **FDP default accounts.** The DPIA (SMS4) now says the admin must log in, create a new admin, and
  delete the default accounts **before making the system public**. The Sight README says to do this
  "immediately" but doesn't mention "before public". Consider adding it, and consider whether the
  installer should keep the FDP client port bound to `127.0.0.1` until the admin has done it.
- **The Severance access token and AAI.** The DPIA now says Severance External is intended to sit
  behind an AAI system, that the default token is for testing only, and that the production token
  is held only by the AAI front-end. Severance 1.1.0 (`external/outie.rb`) only compares a single
  static `AUTH_TOKEN`, so the "AAI front-end holds the static token" model is the one that matches
  the code today. If the intent is for Severance to validate AAI-issued tokens itself, that isn't
  built yet, and the DPIA wording would need revisiting when it is. The Severance README should also
  say plainly that the default/example token is for testing only.
- **TLS.** The DPIA "highly encourages" a reverse proxy with the host's own certificates. The FDP
  client port is published on all interfaces (`{FDP_PORT}:80`), and so is Severance External's
  (`3000:3000`). Consider binding both to `127.0.0.1` by default, since a reverse proxy on the same
  host doesn't need them public. That would turn "encouraged" into "the default".
- **`application-<P>.yml` is mode 644** and contains the Virtuoso dba password, the Mongo root
  password and the JWT secret, because the FDP container runs as its own user. The DPIA says so and
  recommends no other interactive users on the Sight host. A tighter fix: `chown` the file to the
  FDP container's UID (100, `spring`) with mode 600, or pass the secrets as environment variables
  instead of a file.

## 5. Rare2FAIR

The Rare2FAIR DPIA already describes this v2.0 behaviour. Per the user, the Rare2FAIR code will be
ported once collaborators have tested Sextans, and the Rare2FAIR DPIA won't be distributed until
then. Anything fixed above must also be ported to Rare2FAIR, and reflected in its DPIA without any
mention of Sextans.
