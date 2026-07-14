#!/usr/bin/env python3
"""
Rewrite the baseURI baked into a Sextans Sight install's GraphDB and MongoDB
content, and update the FDP's own application.yml to match.

Handles the "I tested on localhost, now I have a real server / w3id" migration:
the GraphDB triples and the FDP's Mongo (ACL + metadata collections) both have
the old URI baked into IRIs and stored documents, and need a coordinated
rewrite alongside the clientUrl/persistentUrl fields in application.yml.

Also provides 'export'/'import' to move the underlying docker volumes to a
new host (as a portable tarball + checksummed manifest), for when the server
itself is relocating, not just its URI. Content rewriting and volume
relocation are independent: do either, both, or neither.

Usage:
    python3 sextans_migrate.py rewrite \\
        --path /path/to/PREFIX-Sextans-Sight \\
        --new-persistent-url https://w3id.org/my-organization \\
        [--old-persistent-url http://localhost:7070] \\
        [--new-client-url https://myrealserver.example.org:7070] \\
        [--confirm-rewrite]

    python3 sextans_migrate.py export --path /path/to/PREFIX-Sextans-Sight --outdir ./out
    # ... copy ./out to the destination host ...
    python3 sextans_migrate.py import --indir ./out

If --old-persistent-url is omitted, the current persistentUrl recorded in
fdp/application-{PREFIX}.yml is used (this is what was baked into the
GraphDB/Mongo content when the install was first bootstrapped).
"""

import argparse
import hashlib
import json
import os
import re
import socket
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import requests
from requests.auth import HTTPBasicAuth

MONGO_DB_DEFAULT = "fdp"

SPARQL_PASSES = [
    ("named graph IRIs", """
DELETE {{ GRAPH ?g {{ ?s ?p ?o }} }}
INSERT {{ GRAPH ?newg {{ ?s ?p ?o }} }}
WHERE {{
  GRAPH ?g {{ ?s ?p ?o }}
  FILTER(STRSTARTS(STR(?g), "{old}"))
  BIND(IRI(CONCAT("{new}", STRAFTER(STR(?g), "{old}"))) AS ?newg)
}}"""),
    ("subjects", """
DELETE {{ GRAPH ?g {{ ?s ?p ?o }} }}
INSERT {{ GRAPH ?g {{ ?news ?p ?o }} }}
WHERE {{
  GRAPH ?g {{ ?s ?p ?o }}
  FILTER(isIRI(?s) && STRSTARTS(STR(?s), "{old}"))
  BIND(IRI(CONCAT("{new}", STRAFTER(STR(?s), "{old}"))) AS ?news)
}}"""),
    ("predicates", """
DELETE {{ GRAPH ?g {{ ?s ?p ?o }} }}
INSERT {{ GRAPH ?g {{ ?s ?newp ?o }} }}
WHERE {{
  GRAPH ?g {{ ?s ?p ?o }}
  FILTER(isIRI(?p) && STRSTARTS(STR(?p), "{old}"))
  BIND(IRI(CONCAT("{new}", STRAFTER(STR(?p), "{old}"))) AS ?newp)
}}"""),
    ("objects (IRI positions only)", """
DELETE {{ GRAPH ?g {{ ?s ?p ?o }} }}
INSERT {{ GRAPH ?g {{ ?s ?p ?newo }} }}
WHERE {{
  GRAPH ?g {{ ?s ?p ?o }}
  FILTER(isIRI(?o) && STRSTARTS(STR(?o), "{old}"))
  BIND(IRI(CONCAT("{new}", STRAFTER(STR(?o), "{old}"))) AS ?newo)
}}"""),
    ("literals containing the old baseURI", """
PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
DELETE {{ GRAPH ?g {{ ?s ?p ?o }} }}
INSERT {{ GRAPH ?g {{ ?s ?p ?newo }} }}
WHERE {{
  GRAPH ?g {{ ?s ?p ?o }}
  FILTER(isLiteral(?o) && STRSTARTS(STR(?o), "{old}"))
  BIND(CONCAT("{new}", STRAFTER(STR(?o), "{old}")) AS ?newstr)
  BIND(
    IF(LANG(?o) != "",
       STRLANG(?newstr, LANG(?o)),
       IF(DATATYPE(?o) != xsd:string,
          STRDT(?newstr, DATATYPE(?o)),
          ?newstr)
    ) AS ?newo
  )
}}"""),
]

