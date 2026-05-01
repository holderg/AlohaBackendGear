#!/bin/bash

IMAGE=$(jq -r '.custom["gear-builder"].image' manifest.json)
BASEDIR=/data/holder/Aloha

# Command:
docker run --rm -it --entrypoint='/bin/bash'\
	-e FLYWHEEL=/flywheel/v0\
        -v /home/holder/.config/flywheel:/root/.config/flywheel \
	-v ${BASEDIR}/input:/flywheel/v0/input\
	-v ${BASEDIR}/output:/flywheel/v0/output\
	$IMAGE

