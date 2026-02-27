#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color
CWD=$PWD
export DOCKER_BUILDKIT=0
export COMPOSE_DOCKER_CLI_BUILD=0


function ctrl_c() {
        docker compose -f "$CWD/config/docker-compose-${P}.yml" down
        docker compose -f "$CWD/bootstrap_sight/docker-compose-${P}.yml" down
        docker compose rm -f "$CWD/config/docker-compose-${P}.yml" -s
        docker compose rm -f "$CWD/bootstrap_sight/docker-compose-${P}.yml" -s
        docker network rm bootstrap_sight_default bootstrap_sight_graphdb_net
        docker rmi -f bootstrap_sight-graph_db_repo_manager:latest

        rm "${CWD}/config/docker-compose-${P}.yml"
        rm "${CWD}/bootstrap/docker-compose-${P}.yml"
        rm "${CWD}/config/fdp/application-${P}.yml"

        exit 2
}

trap ctrl_c 2


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

production="true"


echo "Sextans Sight Installation in Demilitarized Zone"
echo ""


echo "The first question asks for a 'prefix'."
echo "This is used to compartmentalize your installation, such that you can have multiple Sextans Sight servers running in parallel."
echo "(effectively, it is a namespace for your installation)."
echo "The installer tries to delete all existing containers and volumes with the same prefix, so please be careful when choosing this if you have existing installations you care about!" 
echo ""

if [ -z $P ]; then
  read -p "enter a prefix for your components (e.g. euronmd) NOTE: All existing installations with the same prefix will be obliterated!!!!: " P
  if [ -z $P ]; then
    echo "invalid..."
    exit 1
  fi
fi



echo "The next question asks for your permanent GUID."
echo "If you have a permanent identifier, please be sure that all proxies and redirects are alredy setup and working. "
echo "If you have a proxy, you must know the port that the proxy is pointing to. "
echo "If you are installing just to test things, "
echo "please feel free to use a localhost:PORTXXXX address to answer this question. (you will not be able to register a localhost installation in any registry)"
echo "IN THIS CASE, NOTE: PORTXXXX must match your answer to the 'port for your Sight Server', in the next question!!"
read -p "Your permanent GUID (e.g. https://w3id.org/my-organization): " uri


# FDP_PORT handling
if [ -z "$FDP_PORT" ]; then
  echo "If you have a permanent identifier, you will already have an SSL proxy and redirect. "
  echo "The answer to the next question is the port that the proxy is pointing to. "
  read -p "Enter the port for your Sight Server (e.g. 7070): " FDP_PORT
fi

if [ -z "$FDP_PORT" ]; then
  echo "Error: No port specified for Sight Server."
  exit 1
fi

if ! [[ "$FDP_PORT" =~ ^[0-9]+$ ]] || (( FDP_PORT < 1 || FDP_PORT > 65535 )); then
  echo "Error: Invalid port '$FDP_PORT' – must be a number between 1 and 65535."
  exit 1
fi

if is_banned_port "$FDP_PORT"; then
  echo "Error: Port $FDP_PORT is restricted in many web browsers (including Firefox and Chrome) for security reasons."
  echo "This will prevent users from connecting to your server through those browsers."
  echo "Please choose a different port. Safe common options include 3000, 4000, 5000, 7070, 8080, 8000, or 9000."
  exit 1
fi

# GDB_PORT handling
if [ -z "$GDB_PORT" ]; then
  echo "The next question relates to the GraphDB database that contains your Sight metadata. "
  echo "By default, this will NOT be exposed after installation, but we capture the port number here so that it can easily be switched ON for troubleshooting or maintenance. "
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


mkdir $HOME/tmp
export TMPDIR=$HOME/tmp
# PREFIX needed by the main.py script and docker composes
export FDP_PREFIX=$P

docker network rm bootstrap_sight__default
# this next line might throw an error if there was never a previous installation - that's fine!
docker ps -a | egrep -oh "${P}-Sextans.*" | xargs docker rm
docker rm -f  bootstrap_sight_graphdb_1 config_fdp_1 config_fdp_client_1
docker volume remove -f "${P}-graphdb ${P}-fdp-client-assets ${P}-fdp-client-css ${P}-fdp-client-scss ${P}-fdp-server ${P}-mongo-data ${P}-mongo-init"

docker volume create "${P}-graphdb"
docker volume create "${P}-sight-server"
docker volume create "${P}-sight-client-assets"
docker volume create "${P}-sight-client-scss"
docker volume create "${P}-mongo-data"
docker volume create "${P}-mongo-init"


