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
    "CVE-2026-31789": (
        "RESOLVED",
        "OpenSSL heap buffer overflow (libcrypto3, Alpine). Confirmed fixed: the "
        "fdpclient rescan after our apk update/upgrade fix shows 0 vulnerabilities."
    ),
    "CVE-2025-58050": (
        "RESOLVED",
        "PCRE2 heap-buffer-overflow read (Alpine). Confirmed fixed: the fdpclient "
        "rescan after our apk update/upgrade fix shows 0 vulnerabilities."
    ),
    "CVE-2025-68121": (
        "ACCEPT",
        "Go TLS session-resumption bug (mutated ClientCAs/RootCAs between "
        "handshakes) -- affects Go-compiled binaries in the mdb image (gosu / mongo "
        "CLI tools), not mongod itself (C++, not a Trivy target here) and not the "
        "clean Ubuntu OS layer. Inert given our deployment. Also: Red Hat rates it "
        "'important', not critical."
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
}

DEFAULT_DECISIONS = {
    (1, "vendor"): ("TRACK", "Network-exposed, third-party image. No fork by default "
                              "(see project policy) -- bump the pinned tag as soon as "
                              "upstream ships a release containing FixedVersion."),
    (1, "owned"): ("PATCH", "Network-exposed, and we build this image directly -- patch "
                             "immediately, higher urgency than internal-only 'owned' findings "
                             "given real exposure. Currently only applies to fdpserv2, whose "
                             "'owned' classification is itself temporary (see the dedicated "
                             "note in VULNERABILITY_TRIAGE.md) -- revisit this default if it "
                             "moves back to 'vendor'."),
    (2, "vendor"): ("TRACK", "Internal-only, third-party image. No fork by default -- bump "
                              "the pinned tag as soon as upstream ships a release containing "
                              "FixedVersion. Lower urgency than (1, vendor) given no direct "
                              "network exposure."),
    (2, "owned"): ("PATCH", "Internal-only, and we build this image -- bump the "
                             "dependency directly next time this Dockerfile is touched."),
    (2, "collaborator"): ("FLAG-UPSTREAM", "Internal-only, built by a CARE-SM "
                                            "collaborator -- open an issue/PR rather than "
                                            "forking; low urgency given exposure."),
    (2, "wrapper"): ("TRACK", "Internal-only; app-level dependency we don't control the "
                               "source of -- only actionable if it's in the base OS/runtime "
                               "layer of our own Dockerfile."),
    (3, "vendor"): ("ACCEPT", "Inert -- bundled but never invoked/exposed by our "
                               "deployment. Re-verify this reasoning if the deployment "
                               "changes (e.g. if we ever call these CLI tools directly)."),
}


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

        if (image, cve) in existing:
            decision, notes = existing[(image, cve)]
        elif cve in MANUAL_DECISIONS:
            decision, notes = MANUAL_DECISIONS[cve]
        elif shadowed == "yes":
            # See annotate_gem_shadowing.rb: every package contributing to this finding is a stale
            # default-gem copy that `bundle exec` never actually loads -- not currently exploitable via
            # this app's own code path, unlike the ordinary (exposure, control) default below.
            decision, notes = (
                "SHADOWED",
                "Flagged copy present on disk but never loaded at runtime -- bundle exec resolves a "
                "newer, Gemfile-pinned version instead (RubyGems refuses to uninstall this compiled "
                "default gem). See the per-image CSV's BundlerShadowedDetail column. Not currently "
                "exploitable via this app's own code path.",
            )
        else:
            decision, notes = DEFAULT_DECISIONS[(exposure, control)]

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
    sev_rank = {"CRITICAL": 0, "HIGH": 1}
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
