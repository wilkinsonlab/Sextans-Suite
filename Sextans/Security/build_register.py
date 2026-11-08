#!/usr/bin/env python3
"""
Builds/updates vulnerability-register.csv from the Trivy scan CSVs in
security_scan_output/. Existing decisions in the register are preserved
across re-runs (keyed on Image+VulnerabilityID); only genuinely new
CVE/image combinations get a fresh default disposition and land in the
"needs review" bucket.

Usage: python3 build_register.py
"""
import csv
import glob
import os
import re
import collections

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SCAN_DIR = os.path.join(SCRIPT_DIR, "security_scan_output")
REGISTER_PATH = os.path.join(SCRIPT_DIR, "vulnerability-register.csv")

# Static per-image classification. Update this as the fleet changes.
# exposure: 1 = network-exposed (directly or one hop via a proxy in front of it)
#           2 = internal-only (reachable only from other containers on the
#               private compose network, or not currently deployed at all)
#           3 = inert (bundled but never invoked by our deployment)
# control:  owned        = we build this image ourselves, can patch app deps directly
#           collaborator = built by a close collaborator (CARE-SM ecosystem); PR-able
#           wrapper      = we build the Dockerfile but wrap someone else's app code;
#                          we can only patch the base OS/runtime layer, not app deps
#           vendor       = pure third-party image; only lever is tracking upstream releases
IMAGE_INFO = {
    "fdpserv":   {"exposure": 1, "control": "vendor",
                   "note": "FAIR Data Point server. Has no published port of its own, but "
                            "fdp_client (nginx) proxies to it, so its full REST API surface "
                            "is reachable from the public internet via that proxy hop."},
    "fdpserv2":  {"exposure": 1, "control": "owned",
                   "note": "FAIR Data Point server, patched for Virtuoso support. Same exposure "
                            "as the retired 'fdpserv' (fdp_client proxies its full REST API to "
                            "the public internet). Control is 'owned' TEMPORARILY ONLY: this is "
                            "built from our own fork branch (markwilkinson/FAIRDataPoint, "
                            "feature/virtuoso-repository) pending upstream PR acceptance into "
                            "FAIRDataTeam/FAIRDataPoint, not a permanent ownership decision -- "
                            "move this back to 'vendor' once an official FDP release includes "
                            "Virtuoso support and fdpserv2 goes back to vendor-pull-and-patch. "
                            "See the dedicated note in VULNERABILITY_TRIAGE.md."},
    "virtuoso":  {"exposure": 2, "control": "vendor",
                   "note": "Virtuoso triple store, shared by Sextans Fix and Sextans Sight. "
                            "No published port to the internet directly; reachable only from "
                            "fdp/fdp_client (Sight) or cde-box-daemon (Fix) over the internal "
                            "network. Pure vendor image (openlink/virtuoso-opensource-7, "
                            "-alpine variant: much smaller than the Ubuntu one, and "
                            "apk-patchable -- the Ubuntu builds from 7.2.17-r25 onward "
                            "ship without /var/lib/dpkg, so apt can't patch them and "
                            "Trivy can't see their OS packages). Only lever is "
                            "tracking upstream releases."},
    "fdpclient": {"exposure": 1, "control": "vendor",
                   "note": "FDP web client (nginx/Alpine). Directly publishes {FDP_PORT} to "
                            "the internet."},
    "mdb":       {"exposure": 3, "control": "vendor",
                   "note": "Mongo. Confirmed via Trivy Target breakdown: the Ubuntu OS layer "
                            "has 0 vulnerabilities and mongod itself (C++) isn't a scan "
                            "target at all. Every flagged CVE sits on bundled Go CLI "
                            "utilities (mongodump/mongoexport/bsondump/etc.) or gosu, none "
                            "of which our deployment invokes or exposes."},
    # Retired images. "cdeb"/"care" were replaced by "cdeb2"/"care2" when Sextans
    # Fix moved to CARE-SM-2 (kept so an older CSV dropped back into
    # security_scan_output/ still parses). "gdb" (GraphDB) and "beacon"
    # (pabloalarconm/beacon-api4care-sm) have been removed outright: GraphDB was
    # replaced by Virtuoso, and Beacon by our own Beacon2 facade built on
    # Severance (see VULNERABILITY_TRIAGE.md). Neither is built or scanned any
    # more, and archived scans in security_scan_output/old/ are never read.
    "cdeb":      {"exposure": 2, "control": "owned",
                   "note": "cde-box-daemon (CARE-SM v1, retired). Ours to build. Port bound "
                            "to 127.0.0.1 only (host-local), also reachable from "
                            "caresm/yarrrml-rdfizer over the internal network."},
    "care":      {"exposure": 2, "control": "collaborator",
                   "note": "caresm (care-sm-toolkit, CARE-SM v1, retired). Built under a "
                            "CARE-SM collaborator's namespace (pabloalarconm) -- PR-able, "
                            "not a cold fork. No published port; internal network only."},
    "cdeb2":     {"exposure": 2, "control": "owned",
                   "note": "cde-box-daemon (CARE-SM-2). Ours to build. Port bound to "
                            "127.0.0.1 only (host-local), also reachable from "
                            "caresm/yarrrml-rdfizer over the internal network."},
    "care2":     {"exposure": 2, "control": "owned",
                   "note": "caresm (CARE-SM-2 Toolkit). Built from our own source "
                            "(wilkinsonlab/CARE-Semantic-Model-Version-2), not a vendor "
                            "image -- previously a collaborator's pabloalarconm image under "
                            "the retired \"care\" name. No published port; internal network "
                            "only."},
    "yrml":      {"exposure": 2, "control": "wrapper",
                   "note": "yarrrml-rdfizer. We build the Docker wrapper but the app logic "
                            "inside is a third-party project -- we can only fix the base "
                            "OS/build-hygiene layer, not app-level dependencies. No "
                            "published port; internal network only."},
}

