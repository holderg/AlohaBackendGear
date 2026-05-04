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

./aloha_qc_qsub.sh -a ${FLYWHEEL}/input/aloha -b ${FLYWHEEL}/input/Baseline/18_anat_T2w_acq_2DHiResMTL_anat-T2w_acq-2DHiResMTL_20231116134951_18.nii.gz -f ${FLYWHEEL}/input/Followup/18_anat_T2w_acq_2DHiResMTL_anat-T2w_acq-2DHiResMTL_20231219140211_18.nii.gz -L ${FLYWHEEL}/input/Baseline/18_anat_T2w_acq_2DHiResMTL_anat-T2w_acq-2DHiResMTL_20231116134951_18_ASHS-PMC-T2_lfseg_heur_left.nii.gz -R ${FLYWHEEL}/input/Baseline/18_anat_T2w_acq_2DHiResMTL_anat-T2w_acq-2DHiResMTL_20231116134951_18_ASHS-PMC-T2_lfseg_heur_right.nii.gz -s M90195869