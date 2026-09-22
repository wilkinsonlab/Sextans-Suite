# Stop on the first failed step, so a patch that did not apply can never be
# committed, pushed and scanned as if it had.
set -e

# Refuse to build from a working tree that differs from what is committed. The
# images we own (cdeb2, yrml) are built from these directories with `COPY . /app`,
# so an uncommitted edit either gets baked into a pushed image that no commit
# describes, or -- if made after the build -- silently misses it. Either way the
# deployed image and the repo disagree. (Only the build contexts are checked:
# the generated compose templates and scan output are expected to be dirty.)
dirty=$(git status --porcelain -- ../../Daemon ../../yarrrml-rml)
if [ -n "${dirty}" ]; then
  echo "ABORTING: uncommitted changes in the image build contexts (Daemon/, yarrrml-rml/):" >&2
  echo "${dirty}" >&2
  echo "Commit or stash them, then re-run, so the pushed images match the repo." >&2
  exit 1
fi

timestamp=$(date +"%Y-%m-%d")

# Repos with an auto-patch commit staged, to be opened as a PR at the end of the run -- see the cdeb2
# block below (this pipeline's only Ruby-owned image; care2 is Python and yrml is Java, neither has
# Ruby-specific auto-patch tooling to apply -- see Severance's Security/security-patch.sh for the
# reference implementation this mirrors). Format: one line per entry, "repo_path|branch|title".
AUTOPATCH_QUEUE=$(mktemp)
trap 'rm -f "${AUTOPATCH_QUEUE}"' EXIT

# Opens a PR for a repo with a queued auto-patch commit. Never pushes to or merges into that repo's
# default branch -- only ever a new branch + PR, for a human to review. Assumes `gh` is authenticated
# with push access to the repo's remote.
open_autopatch_pr() {
  local repo_path="$1" branch="$2" title="$3"
  echo ""
  echo "=== opening PR for ${repo_path} (branch ${branch}) ==="
  (cd "${repo_path}" && git push -u origin "${branch}")
  (cd "${repo_path}" && gh pr create --title "${title}" --head "${branch}" --body \
    "Automated Ruby gem CVE patch attempt, opened by \`security-patch.sh\`. Verified: image builds, boots correctly, re-scanned to confirm the finding is actually gone. See the commit message for exactly what changed and why. Not auto-merged -- please review before merging.")
}

# Record which Trivy produced this run's scan results (the scanner is maintained
# by hand on this machine, so it can differ between runs).
echo "Trivy version:"
trivy --version

# Fetch the vulnerability DB and the Java DB up front, as their own retried step.
# Both are large downloads; when Trivy fetched them lazily inside a scan, a slow
# download used up that scan's --timeout and killed the whole run. The scans
# below pass --skip-db-update/--skip-java-db-update and just use this cache.
# (The Java DB is what lets Trivy identify the JARs in fdpserv2 and yrml.)
# Aborts before anything is built or pushed if the download never succeeds.
trivy_db_ok=false
for attempt in 1 2 3; do
  if trivy image --download-db-only && trivy image --download-java-db-only; then
    trivy_db_ok=true
    break
  fi
  echo "Trivy DB download failed (attempt ${attempt}/3)" >&2
  sleep 30
done
if [ "${trivy_db_ok}" != true ]; then
  echo "ABORTING: could not download the Trivy vulnerability/Java databases." >&2
  exit 1
fi

# Archive the previous run's scan results instead of deleting them -- someone
# running an older patched image should still be able to look up what
# vulnerabilities apply to the version they actually have deployed.
mkdir -p ./security_scan_output/old
find ./security_scan_output -maxdepth 1 -type f \( -name '*.json' -o -name '*.csv' \) -exec mv {} ./security_scan_output/old/ \;


# ontotext/graphdb:10.8.14 -- retired. Both Sextans Fix and Sextans Sight now
# run on Virtuoso (below); GraphDB was the one service in the whole suite
# that couldn't be made to run non-root (its own startup re-creates log
# files as root regardless of container --user settings), which is why it
# was replaced rather than patched further. Nothing in this pipeline builds
# or pushes a "gdb" image any more.