# Manually researched dispositions for CVEs that need individual judgment
# (currently: the CRITICALs, plus a couple of notable HIGHs found in passing).
# Keyed by VulnerabilityID; applies across every image it appears in unless
# overridden by a more specific (Image, VulnerabilityID) key.
MANUAL_DECISIONS = {
    "CVE-2026-22732": (
        "REVIEW",
        "Spring Security: HTTP security response headers omitted under certain "
        "conditions (not an injection/RCE bug). Real but lower practical severity "
        "than the CRITICAL label suggests for us; verify our security-header "
        "posture isn't relying solely on Spring's default headers, then track "
        "upstream Spring Boot bump in fdpserv2's next FAIRDataPoint release."
    ),
    "CVE-2026-41293": (
        "REVIEW",
        "Apache Tomcat improper input validation (embedded in fdpserv2's Spring "
        "Boot runtime). Need the specific advisory text to judge exploitability -- "
        "flagged for a closer read before deciding bump vs. accept."
    ),
    "CVE-2026-43512": (
        "REVIEW",
        "Tomcat-related per NVD/VulDB but full advisory text wasn't accessible "
        "during triage. Flagged for a closer read; track upstream in the meantime."
    ),
    "CVE-2026-43515": (
        "REVIEW",
        "Same as CVE-2026-43512 -- Tomcat-related, needs a closer read of the full "
        "advisory before deciding."
    ),
    # CVE-2026-31789 and CVE-2025-58050 used to have global RESOLVED entries here,
    # from when they were confirmed fixed in fdpclient specifically. Removed
    # 2026-11-06: fdpclient dropping a CVE from its own scan already makes that
    # (image, cve) pair disappear from the register on its own (see
    # VULNERABILITY_TRIAGE.md, "Re-running after a new scan") -- a global,
    # CVE-ID-only RESOLVED entry adds no value for that case and is actively
    # dangerous, since MANUAL_DECISIONS applies "across every image it appears
    # in." That's exactly what happened: CVE-2026-31789 reappeared in care2 (a
    # different, still-unpatched image) and was silently marked RESOLVED on the
    # strength of fdpclient's unrelated fix. See the (image, cve)-specific
    # overrides below for the real, currently-open findings.
    "CVE-2025-68121": (
        "NOT REACHABLE",
        "Go TLS session-resumption bug (mutated ClientCAs/RootCAs between "
        "handshakes) -- affects Go-compiled binaries in the mdb image (gosu / mongo "
        "CLI tools), not mongod itself (C++, not a Trivy target here) and not the "
        "clean Ubuntu OS layer. Inert given our deployment. Also: Red Hat rates it "
        "'important', not critical."
    ),
    ("care2", "CVE-2026-31789"): (
        "PATCH",
        "OpenSSL heap buffer overflow, Alpine libcrypto3/libssl3 (installed 3.5.4-r0, "
        "fixed 3.5.6-r0). Root cause found 2026-11-06: care2's Dockerfile "
        "(CARE-Semantic-Model-Version-2/implementation/Toolkit/Dockerfile) never ran "
        "`apk upgrade` at all, unlike cdeb2/yrml's Alpine base -- it just shipped whatever "
        "OS packages came baked into the `python:3.12.11-alpine3.22` base image. That's also "
        "why care2 carried all ~18 of its other HIGH openssl/libuuid/musl/zlib findings this "
        "pass. Fixed by adding `RUN apk update && apk upgrade --no-cache` right after FROM; "
        "next care2 build+rescan should resolve this and most of the rest. (The advisory's "
        "'32-bit systems' caveat doesn't make this ACCEPT-able on its own -- the fix is a "
        "trivial apk bump, not a tradeoff worth skipping.)"
    ),
    "CVE-2026-27820": (
        "REVIEW",
        "Alpine classic buffer overflow, OS-layer in cdeb (which we own). Since we "
        "fixed the apk update/upgrade chaining bug, a fresh cdeb rebuild+rescan "
        "should resolve this automatically -- verify on next scan before spending "
        "more effort."
    ),
    "CVE-2017-1000487": (
        "WRAPPER-ONLY",
        "plexus-utils, old (2017) Maven build-tooling CVE bundled in yrml. Almost "
        "certainly a leftover build-stage artifact (Maven plugin jars) shipped in "
        "the final image, not something executed at runtime. We don't own the app "
        "code, but we do own the Dockerfile -- worth a multi-stage build cleanup to "
        "stop shipping the .m2 cache in the final layer."
    ),
    "CVE-2021-26291": (
        "WRAPPER-ONLY",
        "maven-core, same build-hygiene situation as CVE-2017-1000487."
    ),
    "CVE-2022-29599": (
        "WRAPPER-ONLY",
        "maven-shared-utils, same build-hygiene situation as CVE-2017-1000487."
    ),
    # Reviewed 2026-11-08 (see VULNERABILITY_TRIAGE.md, "2026-11-08 re-scan review").
    ("cdeb2", "CVE-2026-107891"): (
        "PATCH",
        "musl integer overflow in regcomp (Alpine 1.2.6-r2 -> r3), internal-only image we own. "
        "Code execution needs an attacker-controlled regex pattern reaching musl's regcomp; the "
        "Ruby app uses its own Onigmo regex engine, not musl, so there is no obvious reachable "
        "path -- but we patch owned images anyway. r3 was not yet in the Alpine mirror at the "
        "2026-11-08 build (the image still carries r2 after apk upgrade); it lands on the next "
        "rebuild once r3 is published."
    ),
    ("mdb", "CVE-2026-78661"): (
        "NOT REACHABLE",
        "golang.org/x/net/html denial-of-service via crafted HTML input, in bundled Go tooling "
        "(mongodump/mongoexport/etc.) that our MongoDB deployment never invokes and that parses no "
        "HTML in our use -- same inert-Go-tooling basis as mdb's other findings. Re-verify if we "
        "ever call those CLI tools directly."
    ),
}

