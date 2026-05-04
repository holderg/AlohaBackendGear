#!/bin/bash

IMAGE=$(jq -r '.custom["gear-builder"].image' manifest.json)

BASEDIR=/data/${USER}/Aloha
[ -n "$1" ] && $bASEDIR="$1"

FlywheelConfigDir="/home/${USER}/.config/flywheel"

echo "Using '$BASEDIR' for Flywheel input/output directories and '$FlywheelConfigDir' for Flywheel credentials"

# Command:
docker run --rm -it --entrypoint='/bin/bash'\
	-e FLYWHEEL=/flywheel/v0\
        -v "${FlywheelConfigDir}":/root/.config/flywheel \
	-v "${BASEDIR}/input":/flywheel/v0/input\
	-v "${BASEDIR}/output":/flywheel/v0/output\
	"$IMAGE"

