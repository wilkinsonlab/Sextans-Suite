#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color
CWD=$PWD
export DOCKER_BUILDKIT=0
export COMPOSE_DOCKER_CLI_BUILD=0

# Detect whether this Docker install uses the modern "docker compose" plugin
# or the legacy standalone "docker-compose" binary, and use whichever works.
if docker compose version >/dev/null 2>&1; then
  DOCKER_COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DOCKER_COMPOSE="docker-compose"
else
  echo -e "${RED}Error: Docker Compose not found. Install either the 'docker compose' plugin or the standalone 'docker-compose' binary.${NC}"
  exit 1
fi


function ctrl_c() {
        $DOCKER_COMPOSE -f "$CWD/bootstrap_fix/docker-compose-${P}.yml" down
        $DOCKER_COMPOSE rm -f "$CWD/bootstrap_fix/docker-compose-${P}.yml" -s
        docker network rm bootstrap_fix_default bootstrap_fix_virtuoso_net

        rm "${CWD}/bootstrap_fix/docker-compose-${P}.yml"

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

echo ""
echo ""
echo ""
echo "Sextans Fix Server Secure Environment Installation"
echo ""
echo ""
echo ""

if [ -z $P ]; then
  read -p "enter a prefix for your components (e.g. euronmd) NOTE: All existing installations IN THE SECURE SPACE with the same prefix will be obliterated!!!!: " P
  if [ -z $P ]; then
    echo "invalid..."
    exit 1
  fi
fi

echo ""
echo ""
echo ""
# GDB_PORT handling
if [ -z "$GDB_PORT" ]; then
  read -p "Enter the port where your Virtuoso database will serve (e.g. 8890): " GDB_PORT
fi

if [ -z "$GDB_PORT" ]; then
  echo "Error: No port specified for Virtuoso."
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

echo ""
echo ""
echo ""
if [ -z $RDF_TRIGGER ]; then
  read -p "Enter the port that will trigger your CSV to CARE-SM Data transformation (e.g. 4567): " RDF_TRIGGER
  if [ -z $RDF_TRIGGER ]; then
    echo "invalid..."
    exit 1
  fi
fi


echo ""
echo ""
echo ""
# Virtuoso DBA password handling
# Virtuoso's `dba` superuser password is set directly from this value via the
# image's own DBA_PASSWORD environment variable at container start -- no
# separate admin-API call needed (unlike GraphDB's REST-based security model).
if [ -z "$GRAPHDB_PASSWORD" ]; then
  echo "Choose a password for Virtuoso's 'dba' superuser account."
  read -s -p "Enter a Virtuoso dba password (min 12 characters): " GRAPHDB_PASSWORD
  echo ""
fi

if [ -z "$GRAPHDB_PASSWORD" ] || [ "${#GRAPHDB_PASSWORD}" -lt 12 ] || [ "$GRAPHDB_PASSWORD" = "root" ] || [ "$GRAPHDB_PASSWORD" = "admin" ] || [ "$GRAPHDB_PASSWORD" = "dba" ]; then
  echo "Error: Virtuoso dba password must be at least 12 characters and not a common default such as 'root', 'admin', or 'dba'."
  exit 1
fi




# if [ -z $BEACON_PORT ]; then
#   read -p  "Enter the port where your Beacon2 will serve (e.g. 8000) (set this, even if not used): " BEACON_PORT
#   if [ -z $BEACON_PORT ]; then
#     echo "invalid..."
#     exit 1
#   fi
# fi


mkdir -p $HOME/tmp
export TMPDIR=$HOME/tmp
# needed by the main.py script
export GDB_PREFIX=$P

# The next few lines clean up any previous installation with this prefix. On a
# fresh, first-ever install there is nothing to clean up, so each of these is
# expected to be a harmless no-op -- silenced rather than left to print scary
# but meaningless "not found"/"requires at least 1 argument" errors.
docker network rm bootstrap_fix_default 2>/dev/null || true
docker ps -a | egrep -oh "${P}-Sextans.*" | xargs -r docker rm
docker rm -f bootstrap_fix-virtuoso-1 2>/dev/null || true
docker volume remove -f "${P}-virtuoso" 2>/dev/null || true

docker volume create "${P}-virtuoso"

echo ""
echo ""
echo -e "${GREEN}Creating Virtuoso and bootstrapping it - this will take about a minute"
echo -e "${NC}"
echo ""

cd bootstrap_fix
cp docker-compose-template.yml "docker-compose-${P}.yml"
sed -i'' -e "s/{PREFIX}/${P}/" "docker-compose-${P}.yml"
sed -i'' -e "s/{GDB_PORT}/${GDB_PORT}/" "docker-compose-${P}.yml"
sed -i'' -e "s%{GDB_PASS}%${GRAPHDB_PASSWORD}%" "docker-compose-${P}.yml"

$DOCKER_COMPOSE -f "docker-compose-${P}.yml" up --build -d
#$DOCKER_COMPOSE -f "docker-compose-${P}.yml" up --build
sleep 60
# Do NOT delete docker-compose-${P}.yml here -- the post-install clean-up below
# still needs it to tear down this bootstrap Virtuoso container/network. Deleting
# it this early made that teardown silently fail ("no such file or directory"),
# leaving the bootstrap container and network orphaned on every install.

echo ""
echo -e "${GREEN}Creating a Sextans Fix Production Server folder in ${NC} ./${P}-Sextans-Fix/"
echo ""

cd ..
rm -rf ./${P}-Sextans-Fix
mkdir ./${P}-Sextans-Fix
cp -r ./Sextans-Fix/data ./${P}-Sextans-Fix/
# cde-box-daemon and yarrrml-rdfizer run as fixed-UID non-root users inside their
# containers, which won't generally match your host UID -- open this bind-mounted
# data directory to any user so both containers can read/write it regardless.
chmod -R o+rwX ./${P}-Sextans-Fix/data
# Only takes effect if the bootstrap step above didn't already create the
# database (see docker-compose-template.yml's own comment on this mount) --
# copied here too so the final compose file is self-contained if this folder
# is later moved elsewhere, per this script's own instructions below.
cp -r ./virtuoso-initdb ./${P}-Sextans-Fix/
cp ./Sextans-Fix/.env_template "./${P}-Sextans-Fix/.env"

cp ./docker-compose-template.yml "./${P}-Sextans-Fix/docker-compose-${P}.yml"
sed -i'' -e "s/{PREFIX}/${P}/" "./${P}-Sextans-Fix/docker-compose-${P}.yml"
sed -i'' -e "s/{GDB_PORT}/${GDB_PORT}/" "./${P}-Sextans-Fix/docker-compose-${P}.yml"
# sed -i'' -e "s/{BEACON_PORT}/${BEACON_PORT}/" "./${P}-Sextans-Fix/docker-compose-${P}.yml"
sed -i'' -e "s/{RDF_TRIGGER}/${RDF_TRIGGER}/" "./${P}-Sextans-Fix/docker-compose-${P}.yml"
sed -i'' -e "s/{SEXTANS_DB_NAME}/${P}-sextans-fix/" "./${P}-Sextans-Fix/.env"
sed -i'' -e "s%{GDB_PASS}%${GRAPHDB_PASSWORD}%" "./${P}-Sextans-Fix/.env"
# sed -i'' -e 's|{GUID}|'"${uri}"'|g' "./${P}-Sextans-Fix/.env"
chmod 600 "./${P}-Sextans-Fix/.env"
echo ""
echo ""
echo -e "${GREEN}Installation Complete!"

echo -e "${GREEN}Now doing post-install clean-up..."

$DOCKER_COMPOSE -f "${CWD}/bootstrap_fix/docker-compose-${P}.yml" down
$DOCKER_COMPOSE -f "${CWD}/bootstrap_fix/docker-compose-${P}.yml" rm -s -f
# `down` above already removes the bootstrap compose project's own network
# (bootstrap_fix_virtuoso_net); bootstrap_fix_default never existed for this
# compose file in the first place. Both are harmless no-ops here -- silenced
# rather than left to print misleading "not found" errors after a clean down.
docker network rm bootstrap_fix_default bootstrap_fix_virtuoso_net 2>/dev/null || true

rm "${CWD}/bootstrap_fix/docker-compose-${P}.yml"

echo ""
echo -e "${GREEN}DONE!"
echo ""
echo ""
echo -e "Please now move into the ${NC} ./${P}-Sextans-Fix/ ${GREEN} folder where the full version of the docker-compose-{P}.yml file lives."
echo ""
echo -e "${GREEN}To start the SECURE ENVIRONMENT SEXTANS FIX DATA SERVER, cd to that folder (or move it elsewhere) and and type:  "
echo -e "$DOCKER_COMPOSE -f docker-compose-${P}.yml up -d ${NC}"
echo ""
echo -e "${GREEN}Security note:${NC} the Virtuoso dba password has already been set to what you provided"
echo -e "during this install, stored (mode 600) in ./${P}-Sextans-Fix/.env. There is nothing further"
echo -e "you need to change there before going into production."
echo ""