# Package-wide dispositions, for packages whose findings all share the same reachability argument
# regardless of the individual CVE. Checked after MANUAL_DECISIONS, before the (exposure, control,
# has_fix) default. linux-libc-dev is a Debian source package of C kernel headers only -- a
# container never runs its image's kernel, it runs the host's -- so a kernel CVE reported against it
# is not reachable in the container. Our owned images are Alpine (no linux-libc-dev), so this should
# not currently fire; it's here for parity with Severance and to catch a Debian-based owned image if
# one is ever added. If linux-libc-dev shows up in an owned image, it almost always means a build
# toolchain (build-base/build-essential) leaked into the runtime image -- find out why.
PACKAGE_DECISIONS = {
    "linux-libc-dev": ("NOT REACHABLE", "Kernel CVE reported against linux-libc-dev, which is only C "
                       "header files (no executable code). A container never runs its image's "
                       "kernel; it runs the host's. If this package is in a runtime image at all, a "
                       "build toolchain leaked into it -- find out why. The bug matters for the HOST "
                       "kernel: keep the host patched."),
}

# Defaults for findings nobody has individually researched yet. Keyed on
# (exposure, control, has_fix) -- has_fix is whether Trivy reported a FixedVersion. Telling a reader
# to "patch immediately" when there is nothing to patch to is wrong, so for images we build, a
# finding with no published fix is TRACK ("applied automatically once it exists") rather than PATCH.
# For third-party (vendor/wrapper/collaborator) control we never fork regardless, so has_fix doesn't
# change the disposition, only the wording.
_NO_FIX = (" No fixed version is published upstream yet -- the next security-patch.sh run's "
           "OS-level upgrade (or a dependency bump) applies one automatically once it exists.")