SPARQL_COUNT_TEMPLATES = [
    ("named graphs", 'SELECT (COUNT(*) AS ?c) WHERE {{ GRAPH ?g {{ ?s ?p ?o }} FILTER(STRSTARTS(STR(?g), "{old}")) }}'),
    ("subjects", 'SELECT (COUNT(*) AS ?c) WHERE {{ GRAPH ?g {{ ?s ?p ?o }} FILTER(isIRI(?s) && STRSTARTS(STR(?s), "{old}")) }}'),
    ("predicates", 'SELECT (COUNT(*) AS ?c) WHERE {{ GRAPH ?g {{ ?s ?p ?o }} FILTER(isIRI(?p) && STRSTARTS(STR(?p), "{old}")) }}'),
    ("objects (IRI)", 'SELECT (COUNT(*) AS ?c) WHERE {{ GRAPH ?g {{ ?s ?p ?o }} FILTER(isIRI(?o) && STRSTARTS(STR(?o), "{old}")) }}'),
    ("literals", 'SELECT (COUNT(*) AS ?c) WHERE {{ GRAPH ?g {{ ?s ?p ?o }} FILTER(isLiteral(?o) && STRSTARTS(STR(?o), "{old}")) }}'),
]

MONGO_COUNT_JS = """
const oldUri = __OLD_PERSISTENT_URL_JSON__;
const re = new RegExp("^" + oldUri.replace(/[.*+?^${}()|[\\]\\\\]/g, "\\\\$&"));
const acl = db.ACL.countDocuments({instanceId: {$regex: re}});
const meta = db.metadata.countDocuments({uri: {$regex: re}});
print(JSON.stringify({acl: acl, metadata: meta}));
"""

MONGO_UPDATE_JS = """
const oldUri = __OLD_PERSISTENT_URL_JSON__;
const newUri = __NEW_URI_JSON__;
const re = new RegExp("^" + oldUri.replace(/[.*+?^${}()|[\\]\\\\]/g, "\\\\$&"));

// Deliberately not using a pipeline-style update with $replaceOne here -
// that aggregation string operator needs MongoDB 4.4+, and these installs
// have been seen running much older servers. find/forEach/updateOne/$set
// with the replacement computed client-side in JS works on essentially any
// MongoDB version, at the cost of one round trip per matched document
// (fine - these collections are FDP metadata, not bulk data).
function rewriteCollection(coll, field) {
  var query = {};
  query[field] = {$regex: re};
  var matched = 0;
  var modified = 0;
  coll.find(query).forEach(function(doc) {
    matched++;
    var setDoc = {};
    setDoc[field] = doc[field].replace(oldUri, newUri);
    var res = coll.updateOne({_id: doc._id}, {$set: setDoc});
    modified += res.modifiedCount;
  });
  return {matched: matched, modified: modified};
}

const aclResult = rewriteCollection(db.ACL, "instanceId");
const metaResult = rewriteCollection(db.metadata, "uri");
print(JSON.stringify({
  acl_matched: aclResult.matched, acl_modified: aclResult.modified,
  meta_matched: metaResult.matched, meta_modified: metaResult.modified
}));
"""


def fatal(msg):
    sys.exit(f"Error: {msg}")


def docker_compose_cmd():
    for cmd in (["docker", "compose"], ["docker-compose"]):
        try:
            subprocess.run(cmd + ["version"], capture_output=True, check=True)
            return cmd
        except (subprocess.CalledProcessError, FileNotFoundError):
            continue
    fatal("no working 'docker compose' plugin or 'docker-compose' binary found.")


def compose(dc_cmd, path, compose_filename, *args, **kw):
    return subprocess.run(dc_cmd + ["-f", compose_filename] + list(args), cwd=str(path), **kw)


