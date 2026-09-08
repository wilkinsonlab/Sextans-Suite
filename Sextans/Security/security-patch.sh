timestamp=$(date +"%Y-%m-%d")

# Archive the previous run's scan results instead of deleting them -- someone
# running an older patched image should still be able to look up what
# vulnerabilities apply to the version they actually have deployed.
mkdir -p ./security_scan_output/old
find ./security_scan_output -maxdepth 1 -type f \( -name '*.json' -o -name '*.csv' \) -exec mv {} ./security_scan_output/old/ \;


image="ontotext/graphdb:10.8.14"
name="gdb"
outputfile=("./security_scan_output/scanresults_${name}_${timestamp}.json")
docker run -d --name ${name} ${image}
echo ""
echo ""
# use the appropriate distribution upgrade tool for that container’s operating system
echo "updating ${name}"
echo "update"
docker exec ${name} apt-get -y update 
echo "dist-upgrade"
docker exec ${name} apt-get -y dist-upgrade --fix-missing
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
GDB="fairdatasystems/${name}:${timestamp}"
# run a scan to determine success
echo "trivy"
trivy image --scanners vuln --format json --severity CRITICAL,HIGH  --timeout 1800s fairdatasystems/${name}:${timestamp}  > ${outputfile}
echo "END"


# fairdata/fairdatapoint:1.17.6
image="fairdata/fairdatapoint:1.17.6"
name="fdpserv"
outputfile=("./security_scan_output/scanresults_${name}_${timestamp}.json")
docker run -d --name ${name} ${image}
# use the appropriate distribution upgrade tool for that container’s operating system
echo ""
echo ""
echo "updating ${name}"
echo "update"
docker exec -u root ${name} sh -c "apk update && apk upgrade --no-cache --force-missing-repositories"
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
FDP="fairdatasystems/${name}:${timestamp}"
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



name="cdeb"
outputfile=("./security_scan_output/scanresults_${name}_${timestamp}.json")
echo ""
echo ""
echo "building ${name}"
# cdeb is an image we own (built from our own Daemon/Dockerfile) -- build fresh
# from source rather than pulling a published base tag and OS-patching it.
# The old approach (docker run markw/cde-box-daemon:0.7.2, apk upgrade, commit)
# went stale silently: that base tag no longer exists on Docker Hub, and even
# when it did, a Dockerfile-level fix (e.g. a non-root USER) landing here would
# never reach the patched image since it was never rebuilt from source.
docker build -t fairdatasystems/${name}:${timestamp} ../../Daemon
echo "push"
docker push fairdatasystems/${name}:${timestamp}
echo "pushed"
CDEB="fairdatasystems/${name}:${timestamp}"
# run a scan to determine success
echo "trivy"
trivy image --scanners vuln  --format json  --severity CRITICAL,HIGH --timeout 1800s fairdatasystems/${name}:${timestamp}  > ${outputfile}
echo "END"


# pabloalarconm/care-sm-toolkit:0.0.19
image="pabloalarconm/care-sm-toolkit:0.3.0"
name="care"
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
CARE="fairdatasystems/${name}:${timestamp}"
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
sed -i'' -e "s!{FDP}!${FDP}!" "sight-docker-compose-template-tmp.yml"
sed -i'' -e "s!{FDPC}!${FDPC}!" "sight-docker-compose-template-tmp.yml"
sed -i'' -e "s!{GDB}!${GDB}!" "sight-docker-compose-template-tmp.yml"
sed -i'' -e "s!{MDB}!${MDB}!" "sight-docker-compose-template-tmp.yml"
sed -i'' -e "s!{YRDF}!${YRDF}!" "sight-docker-compose-template-tmp.yml"
sed -i'' -e "s!{BEACON}!${BEACON}!" "sight-docker-compose-template-tmp.yml"
sed -i'' -e "s!{CDEB}!${CDEB}!" "sight-docker-compose-template-tmp.yml"
sed -i'' -e "s!{CARE}!${CARE}!" "sight-docker-compose-template-tmp.yml"

sed -i'' -e "s!{FDP}!${FDP}!" "fix-docker-compose-template-tmp.yml"
sed -i'' -e "s!{FDPC}!${FDPC}!" "fix-docker-compose-template-tmp.yml"
sed -i'' -e "s!{GDB}!${GDB}!" "fix-docker-compose-template-tmp.yml"
sed -i'' -e "s!{MDB}!${MDB}!" "fix-docker-compose-template-tmp.yml"
sed -i'' -e "s!{YRDF}!${YRDF}!" "fix-docker-compose-template-tmp.yml"
sed -i'' -e "s!{BEACON}!${BEACON}!" "fix-docker-compose-template-tmp.yml"
sed -i'' -e "s!{CDEB}!${CDEB}!" "fix-docker-compose-template-tmp.yml"
sed -i'' -e "s!{CARE}!${CARE}!" "fix-docker-compose-template-tmp.yml"

sed -i'' -e "s!{FDP}!${FDP}!" "config-docker-compose-template-tmp.yml"
sed -i'' -e "s!{FDPC}!${FDPC}!" "config-docker-compose-template-tmp.yml"
sed -i'' -e "s!{MDB}!${MDB}!" "config-docker-compose-template-tmp.yml"

sed -i'' -e "s!{GDB}!${GDB}!" "bootstrap-sight-docker-compose-template-tmp.yml"
sed -i'' -e "s!{GDB}!${GDB}!" "bootstrap-fix-docker-compose-template-tmp.yml"

mv fix-docker-compose-template-tmp.yml ../Fix-install/docker-compose-template.yml
mv sight-docker-compose-template-tmp.yml ../Sight-install/docker-compose-template.yml
mv config-docker-compose-template-tmp.yml ../Sight-install/config/docker-compose-template.yml
mv bootstrap-sight-docker-compose-template-tmp.yml ../Sight-install/bootstrap_sight/docker-compose-template.yml
mv bootstrap-fix-docker-compose-template-tmp.yml ../Fix-install/bootstrap_fix/docker-compose-template.yml

ruby parse-security-scans.rb ./security_scan_output/*.json