DEFAULT_DECISIONS = {
    (1, "owned", True): ("PATCH", "Network-exposed, and we build this image directly; a fix exists "
                         "-- patch immediately (bump the pinned dependency, or confirm the next "
                         "security-patch.sh run's OS-level upgrade already resolves it). Higher "
                         "urgency than internal-only 'owned' findings given real exposure. Not yet "
                         "individually reviewed for reachability."),
    (1, "owned", False): ("TRACK", "Network-exposed image we build directly, but no upstream fix "
                          "yet." + _NO_FIX + " Not yet individually reviewed for reachability."),
    (2, "owned", True): ("PATCH", "Internal-only, and we build this image; a fix exists -- bump the "
                         "dependency directly next time this Dockerfile is touched (or via the next "
                         "OS-level upgrade). Not yet individually reviewed for reachability."),
    (2, "owned", False): ("TRACK", "Internal-only image we build, but no upstream fix yet." + _NO_FIX +
                          " Not yet individually reviewed for reachability."),
    (1, "vendor", True): ("TRACK", "Network-exposed, third-party image. No fork by default (see "
                          "project policy) -- bump the pinned tag as soon as upstream ships a "
                          "release containing FixedVersion."),
    (1, "vendor", False): ("TRACK", "Network-exposed, third-party image, no upstream fix yet. No "
                           "fork by default -- bump the pinned tag once upstream ships one."),
    (2, "vendor", True): ("TRACK", "Internal-only, third-party image. No fork by default -- bump the "
                          "pinned tag as soon as upstream ships a release containing FixedVersion. "
                          "Lower urgency than (1, vendor) given no direct network exposure."),
    (2, "vendor", False): ("TRACK", "Internal-only, third-party image, no upstream fix yet. No fork "
                           "by default -- bump the pinned tag once upstream ships one. Lower urgency "
                           "than (1, vendor) given no direct network exposure."),
    (2, "collaborator", True): ("FLAG-UPSTREAM", "Internal-only, built by a CARE-SM collaborator -- "
                                "open an issue/PR rather than forking; low urgency given exposure."),
    (2, "collaborator", False): ("FLAG-UPSTREAM", "Internal-only, built by a CARE-SM collaborator, "
                                 "no upstream fix yet -- open an issue/PR rather than forking; low "
                                 "urgency given exposure."),
    (2, "wrapper", True): ("TRACK", "Internal-only; app-level dependency we don't control the source "
                           "of -- only actionable if it's in the base OS/runtime layer of our own "
                           "Dockerfile."),
    (2, "wrapper", False): ("TRACK", "Internal-only; app-level dependency we don't control the "
                            "source of, no upstream fix yet -- only actionable if it's in the base "
                            "OS/runtime layer of our own Dockerfile."),
    (3, "vendor", True): ("NOT REACHABLE", "Inert in our deployment -- either bundled but never "
                          "invoked, or (like the mdb image's gosu, which does run at container "
                          "start) invoked but doing no networking/TLS and reading no untrusted "
                          "input. Re-verify if the deployment changes (e.g. if we ever call these "
                          "CLI tools directly)."),
    (3, "vendor", False): ("NOT REACHABLE", "Inert in our deployment -- either bundled but never "
                           "invoked, or (like the mdb image's gosu, which does run at container "
                           "start) invoked but doing no networking/TLS and reading no untrusted "
                           "input. Re-verify if the deployment changes (e.g. if we ever call these "
                           "CLI tools directly)."),
}

