#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color
CWD=$PWD
export DOCKER_BUILDKIT=0
export COMPOSE_DOCKER_CLI_BUILD=0


function ctrl_c() {
        docker compose -f "$CWD/bootstrap_fix/docker-compose-${P}.yml" down
        docker compose rm -f "$CWD/bootstrap_fix/docker-compose-${P}.yml" -s
        docker network rm bootstrap_fix_default bootstrap_graphdb_net
        docker rmi -f bootstrap_fix_graph_db_repo_manager:latest

        rm "${CWD}/bootstrap/docker-compose-${P}.yml"

        exit 2
}

trap ctrl_c 2

production="true"

# List of ports commonly restricted in web browsers (e.g., Firefox, Chrome) for security reasons
# This is based on historical and current browser implementations to prevent access to legacy/insecure services
banned_ports=(
  1 7 9 11 13 15 17 19 20 21 22 23 25 37 42 43 53 69 77 79 87 95
  101 102 103 104 109 110 111 113 115 117 119 123 135 137 139 143 161 179
  389 427 465 512 514 515 526 530 531 532 540 548 554 556 563 587 601 636
  989 990 993 995 1719 1720 1723 2049 3659 4045 4190 5060 5061 6000 6566
  6665 6666 6667 6668 6669 6679 6697 10080
)

# Helper function to check if a port is banned
is_banned_port() {
  local port="$1"
  for banned in "${banned_ports[@]}"; do
    if [ "$banned" = "$port" ]; then
      return 0  # banned
    fi
  done
  return 1  # not banned
}

echo "Sextans Fix Server Secure Environment Installation"

if [ -z $P ]; then
  read -p "enter a prefix for your components (e.g. euronmd) NOTE: All existing installations IN THE SECURE SPACE with the same prefix will be obliterated!!!!: " P
  if [ -z $P ]; then
    echo "invalid..."
    exit 1
  fi
fi


# GDB_PORT handling
if [ -z "$GDB_PORT" ]; then
  read -p "Enter the port where your GraphDB will serve (e.g. 7200): " GDB_PORT
fi

if [ -z "$GDB_PORT" ]; then
  echo "Error: No port specified for GraphDB."
  exit 1
fi

if ! [[ "$GDB_PORT" =~ ^[0-9]+$ ]] || (( GDB_PORT < 1 || GDB_PORT > 65535 )); then
  echo "Error: Invalid port '$GDB_PORT' – must be a number between 1 and 65535."
  exit 1
fi

if is_banned_port "$GDB_PORT"; then
  echo "Error: Port $GDB_PORT is restricted in many web browsers (including Firefox and Chrome) for security reasons."
  echo "This will prevent users from connecting to your server through those browsers."
  echo "Please choose a different port. Safe common options include 3000, 4000, 5000, 7200, 8080, 8000, or 9000."
  exit 1
fi


if [ -z $RDF_TRIGGER ]; then
  read -p "Enter the port that will trigger your CSV to CARE-SM Data transformation (e.g. 4567): " RDF_TRIGGER
  if [ -z $RDF_TRIGGER ]; then
    echo "invalid..."
    exit 1
  fi
fi




# if [ -z $BEACON_PORT ]; then
#   read -p  "Enter the port where your Beacon2 will serve (e.g. 8000) (set this, even if not used): " BEACON_PORT
#   if [ -z $BEACON_PORT ]; then
#     echo "invalid..."
#     exit 1
#   fi
# fi


mkdir $HOME/tmp
export TMPDIR=$HOME/tmp
# needed by the main.py script
export FDP_PREFIX=$P

docker network rm bootstrap_fix_default
# this next line might throw an error if there was never a previous installation - that's fine!
docker ps -a | egrep -oh "${P}-Sextans.*" | xargs docker rm
docker rm -f  bootstrap_fix_graphdb_1 
docker volume remove -f "${P}-graphdb"

docker volume create "${P}-graphdb"

echo ""
echo ""
echo -e "${GREEN}Creating GraphDB and bootstrapping it - this will take about a minute"
echo -e "Go make a nice cup of tea and then come back to check on progress"
echo -e "${NC}"
echo ""

cd bootstrap_fix
cp docker-compose-template.yml "docker-compose-${P}.yml"
sed -i'' -e "s/{PREFIX}/${P}/" "docker-compose-${P}.yml"

docker compose -f "docker-compose-${P}.yml" up --build -d
sleep 120

echo ""
echo -e "${GREEN}Creating a Sextans Fix Production Server folder in ${NC} ./${P}-Sextans-Fix/"
echo ""

cd ..
mkdir ./${P}-Sextans-Fix
cp -r ./Sextans-Fix/data ./${P}-Sextans-Fix/
cp ./Sextans-Fix/.env_template "./${P}-Sextans-Fix/.env"

cp ./docker-compose-template.yml "./${P}-Sextans-Fix/docker-compose-${P}.yml"
sed -i'' -e "s/{PREFIX}/${P}/" "./${P}-Sextans-Fix/docker-compose-${P}.yml"
sed -i'' -e "s/{GDB_PORT}/${GDB_PORT}/" "./${P}-Sextans-Fix/docker-compose-${P}.yml"
# sed -i'' -e "s/{BEACON_PORT}/${BEACON_PORT}/" "./${P}-Sextans-Fix/docker-compose-${P}.yml"
sed -i'' -e "s/{RDF_TRIGGER}/${RDF_TRIGGER}/" "./${P}-Sextans-Fix/docker-compose-${P}.yml"
sed -i'' -e "s/{SEXTANS_DB_NAME}/${P}-sextans-fix/" "./${P}-Sextans-Fix/.env"
# sed -i'' -e 's|{GUID}|'"${uri}"'|g' "./${P}-Sextans-Fix/.env"
echo ""
echo ""
echo -e "${GREEN}Installation Complete!"

echo -e "${GREEN}Now doing post-install clean-up..."

docker compose -f "${CWD}/bootstrap_fix/docker-compose-${P}.yml" down
docker compose -f "${CWD}/bootstrap_fix/docker-compose-${P}.yml" rm -s -f
docker network rm bootstrap_fix_default bootstrap_fix_graphdb_net
docker rmi -f bootstrap_fix-graph_db_repo_manager:latest

rm "${CWD}/bootstrap_fix/docker-compose-${P}.yml"

echo ""
echo -e "${GREEN}DONE!"
echo ""
echo ""
echo -e "Please now move into the ${NC} ./${P}-Sextans-Fix/ ${GREEN} folder where the full version of the docker-compose-{P}.yml file lives."
echo ""
echo -e "${GREEN}To start the SECURE ENVIRONMENT SEXTANS FIX DATA SERVER, cd to that folder (or move it elsewhere) and and type:  "
echo -e "docker-compose -f docker-compose-${P}.yml up -d ${NC}"
echo ""

