#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Always run relative to this script's own location, regardless of caller's CWD.
cd "$(dirname "$0")"

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

echo ""
echo "This script configures a running Sextans Sight FDP to be ERDERA-compliant."
echo -e "${RED}Nota Bene: This script can only be run ONE TIME against a given FDP. Do not run it again unless you really know what you're doing.${NC}"
echo ""

if [ -z "$FDP_PORT" ]; then
  read -p "What port did you choose for the FDP during your Sextans Sight installation? (e.g. 8000): " FDP_PORT
fi

if [ -z "$FDP_PORT" ]; then
  echo "Error: no port provided."
  exit 1
fi

if ! [[ "$FDP_PORT" =~ ^[0-9]+$ ]] || (( FDP_PORT < 1 || FDP_PORT > 65535 )); then
  echo "Error: Invalid port '$FDP_PORT' – must be a number between 1 and 65535."
  exit 1
fi

export FDP_PORT
export FDP_EMAIL="${FDP_EMAIL:-albert.einstein@example.com}"
export FDP_PASSWORD="${FDP_PASSWORD:-password}"

echo ""
echo -e "${GREEN}Running the ERDERA FDP configuration against http://localhost:${FDP_PORT} ...${NC}"
echo ""

$DOCKER_COMPOSE run --rm --build fdp-config