SHADOWED_DECISION = (
    "SHADOWED",
    "Flagged copy present on disk but never loaded at runtime -- bundle exec resolves a "
    "newer, Gemfile-pinned version instead (RubyGems refuses to uninstall this compiled "
    "default gem). See the per-image CSV's BundlerShadowedDetail column. Not currently "
    "exploitable via this app's own code path.",
)

# Notes text this script generates by itself. A prior register row carrying one of these was never a
# human decision, so it is recomputed every run rather than kept -- otherwise improving a default
# (e.g. the has_fix split added 2026-11-08) or adding research above could never replace what an
# earlier run wrote. Includes the pre-2026-11-08 default strings that older registers still carry.
_OLD_GENERATED_NOTES = {
    "Network-exposed, third-party image. No fork by default (see project policy) -- bump the "
    "pinned tag as soon as upstream ships a release containing FixedVersion.",
    "Network-exposed, and we build this image directly -- patch immediately, higher urgency than "
    "internal-only 'owned' findings given real exposure. Currently only applies to fdpserv2, whose "
    "'owned' classification is itself temporary (see the dedicated note in VULNERABILITY_TRIAGE.md) "
    "-- revisit this default if it moves back to 'vendor'.",
    "Internal-only, third-party image. No fork by default -- bump the pinned tag as soon as upstream "
    "ships a release containing FixedVersion. Lower urgency than (1, vendor) given no direct network "
    "exposure.",
    "Internal-only, and we build this image -- bump the dependency directly next time this "
    "Dockerfile is touched.",
    "Internal-only, built by a CARE-SM collaborator -- open an issue/PR rather than forking; low "
    "urgency given exposure.",
    "Internal-only; app-level dependency we don't control the source of -- only actionable if it's "
    "in the base OS/runtime layer of our own Dockerfile.",
    "Inert -- bundled but never invoked/exposed by our deployment. Re-verify this reasoning if the "
    "deployment changes (e.g. if we ever call these CLI tools directly).",
    "Flagged copy present on disk but never loaded at runtime -- bundle exec resolves a newer, "
    "Gemfile-pinned version instead (RubyGems refuses to uninstall this compiled default gem). See "
    "the per-image CSV's BundlerShadowedDetail column. Not currently exploitable via this app's own "
    "code path.",
}
_GENERATED_NOTES = ({n for _, n in DEFAULT_DECISIONS.values()}
                    | {SHADOWED_DECISION[1]}
                    | _OLD_GENERATED_NOTES)


def decide(image, cve, packages, exposure, control, has_fix, shadowed, prior):
    """Disposition for one (image, cve) row. Precedence: researched (image, cve) > researched cve >
    package-wide rule > a prior *human* decision kept in the register > shadowed > (exposure,
    control, has_fix) default. A prior row whose Notes are one this script generated was never a
    human decision, so it is recomputed rather than kept."""
    if (image, cve) in MANUAL_DECISIONS:
        return MANUAL_DECISIONS[(image, cve)]
    if cve in MANUAL_DECISIONS:
        return MANUAL_DECISIONS[cve]
    if packages and all(p in PACKAGE_DECISIONS for p in packages):
        decisions = {PACKAGE_DECISIONS[p] for p in packages}
        if len(decisions) == 1:
            return decisions.pop()
    if prior and prior[1] not in _GENERATED_NOTES:
        # Sticky human decision -- unless the finding has since become shadowed (the Gemfile now
        # pins a fixed version and annotate_gem_shadowing.rb confirmed bundle exec never loads the
        # flagged copy): that decision predates the fix and was never reviewed against it.
        if not (prior[0] != "SHADOWED" and shadowed == "yes"):
            # "ACCEPT" was renamed "NOT REACHABLE" on 2026-11-08 (same meaning). A hand-written row
            # in an older register keeps its notes but gets the new name.
            return ("NOT REACHABLE", prior[1]) if prior[0] == "ACCEPT" else prior
    if shadowed == "yes":
        return SHADOWED_DECISION
    return DEFAULT_DECISIONS[(exposure, control, has_fix)]