def yaml_value(text, key):
    # [ \t]* rather than \s* - the latter matches newlines too, which lets an
    # empty "key:" line (opening a nested block) bleed into the next line's
    # content instead of correctly failing to match and moving on.
    m = re.search(rf'^[ \t]*{re.escape(key)}:[ \t]*(.+?)[ \t]*$', text, re.MULTILINE)
    if not m:
        return None
    return m.group(1).strip().strip('"').strip("'")


# The three named volumes every Sextans Sight install creates. Content
# rewriting, backup, export and import all key off this same list so a role
# ("graphdb") always maps to the same volume name ("{prefix}-graphdb").
VOLUME_ROLES = ("graphdb", "mongo-data", "mongo-init")


def prefix_from_compose_text(text):
    # Installs are usually left as "docker-compose-{PREFIX}.yml", but users
    # are free to rename that file (e.g. to plain "docker-compose.yml") once
    # it's in production, so the filename alone can't be trusted. The prefix
    # is also encoded in the external volume declarations
    # ("{PREFIX}-graphdb:", "{PREFIX}-mongo-data:") - fall back to those.
    for role in VOLUME_ROLES:
        m = re.search(rf'^\s*([A-Za-z0-9_.-]+)-{re.escape(role)}:\s*$', text, re.MULTILINE)
        if m:
            return m.group(1)
    return None


def find_compose_file(path: Path):
    matches = sorted(path.glob("docker-compose*.yml"))
    if len(matches) == 0:
        fatal(f"no docker-compose*.yml found in {path}")
    if len(matches) > 1:
        fatal(f"expected exactly one docker-compose*.yml in {path}, found {len(matches)}: "
              f"{[m.name for m in matches]}")
    compose_path = matches[0]

    m = re.match(r"docker-compose-(.+)\.yml$", compose_path.name)
    if m:
        return compose_path, m.group(1)

    prefix = prefix_from_compose_text(compose_path.read_text())
    if not prefix:
        fatal(
            f"could not determine the install prefix from {compose_path.name} - expected either "
            f"a 'docker-compose-{{PREFIX}}.yml' filename or a '{{PREFIX}}-graphdb:' external "
            f"volume declaration inside it"
        )
    return compose_path, prefix


def find_application_yml(path: Path, prefix: str):
    expected = path / "fdp" / f"application-{prefix}.yml"
    if expected.exists():
        return expected

    # Same story as the compose file: it may have been renamed since install.
    # Fall back to whatever single application*.yml lives under fdp/.
    matches = sorted((path / "fdp").glob("application*.yml")) if (path / "fdp").is_dir() else []
    if len(matches) == 1:
        return matches[0]
    fatal(
        f"expected {expected} to exist - is this a Sextans Sight install? "
        f"(found {len(matches)} candidate(s) under fdp/application*.yml)"
    )


def load_install(path: Path):
    compose_path, prefix = find_compose_file(path)
    app_yml_path = find_application_yml(path, prefix)

    compose_text = compose_path.read_text()
    app_text = app_yml_path.read_text()

    gdb_port_m = re.search(r'127\.0\.0\.1:(\d+):7200', compose_text)
    if not gdb_port_m:
        fatal("could not find GraphDB port binding (127.0.0.1:<port>:7200) in the compose file")

    info = {
        "prefix": prefix,
        "path": path,
        "compose_path": compose_path,
        "app_yml_path": app_yml_path,
        "compose_text": compose_text,
        "app_text": app_text,
        "gdb_port": gdb_port_m.group(1),
        "client_url": yaml_value(app_text, "clientUrl"),
        "persistent_url": yaml_value(app_text, "persistentUrl"),
        "gdb_repo": yaml_value(app_text, "repository"),
        "gdb_user": yaml_value(app_text, "username") or "admin",
        "gdb_pass": yaml_value(app_text, "password") or "root",
    }
    for key in ("client_url", "persistent_url", "gdb_repo"):
        if not info[key]:
            fatal(f"could not read '{key}' out of {app_yml_path}")
    return info