# openlink/virtuoso-opensource-7 -- the shared triple store for both Sextans
# Fix and Sextans Sight (actively maintained, vendor-backed, has real
# authentication -- a much better fit than GraphDB for a system meant to
# run in a hospital).
# The -alpine variant is used deliberately: it is much smaller (less attack
# surface), and it is patchable with apk. The Ubuntu variants from 7.2.17-r25
# onward ship with /var/lib/dpkg stripped out, so apt cannot upgrade them and
# Trivy cannot see their OS packages.
image="openlink/virtuoso-opensource-7:7.2.17-alpine"
name="virtuoso"
outputfile=("./security_scan_output/scanresults_${name}_${timestamp}.json")
docker run -d --name ${name} ${image}
echo ""
echo ""
echo "updating ${name}"
docker exec -u root ${name} sh -c "apk update && apk upgrade --no-cache --force-missing-repositories"
# Commit the patched container, with a new name, overwriting the previous version
echo "commit"
docker commit ${name} fairdatasystems/${name}:${timestamp}
docker stop ${name}
docker rm ${name}
echo "push"
docker push fairdatasystems/${name}:${timestamp}
echo "pushed"
VIRTUOSO="fairdatasystems/${name}:${timestamp}"
echo "trivy"
trivy image --skip-db-update --skip-java-db-update --scanners vuln --format json --severity CRITICAL,HIGH  --timeout 1800s fairdatasystems/${name}:${timestamp}  > ${outputfile}
echo "END"


name="fdpserv2"
outputfile=("./security_scan_output/scanresults_${name}_${timestamp}.json")
echo ""
echo ""
echo "building ${name}"
# fdpserv2 is our own build of FDP with the Virtuoso repository-type patch
# (markwilkinson/FAIRDataPoint, branch feature/virtuoso-repository) --
# replacing the old vendor-pull-and-patch of fairdata/fairdatapoint:1.17.6,
# which can't run against Virtuoso at all. Renamed "fdpserv" -> "fdpserv2"
# for the same reason as cdeb2/care2: a same-named image whose source
# fundamentally changed (vendor tag -> our own patched fork) would be a
# worse record than a clean break in the tag history. Clone into a temp dir
# since the source lives in a separate repo from this one.
fdpserv2_clone_dir=$(mktemp -d)
git clone --branch feature/virtuoso-repository --depth 1 \
  https://github.com/markwilkinson/FAIRDataPoint.git "${fdpserv2_clone_dir}"
docker build --build-arg PROJECT_VERSION="${timestamp}" \
  -t fairdatasystems/${name}:${timestamp} "${fdpserv2_clone_dir}"
rm -rf "${fdpserv2_clone_dir}"
echo "push"
docker push fairdatasystems/${name}:${timestamp}
echo "pushed"
FDP2="fairdatasystems/${name}:${timestamp}"
# run a scan to determine success
echo "trivy"
trivy image --skip-db-update --skip-java-db-update --scanners vuln  --format json  --severity CRITICAL,HIGH --timeout 1800s fairdatasystems/${name}:${timestamp}  > ${outputfile}
echo "END"


# fairdata/fairdatapoint-client:1.16.3
image="fairdata/fairdatapoint-client:1.17.1"
name="fdpclient"
outputfile=("./security_scan_output/scanresults_${name}_${timestamp}.json")
echo ""
echo ""
echo "updating ${name}"
docker run -d --name ${name} ${image} tail -f /dev/null
# use the appropriate distribution upgrade tool for that container’s operating system
docker exec -u root ${name} sh -c "apk update && apk upgrade --no-cache --force-missing-repositories"
# Commit the patched container, with a new name, overwriting the previous version
docker commit ${name} fairdatasystems/${name}:${timestamp}
# stop the temporary container
docker stop ${name}
# delete the temporary container
docker rm ${name}
echo "push"
docker push fairdatasystems/${name}:${timestamp}
echo "pushed"
FDPC="fairdatasystems/${name}:${timestamp}"
# run a scan to determine success
trivy image --skip-db-update --skip-java-db-update --scanners vuln  --format json  --severity CRITICAL,HIGH --timeout 1800s fairdatasystems/${name}:${timestamp} > ${outputfile}
echo "END"