echo ""
echo ""
echo -e "${GREEN}Creating GraphDB and bootstrapping it - this will take about a minute"
echo -e "Go make a nice cup of tea and then come back to check on progress"
echo -e "${NC}"
echo ""

cd bootstrap_sight
cp docker-compose-template.yml "docker-compose-${P}.yml"
sed -i'' -e "s/{PREFIX}/${P}/" "docker-compose-${P}.yml"
docker compose -f "docker-compose-${P}.yml" down
sleep 10

docker compose -f "docker-compose-${P}.yml" up --build -d
sleep 120
rm "docker-compose-${P}.yml"

echo ""
echo -e "${GREEN}Setting up Sextans Sight client and server${NC}"
echo ""




cd ../config

cp docker-compose-template.yml "docker-compose-${P}.yml"
cp ./fdp/application-template.yml "./fdp/application-${P}.yml"
echo "A"
sed -i'' -e "s/{PREFIX}/$P/" "docker-compose-${P}.yml"
echo "B"
sed -i'' -e "s/{FDP_PORT}/$FDP_PORT/" "docker-compose-${P}.yml"
echo "C"
sed -i'' -e "s/{PREFIX}/$P/" "./fdp/application-${P}.yml"
echo "D"
sed -i'' -e "s/{FDP_PORT}/$FDP_PORT/" "./fdp/application-${P}.yml"
echo "E"
sed -i'' -e "s%{GUID}%$uri%" "./fdp/application-${P}.yml"
echo "F"


docker compose -f "docker-compose-${P}.yml" up --build -d
#docker compose -f "docker-compose-${P}.yml" up --build 


sleep 120

echo ""
echo -e "${GREEN}Creating a production server folder in ${NC} ./${P}-Sextans-Sight/"
echo ""

cd ..

cp -r ./Sextans-Sight ./${P}-Sextans-Sight
cp ./docker-compose-template.yml "./${P}-Sextans-Sight/docker-compose-${P}.yml"
cp ./${P}-Sextans-Sight/fdp/application-template.yml "./${P}-Sextans-Sight/fdp/application-${P}.yml"
rm ./${P}-Sextans-Sight/fdp/application-template.yml
cp ./${P}-Sextans-Sight/.env_template "./${P}-Sextans-Sight/.env"
echo "1"
sed -i'' -e "s/{PREFIX}/${P}/" "./${P}-Sextans-Sight/docker-compose-${P}.yml"
echo "2"
sed -i'' -e "s/{FDP_PORT}/${FDP_PORT}/" "./${P}-Sextans-Sight/docker-compose-${P}.yml"
echo "3"
sed -i'' -e "s/{GDB_PORT}/${GDB_PORT}/" "./${P}-Sextans-Sight/docker-compose-${P}.yml"
echo "4"
sed -i'' -e "s/{PREFIX}/${P}/" "./${P}-Sextans-Sight/fdp/application-${P}.yml"
echo "5"
sed -i'' -e "s/{FDP_PORT}/${FDP_PORT}/" "./${P}-Sextans-Sight/fdp/application-${P}.yml"
echo "6"
sed -i'' -e 's|{GUID}|'"${uri}"'|g' "./${P}-Sextans-Sight/fdp/application-${P}.yml"
echo "7"
sed -i'' -e 's|{GUID}|'"${uri}"'|g' "./${P}-Sextans-Sight/.env"

echo -e "${GREEN}Installation Complete!"
echo -e "${GREEN}Now doing post-install clean-up..."

docker compose -f "${CWD}/config/docker-compose-${P}.yml" down
docker compose -f "${CWD}/bootstrap_sight/docker-compose-${P}.yml" down
docker compose -f "${CWD}/config/docker-compose-${P}.yml" rm -s -f
docker compose -f "${CWD}/bootstrap_sight/docker-compose-${P}.yml" rm -s -f
docker network rm bootstrap_sight_default bootstrap_sight_graphdb_net
docker rmi -f bootstrap_sight-graph_db_repo_manager:latest

rm "${CWD}/config/docker-compose-${P}.yml"
rm "${CWD}/bootstrap_sight/docker-compose-${P}.yml"
rm "${CWD}/config/fdp/application-${P}.yml"

echo ""
echo -e "${GREEN}DONE!"
echo ""
echo -e "${GREEN}Please now move into the ${NC} ./${P}-Sextans-Sight/ ${GREEN} folder where the full version of the docker-compose-{P}.yml file lives."
echo ""
echo -e "${GREEN}To start your full Sextans Sight server, cd to that folder or move it elsewhere and and type:  "
echo -e "docker-compose -f docker-compose-${P}.yml up -d ${NC}"
echo ""