def ensure_down(dc_cmd, path, compose_filename, force):
    result = compose(dc_cmd, path, compose_filename, "ps", "-q", capture_output=True, text=True)
    running = [l for l in result.stdout.splitlines() if l.strip()]
    if running and not force:
        fatal(
            f"{len(running)} container(s) for this install are currently up. "
            f"Run 'docker compose -f {compose_filename} down' first, or pass --force "
            f"if you understand the risk of rewriting content under a live stack."
        )


def volume_name(prefix, role):
    return f"{prefix}-{role}"


def volume_exists(name):
    return subprocess.run(["docker", "volume", "inspect", name], capture_output=True).returncode == 0


def tar_volume_to(volume, dest_dir: Path, filename):
    subprocess.run([
        "docker", "run", "--rm",
        "-v", f"{volume}:/from:ro",
        "-v", f"{dest_dir.resolve()}:/to",
        "busybox", "tar", "czf", f"/to/{filename}", "-C", "/from", "."
    ], check=True)


def untar_into_volume(volume, src_dir: Path, filename):
    subprocess.run([
        "docker", "run", "--rm",
        "-v", f"{volume}:/to",
        "-v", f"{src_dir.resolve()}:/from:ro",
        "busybox", "tar", "xzf", f"/from/{filename}", "-C", "/to"
    ], check=True)


def chown_to_current_user(path: Path):
    # busybox runs as root, so anything it writes into a bind-mounted host
    # directory ends up root-owned - fine for docker, but annoying for a
    # human trying to copy the result onto a USB key without sudo.
    if not hasattr(os, "getuid"):
        return
    subprocess.run([
        "docker", "run", "--rm",
        "-v", f"{path.parent.resolve()}:/to",
        "busybox", "chown", f"{os.getuid()}:{os.getgid()}", f"/to/{path.name}"
    ], check=True)