# mongo:7.0
image="mongo:7.0"
name="mdb"
outputfile=("./security_scan_output/scanresults_${name}_${timestamp}.json")
docker run -d --name ${name} ${image}
# use the appropriate distribution upgrade tool for that container’s operating system
echo ""
echo ""
echo "updating ${name}"
echo "update"
docker exec ${name} apt-get -y update 
echo "dist-upgrade"
docker exec ${name} apt-get -y dist-upgrade   --fix-missing
echo "autoclean"
docker start ${name}
docker exec ${name} apt-get -y autoclean
# Commit the patched container, with a new name, overwriting the previous version
echo "commit"
docker commit ${name} fairdatasystems/${name}:${timestamp}
# stop the temporary container
docker stop ${name}
# delete the temporary container
docker rm ${name}
echo "push"
docker push fairdatasystems/${name}:${timestamp}
echo "pushed"
MDB="fairdatasystems/${name}:${timestamp}"
# run a scan to determine success
echo "trivy"
trivy image --skip-db-update --skip-java-db-update --scanners vuln  --format json  --severity CRITICAL,HIGH  --timeout 1800s fairdatasystems/${name}:${timestamp}  > ${outputfile}
echo "END"



name="cdeb2"
outputfile=("./security_scan_output/scanresults_${name}_${timestamp}.json")
echo ""
echo ""
echo "building ${name}"
# cdeb2 is an image we own (built from our own Daemon/Dockerfile) -- build fresh
# from source rather than pulling a published base tag and OS-patching it.
# The old approach (docker run markw/cde-box-daemon:0.7.2, apk upgrade, commit)
# went stale silently: that base tag no longer exists on Docker Hub, and even
# when it did, a Dockerfile-level fix (e.g. a non-root USER) landing here would
# never reach the patched image since it was never rebuilt from source.
# Renamed from "cdeb" -> "cdeb2" when the Dockerfile's baked-in CARE-SM clone
# moved from CARE-SM-Implementation (v1) to CARE-Semantic-Model-Version-2 (v2) --
# a same-named image whose source repo silently changed underneath it would be a
# worse record than a clean break in the tag history.
docker build -t fairdatasystems/${name}:${timestamp} ../../Daemon

# Auto-patch attempt for Ruby gem CVEs (see Security/auto_patch_ruby_gems.rb for the two strategies:
# bundle update within an existing constraint for a real dependency; exact-pin + Dockerfile uninstall
# attempt for a phantom default gem). Scans a LOCAL, not-yet-pushed build first, so a declined or
# failed auto-patch attempt never gets pushed under this run's tag.
prepatch_scanfile="./security_scan_output/scanresults_${name}_${timestamp}-prepatch.json"
trivy image --skip-db-update --skip-java-db-update --scanners vuln --format json --severity CRITICAL,HIGH \
  --timeout 1800s "fairdatasystems/${name}:${timestamp}" > "${prepatch_scanfile}"
