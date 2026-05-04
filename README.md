# AlohaGear

clone
git checkout qc
fw-beta gear build 
# where are the gears ${FLYWHEEL}/{input,output} directories
./run-gear.sh 

# only needs to be done once as ./run-gear.sh uses host storage
./downloadInputFiles

# in the container
./run -C config.test.json