def sha256_file(path: Path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def backup_volumes(prefix, backup_dir: Path):
    backup_dir.mkdir(parents=True, exist_ok=True)
    for role in VOLUME_ROLES:
        vol = volume_name(prefix, role)
        if not volume_exists(vol):
            print(f"  (skip: volume {vol} not found)")
            continue
        filename = f"{vol}.tar.gz"
        print(f"  backing up {vol} -> {backup_dir / filename}")
        tar_volume_to(vol, backup_dir, filename)
        chown_to_current_user(backup_dir / filename)


def wait_for_graphdb(base_url, auth, timeout=300):
    deadline = time.time() + timeout
    last_err = None
    attempt = 0
    while time.time() < deadline:
        attempt += 1
        try:
            r = requests.get(f"{base_url}/rest/repositories", auth=auth, timeout=5)
            if r.status_code == 200:
                return
            last_err = f"HTTP {r.status_code}: {r.text[:300]}"
        except requests.RequestException as e:
            last_err = str(e)
        if attempt % 10 == 0:
            print(f"  ... still waiting for GraphDB ({int(time.time() - (deadline - timeout))}s elapsed, "
                  f"last response: {last_err})")
        time.sleep(3)
    fatal(f"timed out waiting for GraphDB to become ready. Last error: {last_err}\n"
          f"(on a large/real dataset this can legitimately take longer than the {timeout}s default - "
          f"pass --db-timeout to raise it, e.g. --db-timeout 900)")


def detect_mongo_shell(dc_cmd, path, compose_filename, timeout=60):
    # Older fairdatasystems/mdb tags only ship the legacy "mongo" shell -
    # "mongosh" was bundled starting later. Try both rather than assuming.
    # This only needs the container process to be alive, not mongod itself
    # to be accepting connections yet, so it can run before the readiness wait.
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        for candidate in ("mongosh", "mongo"):
            r = compose(dc_cmd, path, compose_filename, "exec", "-T", "mongo", "which", candidate,
                        capture_output=True, text=True)
            if r.returncode == 0:
                return candidate
            last = f"exit code {r.returncode}, stderr: {r.stderr.strip()!r}"
        time.sleep(2)
    fatal(f"could not find either 'mongosh' or 'mongo' inside the mongo container. Last error: {last}")


def wait_for_mongo(dc_cmd, path, compose_filename, mongo_shell, timeout=300):
    deadline = time.time() + timeout
    last = None
    attempt = 0
    while time.time() < deadline:
        attempt += 1
        r = compose(dc_cmd, path, compose_filename, "exec", "-T", "mongo", mongo_shell,
                     "--quiet", "--eval", "db.runCommand({ping:1}).ok",
                     capture_output=True, text=True)
        if r.returncode == 0 and "1" in r.stdout:
            return
        last = f"exit code {r.returncode}, stdout: {r.stdout.strip()!r}, stderr: {r.stderr.strip()!r}"
        if attempt % 10 == 0:
            print(f"  ... still waiting for MongoDB ({int(time.time() - (deadline - timeout))}s elapsed, "
                  f"last attempt: {last})")
        time.sleep(3)
    fatal(f"timed out waiting for MongoDB to become ready. Last attempt: {last}\n"
          f"(on a large/real dataset this can legitimately take longer than the {timeout}s default - "
          f"pass --db-timeout to raise it, e.g. --db-timeout 900.)")


def sparql_query(base_url, repo, auth, query):
    r = requests.post(
        f"{base_url}/repositories/{repo}",
        data={"query": query},
        headers={"Accept": "application/sparql-results+json"},
        auth=auth, timeout=60,
    )
    r.raise_for_status()
    return r.json()


def sparql_update(base_url, repo, auth, update):
    r = requests.post(
        f"{base_url}/repositories/{repo}/statements",
        data=update.encode("utf-8"),
        headers={"Content-Type": "application/sparql-update"},
        auth=auth, timeout=300,
    )
    r.raise_for_status()


def sparql_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def graphdb_counts(base_url, repo, auth, old_persistent_url):
    old = sparql_escape(old_persistent_url)
    counts = {}
    for label, template in SPARQL_COUNT_TEMPLATES:
        data = sparql_query(base_url, repo, auth, template.format(old=old))
        binding = data["results"]["bindings"][0]["c"]["value"]
        counts[label] = int(binding)
    return counts


def mongo_eval(dc_cmd, path, compose_filename, mongo_shell, script, mongo_db):
    return compose(dc_cmd, path, compose_filename, "exec", "-T", "mongo", mongo_shell,
                    "--quiet", mongo_db, "--eval", script,
                    capture_output=True, text=True)


def mongo_counts(dc_cmd, path, compose_filename, mongo_shell, old_persistent_url, mongo_db):
    script = MONGO_COUNT_JS.replace("__OLD_PERSISTENT_URL_JSON__", json.dumps(old_persistent_url))
    r = mongo_eval(dc_cmd, path, compose_filename, mongo_shell, script, mongo_db)
    if r.returncode != 0:
        fatal(f"mongo count query failed:\n{r.stdout}\n{r.stderr}")
    try:
        return json.loads(r.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        fatal(f"could not parse mongo count output:\n{r.stdout}")


def print_counts(title, gdb_counts, m_counts):
    print(f"\n{title}")
    for label, c in gdb_counts.items():
        print(f"  GraphDB {label:<32} {c}")
    print(f"  Mongo   ACL.instanceId matches           {m_counts['acl']}")
    print(f"  Mongo   metadata.uri matches              {m_counts['metadata']}")


def rewrite_app_yaml(text, new_client_url, new_persistent_url):
    text = re.sub(r'^(\s*clientUrl:\s*).+$', lambda m: m.group(1) + new_client_url, text, flags=re.MULTILINE)
    text = re.sub(r'^(\s*persistentUrl:\s*).+$', lambda m: m.group(1) + new_persistent_url, text, flags=re.MULTILINE)
    return text


def confirm(prompt):
    return input(f"{prompt} [y/N] ").strip().lower() in ("y", "yes")


def cmd_rewrite(args):
    path = Path(args.path).resolve()
    if not path.is_dir():
        fatal(f"{path} is not a directory")

    info = load_install(path)
    prefix = info["prefix"]
    old_persistent_url = args.old_persistent_url or info["persistent_url"]
    new_persistent_url = args.new_persistent_url
    new_client_url = args.new_client_url or new_persistent_url
    mongo_db = args.mongo_db

    base_url = f"http://127.0.0.1:{info['gdb_port']}"
    auth = HTTPBasicAuth(info["gdb_user"], info["gdb_pass"])

    print("Sextans Sight content migration")
    print("================================")
    print(f"  install path       : {path}")
    print(f"  prefix             : {prefix}")
    print(f"  GraphDB repository : {info['gdb_repo']}  (via {base_url})")
    print(f"  old URI            : {old_persistent_url}")
    print(f"  new persistentUrl  : {new_persistent_url}")
    print(f"  new clientUrl      : {new_client_url}")
    print(f"  (current clientUrl was {info['client_url']})")

    if old_persistent_url == new_persistent_url:
        fatal("old URI and new persistentUrl are identical - nothing to do")

    dc_cmd = docker_compose_cmd()
    compose_filename = info["compose_path"].name

    ensure_down(dc_cmd, path, compose_filename, args.force)

    if not args.skip_backup:
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        backup_dir = path / "migration-backup" / f"{prefix}-{timestamp}"
        print(f"\nBacking up volumes to {backup_dir} ...")
        backup_volumes(prefix, backup_dir)
    else:
        print("\n(--skip-backup given: no volume backup taken)")

    print("\nStarting graphdb + mongo ...")
    compose(dc_cmd, path, compose_filename, "up", "-d", "graphdb", "mongo", check=True)
    mongo_shell = detect_mongo_shell(dc_cmd, path, compose_filename)
    print(f"  using '{mongo_shell}' as the mongo shell")
    wait_for_graphdb(base_url, auth, timeout=args.db_timeout)
    wait_for_mongo(dc_cmd, path, compose_filename, mongo_shell, timeout=args.db_timeout)
    print("  both services are up.")

    gdb_before = graphdb_counts(base_url, info["gdb_repo"], auth, old_persistent_url)
    mongo_before = mongo_counts(dc_cmd, path, compose_filename, mongo_shell, old_persistent_url, mongo_db)
    print_counts("Matches found for the old URI (dry run):", gdb_before, mongo_before)

    if sum(gdb_before.values()) == 0 and sum(mongo_before.values()) == 0:
        print("\nNo content matched the old URI - check --old-persistent-url is correct.")
        if not args.force and not confirm("Continue anyway?"):
            fatal("aborted - nothing matched --old-persistent-url")

    if not args.confirm_rewrite and not confirm("\nProceed with rewriting the above content?"):
        fatal("aborted by user")

    print("\nRewriting GraphDB content ...")
    for label, template in SPARQL_PASSES:
        query = template.format(old=sparql_escape(old_persistent_url), new=sparql_escape(new_persistent_url))
        print(f"  pass: {label}")
        sparql_update(base_url, info["gdb_repo"], auth, query)

    print("\nRewriting MongoDB content ...")
    script = MONGO_UPDATE_JS.replace("__OLD_PERSISTENT_URL_JSON__", json.dumps(old_persistent_url)) \
                             .replace("__NEW_URI_JSON__", json.dumps(new_persistent_url))
    r = mongo_eval(dc_cmd, path, compose_filename, mongo_shell, script, mongo_db)
    if r.returncode != 0:
        fatal(f"mongo update failed:\n{r.stdout}\n{r.stderr}")
    try:
        result = json.loads(r.stdout.strip().splitlines()[-1])
        print(f"  ACL:      matched {result['acl_matched']}, modified {result['acl_modified']}")
        print(f"  metadata: matched {result['meta_matched']}, modified {result['meta_modified']}")
    except (ValueError, IndexError, KeyError):
        print(f"  (could not parse update result, raw output below)\n{r.stdout}")

    print(f"\nUpdating {info['app_yml_path'].relative_to(path)} ...")
    new_app_text = rewrite_app_yaml(info["app_text"], new_client_url, new_persistent_url)
    info["app_yml_path"].write_text(new_app_text)

    gdb_after = graphdb_counts(base_url, info["gdb_repo"], auth, old_persistent_url)
    mongo_after = mongo_counts(dc_cmd, path, compose_filename, mongo_shell, old_persistent_url, mongo_db)
    print_counts("Remaining matches for the old URI (should be 0):", gdb_after, mongo_after)
    if sum(gdb_after.values()) or sum(mongo_after.values()):
        print("\nWARNING: some old-URI content remains - inspect before going live.")
    else:
        print("\nAll old-URI content has been rewritten.")

    if not args.leave_up:
        print("\nStopping graphdb/mongo (bringing the install back to a fully-down state) ...")
        compose(dc_cmd, path, compose_filename, "down", check=True)
        print(f"\nDone. When ready, start the full stack with:\n  cd {path} && {' '.join(dc_cmd)} -f {compose_filename} up -d")
    else:
        print("\nDone. graphdb/mongo left running (--leave-up); start fdp/fdp_client with:\n"
              f"  cd {path} && {' '.join(dc_cmd)} -f {compose_filename} up -d")


MANIFEST_VERSION = 1


def cmd_export(args):
    if args.path and args.prefix:
        fatal("pass either --path or --prefix, not both")
    if not args.path and not args.prefix:
        fatal("one of --path or --prefix is required")

    if args.path:
        path = Path(args.path).resolve()
        if not path.is_dir():
            fatal(f"{path} is not a directory")
        compose_path, prefix = find_compose_file(path)
        dc_cmd = docker_compose_cmd()
        ensure_down(dc_cmd, path, compose_path.name, args.force)
    else:
        prefix = args.prefix
        print("(--prefix given without --path: cannot verify the stack is stopped - "
              "make sure no graphdb/mongo containers using these volumes are running!)")

    outdir = Path(args.outdir).resolve()
    outdir.mkdir(parents=True, exist_ok=True)

    manifest = {
        "manifest_version": MANIFEST_VERSION,
        "prefix": prefix,
        "exported_at": datetime.now(timezone.utc).isoformat(),
        "source_host": socket.gethostname(),
        "volumes": [],
    }

    print(f"Exporting volumes for prefix '{prefix}' to {outdir} ...")
    for role in VOLUME_ROLES:
        vol = volume_name(prefix, role)
        if not volume_exists(vol):
            print(f"  (skip: volume {vol} not found)")
            continue
        filename = f"{vol}.tar.gz"
        print(f"  {vol} -> {filename}")
        tar_volume_to(vol, outdir, filename)
        chown_to_current_user(outdir / filename)
        digest = sha256_file(outdir / filename)
        manifest["volumes"].append({
            "role": role,
            "volume": vol,
            "file": filename,
            "sha256": digest,
            "bytes": (outdir / filename).stat().st_size,
        })

    if not manifest["volumes"]:
        fatal(f"no volumes found for prefix '{prefix}' - nothing exported")

    manifest_path = outdir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2))
    print(f"\nWrote {manifest_path}")
    print(f"\nCopy the '{outdir}' directory to the destination host (network share, USB key, "
          f"whatever you have - no SSH/network connectivity between the two hosts is required), then run:")
    print(f"  python3 sextans_migrate.py import --indir <copied-path>")