ruby annotate_gem_shadowing.rb "${prepatch_scanfile}" ../../Daemon || true
autopatch_log=$(ruby auto_patch_ruby_gems.rb ../../Daemon "${prepatch_scanfile}")
echo "${autopatch_log}"
if [ "$(echo "${autopatch_log}" | tail -1)" = "CHANGED" ]; then
  echo "auto-patch made changes to ${name} -- rebuilding to verify before keeping them"
  if docker build -t "${name}:autopatch-${timestamp}" ../../Daemon; then
    # No spec/ suite exists for the Daemon today -- a boot smoke test (does the process stay running,
    # the same check used for Severance's own internal, which also has no HTTP port) is the only gate.
    docker rm -f "${name}-autopatch-smoketest" >/dev/null 2>&1 || true
    docker run -d --name "${name}-autopatch-smoketest" "${name}:autopatch-${timestamp}" >/dev/null
    sleep 3
    boot_ok=1
    if docker ps --filter "name=${name}-autopatch-smoketest" --filter "status=running" \
         --format '{{.Names}}' | grep -q "^${name}-autopatch-smoketest\$"; then
      boot_ok=0
    fi
    docker rm -f "${name}-autopatch-smoketest" >/dev/null 2>&1 || true

    if [ "${boot_ok}" -eq 0 ]; then
      echo "auto-patch verified: build OK, boot OK -- keeping the change"
      docker tag "${name}:autopatch-${timestamp}" "fairdatasystems/${name}:${timestamp}"
      branch="autopatch-gems-${name}-${timestamp}"
      (cd ../../Daemon && git checkout -q -b "${branch}" \
        && git add Gemfile Gemfile.lock Dockerfile \
        && git commit -q -m "Auto-patch Ruby gem CVEs in ${name} ($(date +%Y-%m-%d))

$(echo "${autopatch_log}" | grep '^PATCHED')

Verified: image builds, boots correctly, re-scanned.
Opened automatically by security-patch.sh -- see Security/auto_patch_ruby_gems.rb.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>")
      echo "../../Daemon|${branch}|Auto-patch Ruby gem CVEs in cdeb2 (${timestamp})" >> "${AUTOPATCH_QUEUE}"
    else
      echo "auto-patch FAILED boot verification -- reverting, keeping the pre-autopatch build"
      (cd ../../Daemon && git checkout -q -- Gemfile Gemfile.lock Dockerfile) || true
    fi
  else
    echo "auto-patch rebuild FAILED -- reverting, keeping the pre-autopatch build"
    (cd ../../Daemon && git checkout -q -- Gemfile Gemfile.lock Dockerfile) || true
  fi
  docker rmi "${name}:autopatch-${timestamp}" >/dev/null 2>&1 || true
fi
rm -f "${prepatch_scanfile}"

echo "push"
docker push fairdatasystems/${name}:${timestamp}
echo "pushed"
CDEB2="fairdatasystems/${name}:${timestamp}"
# run a scan to determine success
echo "trivy"
trivy image --skip-db-update --skip-java-db-update --scanners vuln  --format json  --severity CRITICAL,HIGH --timeout 1800s fairdatasystems/${name}:${timestamp}  > ${outputfile}
ruby annotate_gem_shadowing.rb "${outputfile}" ../../Daemon || true
echo "END"


name="care2"
outputfile=("./security_scan_output/scanresults_${name}_${timestamp}.json")
echo ""
echo ""
echo "building ${name}"
# care2 is our own build of the CARE-SM-2 Toolkit (CARE-Semantic-Model-Version-2's
# implementation/Toolkit), replacing the old vendor-pull-and-patch of a
# collaborator's pabloalarconm/care-sm-toolkit image. That old image is a
# different, incompatible model version (CARE-SM v1) -- renamed "care" -> "care2"
# for the same reason as cdeb2, above. Clone into a temp dir since the source
# lives in a separate repo from this one, not a subdirectory we can build
# in-place like ../../Daemon.
care2_clone_dir=$(mktemp -d)
git clone --depth 1 https://github.com/wilkinsonlab/CARE-Semantic-Model-Version-2.git "${care2_clone_dir}"
docker build -t fairdatasystems/${name}:${timestamp} "${care2_clone_dir}/implementation/Toolkit"
rm -rf "${care2_clone_dir}"
echo "push"
docker push fairdatasystems/${name}:${timestamp}
echo "pushed"
CARE2="fairdatasystems/${name}:${timestamp}"
# run a scan to determine success
echo "trivy"
trivy image --skip-db-update --skip-java-db-update --scanners vuln  --format json  --severity CRITICAL,HIGH  --timeout 1800s fairdatasystems/${name}:${timestamp}  > ${outputfile}
echo "END"




name="yrml"
outputfile=("./security_scan_output/scanresults_${name}_${timestamp}.json")
echo ""
echo ""
echo "building ${name}"
# yrml is an image we own (built from our own yarrrml-rml/Dockerfile) -- build
# fresh from source rather than pulling a published base tag and OS-patching
# it. The old approach (docker run markw/yarrrml-rml-ejp:0.1.3, apk upgrade,
# commit) meant Dockerfile-level fixes (pinned upstream versions, the non-root
# USER, npm/maven CVE overrides) never reached the actually-deployed image --
# only OS packages on top of whatever was published under that tag.
docker build -t fairdatasystems/${name}:${timestamp} ../../yarrrml-rml
echo "push"
docker push fairdatasystems/${name}:${timestamp}
echo "pushed"
YRDF="fairdatasystems/${name}:${timestamp}"
# run a scan to determine success
trivy image --skip-db-update --skip-java-db-update --scanners vuln  --format json  --severity CRITICAL,HIGH  --timeout 1800s fairdatasystems/${name}:${timestamp} > ${outputfile}
echo "END"

cp sight-docker-compose-template-template.yml sight-docker-compose-template-tmp.yml
cp fix-docker-compose-template-template.yml fix-docker-compose-template-tmp.yml
cp config-docker-compose-template-template.yml config-docker-compose-template-tmp.yml
cp bootstrap-sight-docker-compose-template-template.yml bootstrap-sight-docker-compose-template-tmp.yml
cp bootstrap-fix-docker-compose-template-template.yml bootstrap-fix-docker-compose-template-tmp.yml
sed -i'' -e "s!{FDP2}!${FDP2}!" "sight-docker-compose-template-tmp.yml"
sed -i'' -e "s!{FDPC}!${FDPC}!" "sight-docker-compose-template-tmp.yml"
sed -i'' -e "s!{VIRTUOSO}!${VIRTUOSO}!" "sight-docker-compose-template-tmp.yml"
sed -i'' -e "s!{MDB}!${MDB}!" "sight-docker-compose-template-tmp.yml"
sed -i'' -e "s!{YRDF}!${YRDF}!" "sight-docker-compose-template-tmp.yml"
sed -i'' -e "s!{CDEB2}!${CDEB2}!" "sight-docker-compose-template-tmp.yml"
sed -i'' -e "s!{CARE2}!${CARE2}!" "sight-docker-compose-template-tmp.yml"

sed -i'' -e "s!{FDP2}!${FDP2}!" "fix-docker-compose-template-tmp.yml"
sed -i'' -e "s!{FDPC}!${FDPC}!" "fix-docker-compose-template-tmp.yml"
sed -i'' -e "s!{VIRTUOSO}!${VIRTUOSO}!" "fix-docker-compose-template-tmp.yml"
sed -i'' -e "s!{MDB}!${MDB}!" "fix-docker-compose-template-tmp.yml"
sed -i'' -e "s!{YRDF}!${YRDF}!" "fix-docker-compose-template-tmp.yml"
sed -i'' -e "s!{CDEB2}!${CDEB2}!" "fix-docker-compose-template-tmp.yml"
sed -i'' -e "s!{CARE2}!${CARE2}!" "fix-docker-compose-template-tmp.yml"

sed -i'' -e "s!{FDP2}!${FDP2}!" "config-docker-compose-template-tmp.yml"
sed -i'' -e "s!{FDPC}!${FDPC}!" "config-docker-compose-template-tmp.yml"
sed -i'' -e "s!{MDB}!${MDB}!" "config-docker-compose-template-tmp.yml"

sed -i'' -e "s!{VIRTUOSO}!${VIRTUOSO}!" "bootstrap-sight-docker-compose-template-tmp.yml"
sed -i'' -e "s!{VIRTUOSO}!${VIRTUOSO}!" "bootstrap-fix-docker-compose-template-tmp.yml"

mv fix-docker-compose-template-tmp.yml ../Fix-install/docker-compose-template.yml
mv sight-docker-compose-template-tmp.yml ../Sight-install/docker-compose-template.yml
mv config-docker-compose-template-tmp.yml ../Sight-install/config/docker-compose-template.yml
mv bootstrap-sight-docker-compose-template-tmp.yml ../Sight-install/bootstrap_sight/docker-compose-template.yml
mv bootstrap-fix-docker-compose-template-tmp.yml ../Fix-install/bootstrap_fix/docker-compose-template.yml

# Open any queued auto-patch PRs (see the cdeb2 block above).
while IFS='|' read -r repo_path branch title; do
  [ -n "${repo_path}" ] && open_autopatch_pr "${repo_path}" "${branch}" "${title}"
done < "${AUTOPATCH_QUEUE}"

ruby parse-security-scans.rb ./security_scan_output/*.json