def load_rows():
    rows = collections.defaultdict(lambda: {
        "packages": set(), "installed": set(), "fixed": set(),
        "severity": None, "title": None, "url": None,
        "shadowed": set(), "shadowed_detail": set(),
    })
    # Only the current run's CSVs live directly in SCAN_DIR (non-recursive glob);
    # everything superseded gets moved into SCAN_DIR/old/ by security-patch.sh
    # and is intentionally excluded from the register.
    for path in sorted(glob.glob(os.path.join(SCAN_DIR, "*.csv"))):
        image = os.path.basename(path).split("_")[1]
        with open(path, newline="") as f:
            for row in csv.DictReader(f):
                key = (image, row["VulnerabilityID"])
                agg = rows[key]
                agg["packages"].add(row["Package"])
                agg["installed"].add(row["InstalledVersion"])
                fv = row["FixedVersion"].strip()
                if fv and fv != "N/A":
                    agg["fixed"].add(fv)
                agg["severity"] = row["Severity"]
                agg["title"] = row["Title"]
                agg["url"] = row["PrimaryURL"]
                # See annotate_gem_shadowing.rb -- set only for gemspec findings it ran against
                # (currently only cdeb2; care2/yrml aren't Ruby).
                shadowed = (row.get("BundlerShadowed") or "").strip()
                if shadowed:
                    agg["shadowed"].add(shadowed)
                detail = (row.get("BundlerShadowedDetail") or "").strip()
                if detail:
                    agg["shadowed_detail"].add(detail)
    return rows


def shadowed_summary(agg):
    """'yes' only if every contributing package/row was shadowed; 'no' if any real, unaddressed one
    exists; '' if annotate_gem_shadowing.rb never ran against this row."""
    if not agg["shadowed"]:
        return ""
    return "yes" if agg["shadowed"] == {"yes"} else "no"


def load_existing_decisions():
    existing = {}
    if os.path.exists(REGISTER_PATH):
        with open(REGISTER_PATH, newline="") as f:
            for row in csv.DictReader(f):
                key = (row["Image"], row["VulnerabilityID"])
                existing[key] = (row["Decision"], row["Notes"])
    return existing


def main():
    rows = load_rows()
    existing = load_existing_decisions()

    out_rows = []
    for (image, cve), agg in sorted(rows.items()):
        info = IMAGE_INFO[image]
        exposure, control = info["exposure"], info["control"]

        shadowed = shadowed_summary(agg)
        decision, notes = decide(image, cve, agg["packages"], exposure, control,
                                 bool(agg["fixed"]), shadowed, existing.get((image, cve)))

        out_rows.append({
            "Image": image,
            "VulnerabilityID": cve,
            "Severity": agg["severity"],
            "ExposureTier": exposure,
            "Control": control,
            "Package": "; ".join(sorted(agg["packages"])),
            "InstalledVersion": "; ".join(sorted(agg["installed"])),
            "FixedVersion": "; ".join(sorted(agg["fixed"])) or "N/A",
            "Decision": decision,
            "Notes": notes,
            "Title": agg["title"],
            "PrimaryURL": agg["url"],
            "BundlerShadowed": shadowed,
        })

    # Sort: CRITICAL first, then by exposure tier, then image, then CVE
    sev_rank = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3, "UNKNOWN": 4}
    out_rows.sort(key=lambda r: (sev_rank.get(r["Severity"], 9), r["ExposureTier"],
                                  r["Image"], r["VulnerabilityID"]))

    fieldnames = ["Image", "VulnerabilityID", "Severity", "ExposureTier", "Control",
                  "Package", "InstalledVersion", "FixedVersion", "Decision", "Notes",
                  "Title", "PrimaryURL", "BundlerShadowed"]
    with open(REGISTER_PATH, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(out_rows)

    counts = collections.Counter(r["Decision"] for r in out_rows)
    print(f"Wrote {len(out_rows)} rows to {REGISTER_PATH}")
    for d, n in counts.most_common():
        print(f"  {d}: {n}")


if __name__ == "__main__":
    main()