def cmd_import(args):
    indir = Path(args.indir).resolve()
    manifest_path = indir / "manifest.json"
    if not manifest_path.exists():
        fatal(f"{manifest_path} not found - is this an export directory produced by 'export'?")

    manifest = json.loads(manifest_path.read_text())
    if manifest.get("manifest_version") != MANIFEST_VERSION:
        fatal(f"unsupported manifest_version {manifest.get('manifest_version')!r}")

    new_prefix = args.prefix or manifest["prefix"]
    print(f"Importing volumes from {indir}")
    print(f"  exported from host '{manifest['source_host']}' at {manifest['exported_at']}")
    print(f"  source prefix: {manifest['prefix']}  ->  destination prefix: {new_prefix}")
    if new_prefix != manifest["prefix"]:
        print("  NOTE: prefix is changing - you must also update the docker-compose*.yml and "
              "fdp/application-*.yml files to reference the new prefix; this tool only moves volumes.")

    for entry in manifest["volumes"]:
        tar_path = indir / entry["file"]
        if not tar_path.exists():
            fatal(f"{tar_path} referenced by manifest.json is missing")

        print(f"\n  verifying checksum for {entry['file']} ...")
        digest = sha256_file(tar_path)
        if digest != entry["sha256"]:
            fatal(
                f"checksum mismatch for {entry['file']}: expected {entry['sha256']}, got {digest} "
                f"- the file is corrupted or was truncated in transit. Do not proceed; re-copy it."
            )

        dest_vol = volume_name(new_prefix, entry["role"])
        if volume_exists(dest_vol):
            if not args.force:
                fatal(f"volume {dest_vol} already exists on this host - pass --force to replace it")
            print(f"  removing existing volume {dest_vol} (--force)")
            subprocess.run(["docker", "volume", "rm", "-f", dest_vol], check=True)

        print(f"  creating volume {dest_vol} and restoring {entry['file']} ...")
        subprocess.run(["docker", "volume", "create", dest_vol], check=True, capture_output=True)
        untar_into_volume(dest_vol, indir, entry["file"])

    print(f"\nDone. Volumes restored under prefix '{new_prefix}'.")
    print("Next: put the install's docker-compose*.yml and fdp/application-*.yml in place here "
          "(if not already), run 'rewrite' if the URI is changing, then bring the stack up.")


