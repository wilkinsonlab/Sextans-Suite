timestamp=$(date +"%Y-%m-%d")

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
image="openlink/virtuoso-opensource-7:7.2.17"
name="virtuoso"
outputfile=("./security_scan_output/scanresults_${name}_${timestamp}.json")
docker run -d --name ${name} ${image}
echo ""
echo ""
echo "updating ${name}"
echo "update"
docker exec ${name} apt-get -y update
echo "dist-upgrade"
docker exec ${name} apt-get -y dist-upgrade --fix-missing
echo "autoclean"
docker start ${name}
docker exec ${name} apt-get -y autoclean
echo "commit"
docker commit ${name} fairdatasystems/${name}:${timestamp}
docker stop ${name}
docker rm ${name}
echo "push"
docker push fairdatasystems/${name}:${timestamp}
echo "pushed"
VIRTUOSO="fairdatasystems/${name}:${timestamp}"
echo "trivy"
trivy image --scanners vuln --format json --severity CRITICAL,HIGH  --timeout 1800s fairdatasystems/${name}:${timestamp}  > ${outputfile}
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
trivy image --scanners vuln  --format json  --severity CRITICAL,HIGH --timeout 1800s fairdatasystems/${name}:${timestamp}  > ${outputfile}
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
trivy image --scanners vuln  --format json  --severity CRITICAL,HIGH --timeout 1800s fairdatasystems/${name}:${timestamp} > ${outputfile}
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
trivy image --scanners vuln  --format json  --severity CRITICAL,HIGH  --timeout 1800s fairdatasystems/${name}:${timestamp}  > ${outputfile}
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
echo "push"
docker push fairdatasystems/${name}:${timestamp}
echo "pushed"
CDEB2="fairdatasystems/${name}:${timestamp}"
# run a scan to determine success
echo "trivy"
trivy image --scanners vuln  --format json  --severity CRITICAL,HIGH --timeout 1800s fairdatasystems/${name}:${timestamp}  > ${outputfile}
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
trivy image --scanners vuln  --format json  --severity CRITICAL,HIGH  --timeout 1800s fairdatasystems/${name}:${timestamp}  > ${outputfile}
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
trivy image --scanners vuln  --format json  --severity CRITICAL,HIGH  --timeout 1800s fairdatasystems/${name}:${timestamp} > ${outputfile}
echo "END"

# pabloalarconm/beacon-api4care-sm:4.1.0 
image="pabloalarconm/beacon-api4care-sm:4.1.0"
name="beacon"
outputfile=("./security_scan_output/scanresults_${name}_${timestamp}.json")
echo ""
echo ""
echo "updating ${name}"
docker run -d --name ${name} ${image}
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
BEACON="fairdatasystems/${name}:${timestamp}"
# run a scan to determine success
trivy image --scanners vuln  --format json  --severity CRITICAL,HIGH  --timeout 1800s fairdatasystems/${name}:${timestamp} > ${outputfile}
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
sed -i'' -e "s!{BEACON}!${BEACON}!" "sight-docker-compose-template-tmp.yml"
sed -i'' -e "s!{CDEB2}!${CDEB2}!" "sight-docker-compose-template-tmp.yml"
sed -i'' -e "s!{CARE2}!${CARE2}!" "sight-docker-compose-template-tmp.yml"

sed -i'' -e "s!{FDP2}!${FDP2}!" "fix-docker-compose-template-tmp.yml"
sed -i'' -e "s!{FDPC}!${FDPC}!" "fix-docker-compose-template-tmp.yml"
sed -i'' -e "s!{VIRTUOSO}!${VIRTUOSO}!" "fix-docker-compose-template-tmp.yml"
sed -i'' -e "s!{MDB}!${MDB}!" "fix-docker-compose-template-tmp.yml"
sed -i'' -e "s!{YRDF}!${YRDF}!" "fix-docker-compose-template-tmp.yml"
sed -i'' -e "s!{BEACON}!${BEACON}!" "fix-docker-compose-template-tmp.yml"
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

ruby parse-security-scans.rb ./security_scan_output/*.json
