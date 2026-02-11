timestamp=$(date +"%Y-%m-%d")

rm -rf ./secury_scan_output/*.json


image="ontotext/graphdb:10.8.2"
name="gdb"
outputfile=("./security_scan_output/scanresults_${name}_${timestamp}.json")
docker run -d --name ${name} ${image}
echo ""
echo ""
# use the appropriate distribution upgrade tool for that container’s operating system
echo "updating ${name}"
echo "update"
docker exec -it ${name} apt-get -y update 
echo "dist-upgrade"
docker exec -it ${name} apt-get -y dist-upgrade --fix-missing
echo "autoclean"
docker start ${name}
docker exec -it ${name} apt-get -y autoclean
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
docker exec -it -u root ${name} apk update && upgrade  --no-cache --force-missing-repositories
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
docker exec -it -u root ${name} update && apk upgrade --no-cache --force-missing-repositories
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
docker exec -it ${name} apt-get -y update 
echo "dist-upgrade"
docker exec -it ${name} apt-get -y dist-upgrade   --fix-missing
echo "autoclean"
docker start ${name}
docker exec -it ${name} apt-get -y autoclean
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



image="markw/cde-box-daemon:0.7.2"
name="cdeb"
outputfile=("./security_scan_output/scanresults_${name}_${timestamp}.json")
docker run -d --name ${name} ${image}
# use the appropriate distribution upgrade tool for that container’s operating system
echo ""
echo ""
echo "updating ${name}"
echo "update"
# use the appropriate distribution upgrade tool for that container’s operating system
docker exec -it -u root ${name} apk update && upgrade --no-cache --force-missing-repositories
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
docker exec -it -u root ${name} apk update && upgrade --no-cache --force-missing-repositories
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




# markw/yarrrml-rml-ejp:0.1.1
image="markw/yarrrml-rml-ejp:0.1.2"
name="yrml"
outputfile=("./security_scan_output/scanresults_${name}_${timestamp}.json")
echo ""
echo ""
echo "updating ${name}"
docker run -d --name ${name} ${image}  tail -f /dev/null
# use the appropriate distribution upgrade tool for that container’s operating system
docker exec -it -u root ${name} apk update && upgrade --no-cache --force-missing-repositories
# Commit the patched container, with a new name, overwriting the previous version
docker commit ${name} fairdatasystems/${name}:${timestamp}
# stop the temporary container
docker stop ${name}
# delete the temporary container
docker rm ${name}
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
docker exec -it -u root ${name} apk update && upgrade --no-cache --force-missing-repositories
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

mv fix-docker-compose-template-tmp.yml ../Fix-install/docker-compose-template.yml
mv sight-docker-compose-template-tmp.yml ../Sight-install/docker-compose-template.yml

ruby parse-security-scans.rb ./security_scan_output/*.json