def build_parser():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="command", required=True)

    r = sub.add_parser("rewrite", help="Rewrite old-URI content in GraphDB/Mongo and update application.yml")
    r.add_argument("--path", required=True, help="Path to the {PREFIX}-Sextans-Sight install directory")
    r.add_argument("--old-persistent-url", help="URI to replace (default: current persistentUrl in application.yml)")
    r.add_argument("--new-persistent-url", required=True, help="New persistentUrl (baked into GraphDB/Mongo content)")
    r.add_argument("--new-client-url", help="New clientUrl (default: same as --new-persistent-url)")
    r.add_argument("--mongo-db", default=MONGO_DB_DEFAULT, help=f"Mongo database name (default: {MONGO_DB_DEFAULT})")
    r.add_argument("--db-timeout", type=int, default=300,
                   help="Seconds to wait for graphdb/mongo to become ready before giving up (default: 300)")
    r.add_argument("--skip-backup", action="store_true", help="Skip the pre-migration volume backup")
    r.add_argument("--force", action="store_true", help="Proceed even if containers are already running")
    r.add_argument("--confirm-rewrite", action="store_true",
                   help="Skip the interactive 'proceed with rewriting?' prompt and go ahead")
    r.add_argument("--leave-up", action="store_true", help="Leave graphdb/mongo running afterwards")
    r.set_defaults(func=cmd_rewrite)

    e = sub.add_parser("export", help="Tar up an install's docker volumes + a checksummed manifest for offline transfer")
    e.add_argument("--path", help="Path to the {PREFIX}-Sextans-Sight install directory (derives --prefix, checks the stack is down)")
    e.add_argument("--prefix", help="Prefix to export, if --path isn't available (can't verify the stack is down)")
    e.add_argument("--outdir", required=True, help="Directory to write the tarballs + manifest.json into")
    e.add_argument("--force", action="store_true", help="Proceed even if containers are already running (only applies with --path)")
    e.set_defaults(func=cmd_export)

    i = sub.add_parser("import", help="Restore volumes exported by 'export' into freshly created docker volumes on this host")
    i.add_argument("--indir", required=True, help="Directory produced by 'export' (containing manifest.json)")
    i.add_argument("--prefix", help="Destination prefix (default: the prefix recorded in manifest.json)")
    i.add_argument("--force", action="store_true", help="Replace destination volumes if they already exist")
    i.set_defaults(func=cmd_import)

    return p


def main():
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
