#!/bin/bash
set -x -e

# Set temp dir in a good way
function make_scratch()
{
    if [[ -d /scratch ]]; then
        mktemp -d /scratch/ashsxv_adni.XXXXXX
    else
        mktemp -d /tmp/ashsxv_adni.XXXXXX
    fi
}

TMPDIR=$(make_scratch)

# Source directory on lambda
# DIR_YUE_ADNI=/data/liyue7/Data/D15_ex_vivo_ASHS/ADNI/formal_inference_larger_patch_updated_0620/${SUBJECT}
# DIR_YUE_ADNI=/data/liyue7/Data/D15_ex_vivo_ASHS/ADNI/formal_inference_larger_patch_updated_0620
DIR_YUE_ADNI=/data/liyue7/Data/D15_ex_vivo_ASHS/ADNI/formal_inference_without_ecunknown_updated_0908
REMOTE_CRASHS_TEMPLATE=/data/pauly2/ashs_xv/work/fold_5/crashs_template/

# Local directory structure
ROOT=/project/hippogang_2/pauly/longi_for_ashs_xv/test_aloha
REMOTE=lambda-picsl.uphs.upenn.edu

ASHS_TEMPLATE=/project/hippogang_2/pauly/wolk/amygdala_ashs_t1/exp02/atlas/final/template/template.nii.gz

ALOHA_ROOT=/project/hippogang_2/pauly/longi_for_ashs_xv/test_aloha/aloha
# ALOHA_ROOT=/project/hippogang_2/longxie/pkg/aloha
ALOHA_CONFIG=$ROOT/aloha_config_custom.sh

export ALOHA_ROOT ALOHA_CONFIG

function generate_manifest()
{
    mkdir -p $ROOT/manifest

    # Get a listing of directories from remote machine
    ssh ${REMOTE} find ${DIR_YUE_ADNI} -type d -maxdepth 2 -mindepth 2 > $TMPDIR/listing.txt

    # Parse to get a manifest of subjects and timepoints
    cat $TMPDIR/listing.txt | while read line; do
        # Get subject and timepoint from the path
        SUBJECT=$(basename $(dirname $line))
        TP=$(basename $line)

        # Print in a format suitable for the script
        echo "${SUBJECT} ${TP}"
    done | sort > $ROOT/manifest/manifest_adni.txt
}

function rsync_images()
{
    # Generate a listing of files that need to be copied with destination paths
    rm -rf $TMPDIR/rsync_list.txt
    cat $ROOT/manifest/manifest_adni.txt | while read line; do
        SUBJECT=$(echo $line | cut -d ' ' -f 1)
        TP=$(echo $line | cut -d ' ' -f 2)

        # Define source and destination paths
        for file in t1_img.nii.gz t2_img.nii.gz; do
            echo $SUBJECT/$TP/$file >> $TMPDIR/rsync_list.txt
            for side in left right; do
                for stage in 1 2; do
                    # echo $SUBJECT/$TP/Dataset421_TwoStageInference/${side}/stage_${stage}_output/MTL_000.nii.gz >> $TMPDIR/rsync_list.txt
		    
		    # New: after fixing RST issue
                    echo $SUBJECT/$TP/Dataset424_TwoStageInferenceNew/${side}/stage_${stage}_output/MTL_000.nii.gz >> $TMPDIR/rsync_list.txt
                done
            done
        done
    done

    # Rsync files from remote to local input directory
    rsync -av --files-from=$TMPDIR/rsync_list.txt ${REMOTE}:${DIR_YUE_ADNI}/ $ROOT/input/
}

function rsync_crashs_template()
{
    mkdir -p $ROOT/manual/crashs_data/templates/ashs_xv
    rsync -av ${REMOTE}:${REMOTE_CRASHS_TEMPLATE}/* $ROOT/manual/crashs_data/templates/ashs_xv/
}

function crashs_post_sample_all
{
    mkdir -p $ROOT/dump
    export PYBATCH_LSF_OPTS="-q bsc_short"
    IFS=' ' cat $ROOT/manifest/manifest_adni.txt | while read SUBJECT TP; do
        echo subject $SUBJECT timepoint $TP

        # Check outputs
        if [[ -f ${ROOT}/work/${SUBJECT}/$TP/crashs_left/${SUBJECT}_${TP}_left_thickness_fine_labels_summary.csv && \
              -f ${ROOT}/work/${SUBJECT}/$TP/crashs_right/${SUBJECT}_${TP}_right_thickness_fine_labels_summary.csv ]]; then
            echo "CRASHS already run for ${SUBJECT} at timepoint ${TP}. Skipping."
            continue
        fi

        $ROOT/pybatch.sh \
            -N "crashs_post_${SUBJECT}_${TP}" -o $ROOT/dump \
            $0 crashs_post_sample_qsub $SUBJECT $TP
    done
    $ROOT/pybatch.sh -w "crashs_post_*"
}

# After CRASHS ran, sample file-scale labels and compute thickness, etc
function crashs_post_sample_qsub()
{
    SUBJECT=$1
    TP=$2
    WORK=${ROOT}/work/${SUBJECT}/$TP

    for SIDE in left right; do

        CDIR=${WORK}/crashs_${SIDE}
        ID=${SUBJECT}_${TP}_${SIDE}

        mesh_image_sample -B -V \
            $CDIR/${ID}_template_thickness.vtk \
            ${WORK}/preproc/${SIDE}_fineseg_t2.nii.gz \
            $CDIR/${ID}_template_thickness_finelabels.vtk \
            fine_labels

        python $ROOT/integrate_thickness.py \
            -m $CDIR/${ID}_template_thickness_finelabels.vtk \
            -o $CDIR/${ID}_thickness_fine_labels_summary.csv \
            -l fine_labels -r VoronoiRadius -i $ID -s $SIDE
        
    done
}


# Perform initial processing and run CRASHS for a single subject/timepoint
function crashs_qsub()
{
    SUBJECT=$1
    TP=$2

    WORK=${ROOT}/work/${SUBJECT}/$TP
    INPUT=${ROOT}/input/${SUBJECT}/$TP

    mkdir -p ${WORK}/preproc/fake_ashs/affine_t1_to_template ${WORK}/preproc/fake_ashs/final

    # Create symlinks to the segmentations in the input directory
    for SIDE in left right; do
        # ln -sf $INPUT/Dataset413_IsotropicExVivo/${SIDE}/output/MTL_000.nii.gz $WORK/preproc/fake_ashs/final/${SUBJECT}_${TP}_${SIDE}_lfseg_heur.nii.gz
	# ${WORK}/preproc/${SIDE}_coarseseg_t2.nii.gz
        ln -sf \
	    ${WORK}/preproc/${SIDE}_coarseseg_t2.nii.gz \
            $WORK/preproc/fake_ashs/final/${SUBJECT}_${TP}_${SIDE}_lfseg_heur.nii.gz
    done

    # Upsample the T2 images for ALOHA
    c3d ${INPUT}/t2_img.nii.gz -resample 100x100x500% -type ushort -o ${WORK}/preproc/t2_iso.nii.gz -as R \
        $WORK/preproc/fake_ashs/final/${SUBJECT}_${TP}_left_lfseg_heur.nii.gz -int 0 -reslice-identity -o ${WORK}/preproc/left_nnunet_seg_t2.nii.gz \
        $WORK/preproc/fake_ashs/final/${SUBJECT}_${TP}_right_lfseg_heur.nii.gz -reslice-identity -o ${WORK}/preproc/right_nnunet_seg_t2.nii.gz
    
    c3d ${INPUT}/t1_img.nii.gz -as R \
        $WORK/preproc/fake_ashs/final/${SUBJECT}_${TP}_left_lfseg_heur.nii.gz -int 0 -reslice-identity -o ${WORK}/preproc/left_nnunet_seg_t1.nii.gz \
        $WORK/preproc/fake_ashs/final/${SUBJECT}_${TP}_right_lfseg_heur.nii.gz -reslice-identity -o ${WORK}/preproc/right_nnunet_seg_t1.nii.gz

    # Neck trim the T1 image to improve registration to the template
    c3d -verbose ${INPUT}/t1_img.nii.gz -as T1 -neck-trim -trim 0vox -push T1 -reslice-identity -o ${WORK}/preproc/t1_trim.nii.gz

    # Rigid registration to the template with a search
    greedy -d 3 -threads 1 -dof 6 -a -m NCC 2x2x2 \
        -i $ASHS_TEMPLATE ${WORK}/preproc/t1_trim.nii.gz \
        -o ${WORK}/preproc/fake_ashs/affine_t1_to_template/t1_to_template_rigid.mat \
        -n 400x0x0x0 -ia-image-centers -search 400 5 5

    # Affine registration to the template
    greedy -d 3 -threads 1 -a -m NCC 2x2x2 \
        -i $ASHS_TEMPLATE ${WORK}/preproc/t1_trim.nii.gz \
        -o ${WORK}/preproc/fake_ashs/affine_t1_to_template/t1_to_template_affine.mat \
        -n 400x80x40x0 -ia ${WORK}/preproc/fake_ashs/affine_t1_to_template/t1_to_template_rigid.mat

    # Run CRASHS in a temporary directory
    TDIR=$(make_scratch)

    # For each side, run CRASHS
    for SIDE in left right; do
        
        ID=${SUBJECT}_${TP}_${SIDE}
        
        # Run CRASHS in temp dir
        mkdir $TDIR/crashs_${SIDE}
        python -m crashs fit \
            -C $ROOT/manual/crashs_data \
            -i ${SUBJECT}_${TP}_${SIDE} \
            -s $SIDE \
            -c heur \
            -d cpu \
            --no-t2-upsample --no-wm-nnunet \
            $WORK/preproc/fake_ashs ashs_xv $TDIR/crashs_${SIDE} 

        # Retain the most important files
        ESSENTIAL_FILES=(
            "preprocess/t2_alveus/tmp/${ID}_ivseg_ashs_upsample.nii.gz"
            "cruise/${ID}_mtl_avg_l2m-mesh-ras.vtk"
            "cruise/${ID}_mtl_gwb_l2m-mesh-ras.vtk"
            "cruise/${ID}_mtl_cwb_l2m-mesh-ras.vtk"
            "cruise/${ID}_mtl_cruise-cortex.nii.gz"
            "fitting/${ID}_fitted_dist_stat.json"
            "fitting/${ID}_fit_lddmm_momenta.vtk"
            "fitting/${ID}_fit_target_reduced.vtk"
            "fitting/${ID}_fitted_omt_match_to_p00.vtk"
            "fitting/${ID}_fitted_omt_match_to_p01.vtk"
            "fitting/${ID}_fitted_omt_match_to_p02.vtk"
            "fitting/${ID}_fitted_omt_match_to_p03.vtk"
            "fitting/${ID}_fitted_omt_match_to_p04.vtk"
            "fitting/${ID}_fitted_omt_match_to_p05.vtk"
            "fitting/${ID}_fitted_omt_match_to_p06.vtk"
            "fitting/${ID}_fitted_omt_match_to_p07.vtk"
            "fitting/${ID}_fitted_omt_match_to_p08.vtk"
            "fitting/${ID}_fitted_omt_match_to_p09.vtk"
            "fitting/${ID}_fitted_omt_match_to_p10.vtk"
            "fitting/${ID}_fitted_lddmm_template_reduced.vtk"
            "thickness/${ID}_template_thickness.vtk"
            "thickness/${ID}_thickness_tetra.vtk"
            "thickness/${ID}_thickness_roi_summary.csv"
        )

        mkdir -p ${WORK}/crashs_${SIDE}
        for fn in "${ESSENTIAL_FILES[@]}"; do
            if [[ -f $TDIR/crashs_${SIDE}/$fn ]]; then
                mkdir -p $(dirname ${WORK}/crashs_${SIDE}/$fn)
                cp $TDIR/crashs_${SIDE}/$fn ${WORK}/crashs_${SIDE}/$(basename $fn)
            else
                echo "Warning: File $TDIR/$fn does not exist."
            fi
        done
    done

    # Final step: using fine-scale labels
    crashs_post_sample_qsub $SUBJECT $TP

<<'NOFINELABELPROP'

    # For each side, propagate the fine-scale labels to the coarse-scale labels
    for SIDE in left right; do
        mkdir -p ${WORK}/crashs_fineseg

        python -m crashs profile_map \
            -c ${TDIR}/crashs_${SIDE} -s ${SUBJECT}_${TP}_${SIDE} \
            -i $WORK/preproc/fake_ashs/final/${SUBJECT}_${TP}_${SIDE}_lfseg_heur.nii.gz \
            -a uclm_label \
            -t $ROOT/manual/crashs_data/templates/ashs_xv/template_left_uclm_labels.vtk \
            -l -k 0.2 \
            -T 1 3 4 5 7 8 9 \
            -H $ROOT/manifest/label_grouping_ashs.csv \
            -o ${WORK}/crashs_fineseg/${SUBJECT}_${TP}_${SIDE}_fineseg.nii.gz

        # Upsample the fine-scale images for ALOHA
        c3d ${WORK}/preproc/t2_iso.nii.gz \
            ${WORK}/crashs_fineseg/${SUBJECT}_${TP}_${SIDE}_fineseg.nii.gz -int 0 -reslice-identity -o ${WORK}/preproc/${SIDE}_fineseg_t2.nii.gz 

        # Generate binary T1-space images for ALOHA
        c3d ${INPUT}/t1_img.nii.gz  ${WORK}/crashs_fineseg/${SUBJECT}_${TP}_${SIDE}_fineseg.nii.gz \
            -thresh 0.5 inf 1 0 -smooth-fast 0.2mm -reslice-identity -thresh 0.5 inf 1 0 \
            -o ${WORK}/preproc/${SIDE}_fineseg_binary_t1space.nii.gz
    done
NOFINELABELPROP

    # Remove the temporary directory
    rm -rf $TDIR
}

function crashs_all
{
    export PYBATCH_LSF_OPTS="-q bsc_short"

    mkdir -p $ROOT/dump
    IFS=' ' cat $ROOT/manifest/manifest_adni.txt | while read SUBJECT TP; do
        echo subject $SUBJECT timepoint $TP

        # Check outputs
        if [[ -f ${ROOT}/work/${SUBJECT}/$TP/crashs_left/${SUBJECT}_${TP}_left_thickness_roi_summary.csv && \
              -f ${ROOT}/work/${SUBJECT}/$TP/crashs_right/${SUBJECT}_${TP}_right_thickness_roi_summary.csv ]]; then
            echo "CRASHS already run for ${SUBJECT} at timepoint ${TP}. Skipping."
            continue
        fi

        $ROOT/pybatch.sh \
            -N "crashs_${SUBJECT}_${TP}" -m 32G -o $ROOT/dump \
            $0 crashs_qsub $SUBJECT $TP
    done
    $ROOT/pybatch.sh -w "crashs_*"
}

function crashs_merge_fine_labels
{
    MANI=$TMPDIR/fine_label_merge_manifest.txt
    rm -rf $MANI
    IFS=' ' cat $ROOT/manifest/manifest_adni.txt | while read SUBJECT TP; do
        BASE=${ROOT}/work/${SUBJECT}/$TP
        MLEFT=${BASE}/crashs_left/${SUBJECT}_${TP}_left_template_thickness_finelabels.vtk
        MRIGHT=${BASE}/crashs_right/${SUBJECT}_${TP}_right_template_thickness_finelabels.vtk

        if [[ -f $MLEFT && -f $MRIGHT ]]; then
            echo ${MLEFT} >> $MANI
            echo ${MRIGHT} >> $MANI
        fi
    done
    mesh_merge_arrays -r $ROOT/manual/crashs_data/templates/ashs_xv/template_shoot_left.vtk \
        -c -B -m $MANI $ROOT/tmp/crashs_fine_labels_merged_left.vtk fine_labels
}


function aloha_preproc_qsub()
{
    SUBJECT=$1
    TP=$2

    WORK=${ROOT}/work/${SUBJECT}/$TP
    INPUT=${ROOT}/input/${SUBJECT}/$TP

    mkdir -p $WORK/preproc

    # Link the T2 segmentation 
    for SIDE in left right; do
        # Link the segmentation in the right directory
        ln -sf ${INPUT}/Dataset424_TwoStageInferenceNew/${SIDE}/stage_2_output/MTL_000.nii.gz ${WORK}/preproc/${SIDE}_fineseg_t2_raw.nii.gz 
        ln -sf ${INPUT}/Dataset424_TwoStageInferenceNew/${SIDE}/stage_1_output/MTL_000.nii.gz ${WORK}/preproc/${SIDE}_coarseseg_t2_raw.nii.gz 

        # Apply cleanup to the segmentations
        python $ROOT/ashs_cleanup.py -c $ROOT/manifest/ashs_cleanup_fine.yaml \
            -i ${WORK}/preproc/${SIDE}_fineseg_t2_raw.nii.gz -o ${WORK}/preproc/${SIDE}_fineseg_t2.nii.gz \
            -s ${WORK}/preproc/${SIDE}_fineseg_cleanup_stats.csv

        # Apply cleanup to the segmentations
        python $ROOT/ashs_cleanup.py -c $ROOT/manifest/ashs_cleanup_coarse.yaml \
            -i ${WORK}/preproc/${SIDE}_coarseseg_t2_raw.nii.gz -o ${WORK}/preproc/${SIDE}_coarseseg_t2.nii.gz \
            -s ${WORK}/preproc/${SIDE}_coarseseg_cleanup_stats.csv

        # Generate binary T1-space images for ALOHA
        c3d ${INPUT}/t1_img.nii.gz ${WORK}/preproc/${SIDE}_fineseg_t2.nii.gz \
            -thresh 0.5 inf 1 0 -smooth-fast 0.2mm -reslice-identity -thresh 0.5 inf 1 0 \
            -o ${WORK}/preproc/${SIDE}_fineseg_binary_t1space.nii.gz
    done
}

function aloha_preproc_all()
{
    mkdir -p $ROOT/dump
    export PYBATCH_LSF_OPTS="-q bsc_short"

    IFS=' ' cat $ROOT/manifest/manifest_adni.txt | while read SUBJECT TP; do
        echo subject $SUBJECT timepoint $TP

        $ROOT/pybatch.sh \
            -N "aloha_preproc_${SUBJECT}_${TP}" -o $ROOT/dump \
            $0 aloha_preproc_qsub $SUBJECT $TP
    done
    $ROOT/pybatch.sh -w "aloha_*"
}


function aloha_copy_essentials()
{
    SRC=${1?}
    DST=${2?}

    # Copy the main ALOHA results back to the work directory
    for side in left right; do
        ESSENTIAL_FILES=(
            global/blmptrim_${side}.nii.gz
            global/futrimdef_${side}.nii.gz
            global/fumptrim_${side}.nii.gz
            global/fumptrim_om_${side}.nii.gz
            global/blmptrimdef_${side}.nii.gz
            global/fumptrimdef_${side}.nii.gz
            global/bltrimdef_${side}.nii.gz
            deformable/fumptrimdef_om_${side}.nii.gz
            deformable/hwmptrimdef_${side}.nii.gz
            deformable/hwtrimdef_${side}.nii.gz
            deformable/futrimdef_om_${side}.nii.gz
            deformable/mprage_global_long_${side}_omRAS_half.mat
            deformable/mprage_global_long_${side}_omRAS_half_inv.mat
            deformable/tse_global_long_${side}_omRAS_half.mat
            deformable/tse_global_long_${side}_omRAS_half_inv.mat
            deformable/mp_antsreg3d_${side}Warpxvec.nii.gz
            deformable/mp_antsreg3d_${side}Warpyvec.nii.gz
            deformable/mp_antsreg3d_${side}Warpzvec.nii.gz
            deformable/tse_antsreg3d_${side}Warpxvec.nii.gz
            deformable/tse_antsreg3d_${side}Warpyvec.nii.gz
            deformable/tse_antsreg3d_${side}Warpzvec.nii.gz
            results/volumes_${side}.txt
        )

        for fn in "${ESSENTIAL_FILES[@]}"; do
            if [[ -f $SRC/$fn ]]; then
                mkdir -p $(dirname $DST/$fn)
                cp $SRC/$fn $DST/$fn
            else
                echo "Warning: File $SRC/$fn does not exist."
            fi
        done
    done
}

# Confirm that essential files have been copied for ALOHA
function aloha_rerun_results_qsub()
{
    SUBJECT=${1?}
    TP_BL=${2?}
    TP_FU=${3?} 
    ALOHADIR=${4}

    # Create necessary directories
    INPUT=${ROOT}/input/${SUBJECT}
    WORK=${ROOT}/work/${SUBJECT}
    if [[ ! $ALOHADIR ]]; then
        ALOHADIR=${WORK}/aloha_${SUBJECT}_${TP_BL}_${TP_FU}
    fi

    # Create a temp dir where to actually run ALOHA
    ALOHATMPDIR=${TMPDIR}/aloha_${SUBJECT}_${TP_BL}_${TP_FU}
    mkdir -p $ALOHATMPDIR

    # Copy the ALOHA dir to temp space
    cp -av ${ALOHADIR}/* $ALOHATMPDIR/

    # Upsample the T2 images for ALOHA
    c3d ${INPUT}/${TP_BL}/t2_img.nii.gz -resample 100x100x500% -type ushort -o ${TMPDIR}/t2_bl_iso.nii.gz
    c3d ${INPUT}/${TP_FU}/t2_img.nii.gz -resample 100x100x500% -type ushort -o ${TMPDIR}/t2_fu_iso.nii.gz

    # Run ALOHA measurement stage in the target directory
    bash ${ALOHA_ROOT}/scripts/aloha_main.sh -z 4 \
        -b ${INPUT}/${TP_BL}/t1_img.nii.gz \
        -f ${INPUT}/${TP_FU}/t1_img.nii.gz \
        -r ${WORK}/${TP_BL}/preproc/left_fineseg_binary_t1space.nii.gz \
        -s ${WORK}/${TP_BL}/preproc/right_fineseg_binary_t1space.nii.gz \
        -w $ALOHATMPDIR \
        -c ${TMPDIR}/t2_bl_iso.nii.gz \
        -g ${TMPDIR}/t2_fu_iso.nii.gz \
        -t ${WORK}/${TP_BL}/preproc/left_fineseg_t2.nii.gz \
        -u ${WORK}/${TP_BL}/preproc/right_fineseg_t2.nii.gz 
    
    # Copy essential files back to the work directory
    aloha_copy_essentials $ALOHATMPDIR $ALOHADIR

    # Delete the temporary directory
    rm -rf $ALOHATMPDIR $TMPDIR/t2_*_iso.nii.gz
}

function aloha_qsub()
{
    SUBJECT=$1
    TP_BL=$2
    TP_FU=$3

    # Create necessary directories
    INPUT=${ROOT}/input/${SUBJECT}
    WORK=${ROOT}/work/${SUBJECT}

    # Main ALOHA work happens in a tempdir
    ALOHADIR=${TMPDIR}/aloha_${SUBJECT}_${TP_BL}_${TP_FU}
    mkdir -p $ALOHADIR

    # Upsample the T2 images for ALOHA
    c3d ${INPUT}/${TP_BL}/t2_img.nii.gz -resample 100x100x500% -type ushort -o ${TMPDIR}/t2_bl_iso.nii.gz
    c3d ${INPUT}/${TP_FU}/t2_img.nii.gz -resample 100x100x500% -type ushort -o ${TMPDIR}/t2_fu_iso.nii.gz

    # Run ALOHA in the temp directory
    bash ${ALOHA_ROOT}/scripts/aloha_main.sh \
        -b ${INPUT}/${TP_BL}/t1_img.nii.gz \
        -f ${INPUT}/${TP_FU}/t1_img.nii.gz \
        -r ${WORK}/${TP_BL}/preproc/left_fineseg_binary_t1space.nii.gz \
        -s ${WORK}/${TP_BL}/preproc/right_fineseg_binary_t1space.nii.gz \
        -w $ALOHADIR \
        -c ${TMPDIR}/t2_bl_iso.nii.gz \
        -g ${TMPDIR}/t2_fu_iso.nii.gz \
        -t ${WORK}/${TP_BL}/preproc/left_fineseg_t2.nii.gz \
        -u ${WORK}/${TP_BL}/preproc/right_fineseg_t2.nii.gz 

    # Copy essential files back to the work directory
    aloha_copy_essentials $ALOHADIR ${WORK}/aloha_${SUBJECT}_${TP_BL}_${TP_FU}

    # Delete the temporary directory
    ### rm -rf ${TMPDIR}/aloha_${SUBJECT}_${TP_BL}_${TP_FU}
}

function aloha_all()
{
    mkdir -p $ROOT/dump
    IFS=' ' cat $ROOT/manifest/manifest_adni_aloha_pairs.txt | while read SUBJECT TP_BL TP_FU; do
        echo subject $SUBJECT timepoint $TP_BL timepoint $TP_FU

        # Check outputs
        if [[ -f ${ROOT}/work/${SUBJECT}/aloha_${SUBJECT}_${TP_BL}_${TP_FU}/results/volumes_left.txt && \
              -f ${ROOT}/work/${SUBJECT}/aloha_${SUBJECT}_${TP_BL}_${TP_FU}/results/volumes_right.txt ]]; then
            echo "ALOHA already run for ${SUBJECT} at timepoint ${TP_BL}/${TP_FU}. Skipping."
            continue
        fi

        $ROOT/pybatch.sh \
            -N "aloha_${SUBJECT}_${TP_BL}_${TP_FU}" -o $ROOT/dump \
            $0 aloha_qsub $SUBJECT $TP_BL $TP_FU
    done
    $ROOT/pybatch.sh -w "aloha_*"
}

function aloha_rerun_results_all()
{
    mkdir -p $ROOT/dump
    MANIFEST=$ROOT/manifest/manifest_adni_aloha_pairs.txt
    IFS=' ' cat ${MANIFEST} | while read SUBJECT TP_BL TP_FU; do
        echo subject $SUBJECT timepoint $TP_BL timepoint $TP_FU

        # TEMPORARY - skip if results exist
        ### if [[ -f ${ROOT}/work/${SUBJECT}/aloha_${SUBJECT}_${TP_BL}_${TP_FU}/results/volumes_left.txt && \
        ###      -f ${ROOT}/work/${SUBJECT}/aloha_${SUBJECT}_${TP_BL}_${TP_FU}/results/volumes_right.txt ]]; then
        ###    echo "ALOHA results already exist for ${SUBJECT} at timepoint ${TP_BL}/${TP_FU}. Skipping."
        ###    continue
        ### fi

        # Remove the existing files
        rm -rf ${ROOT}/work/${SUBJECT}/aloha_${SUBJECT}_${TP_BL}_${TP_FU}/results/volumes*.txt

        # ALOHA must have been run
        if [[ -f ${ROOT}/work/${SUBJECT}/aloha_${SUBJECT}_${TP_BL}_${TP_FU}/deformable/tse_antsreg3d_leftWarpzvec.nii.gz && \
              -f ${ROOT}/work/${SUBJECT}/aloha_${SUBJECT}_${TP_BL}_${TP_FU}/deformable/tse_antsreg3d_rightWarpzvec.nii.gz ]]; then
              
            export PYBATCH_LSF_OPTS="-q bsc_short"
            $ROOT/pybatch.sh \
                -N "aloha_rr_${SUBJECT}_${TP_BL}_${TP_FU}" -o $ROOT/dump \
                $0 aloha_rerun_results_qsub $SUBJECT $TP_BL $TP_FU
        else
            echo "ALOHA has not been run for ${SUBJECT} at timepoint ${TP_BL}/${TP_FU}. Skipping."
        fi
    done
    $ROOT/pybatch.sh -w "aloha_rr_*"
}

function aloha_qc_all()
{
    mkdir -p $ROOT/dump
    export PYBATCH_LSF_OPTS="-q bsc_short"

    IFS=' ' cat $ROOT/manifest/manifest_adni_aloha_pairs.txt | while read SUBJECT TP_BL TP_FU; do
        echo subject $SUBJECT timepoint $TP_BL timepoint $TP_FU
        RESL=${ROOT}/work/${SUBJECT}/aloha_${SUBJECT}_${TP_BL}_${TP_FU}/results/volumes_left.txt
        RESR=${ROOT}/work/${SUBJECT}/aloha_${SUBJECT}_${TP_BL}_${TP_FU}/results/volumes_right.txt
        
        if [[ -f $RESL && -f $RESR ]]; then

            # Only run for files that haven't rerun recently (temporary)
            if [[ $(find $RESL -mmin 2880) || $(find $RESR -mmin 2880) ]]; then
                $ROOT/pybatch.sh \
                    -N "aloha_qc_${SUBJECT}_${TP_BL}_${TP_FU}" -o $ROOT/dump \
                    $0 aloha_qc_qsub $SUBJECT $TP_BL $TP_FU            
            fi
        else
            echo "ALOHA has not been run for ${SUBJECT} at timepoint ${TP_BL}/${TP_FU}. Skipping."
        fi
    done
    $ROOT/pybatch.sh -w "aloha_qc_*"
}


function aloha_qc_qsub()
{
    SUBJECT=${1?}
    TP_BL=${2?}
    TP_FU=${3?}
    ALOHADIR=${4}

    INPUT=${ROOT}/input/${SUBJECT}
    WORK=${ROOT}/work/${SUBJECT}
    if [[ ! $ALOHADIR ]]; then
        ALOHADIR=${WORK}/aloha_${SUBJECT}_${TP_BL}_${TP_FU}
    fi

    QCDIR=$ALOHADIR/qc
    mkdir -p $QCDIR
    mkdir -p tmp/all_qc

    # Generate QC images for ALOHA
    for side in left right; do

        # Create a temp directory for this side
        SDIR=$TMPDIR/qc_${side}
        mkdir -p $SDIR

        # Take the baseline and followup T2 segmentations. They should align well in halfway space
        SEG_BL=${WORK}/${TP_BL}/preproc/${side}_fineseg_t2.nii.gz
        SEG_FU=${WORK}/${TP_FU}/preproc/${side}_fineseg_t2.nii.gz

        # Upsample the T2 images for ALOHA
        c3d ${INPUT}/${TP_BL}/t2_img.nii.gz -resample 100x100x500% -type ushort -o ${SDIR}/t2_bl_iso.nii.gz
        c3d ${INPUT}/${TP_FU}/t2_img.nii.gz -resample 100x100x500% -type ushort -o ${SDIR}/t2_fu_iso.nii.gz

        # Binarize the segmentations, we don't want all the labels
        c3d $SEG_BL -replace 1 100 3 100 4 100 5 100 7 100 8 100 -thresh 100 inf 1 0 -o $SDIR/seg_bl.nii.gz
        c3d $SEG_FU -replace 1 100 3 100 4 100 5 100 7 100 8 100 -thresh 100 inf 1 0 -o $SDIR/seg_fu.nii.gz

        # Crop the moving image and match its origin to the cropped fixed image, this
        # should be done for both the image and segmentation
        REF_FU=$ALOHADIR/global/futrimdef_${side}.nii.gz
        REF_FU_OM=$ALOHADIR/deformable/futrimdef_om_${side}.nii.gz
        c3d $REF_FU_OM $REF_FU ${SDIR}/t2_fu_iso.nii.gz -reslice-identity -copy-transform \
            -o $SDIR/t2_fu_om.nii.gz

        c3d $REF_FU_OM $REF_FU $SDIR/seg_fu.nii.gz -reslice-identity -copy-transform -thresh 0.5 inf 1 0 \
            -o $SDIR/seg_futrimom.nii.gz
    
        # Transform the fixed image to the halfway space
        greedy -d 3 -threads 1 \
            -rf $ALOHADIR/deformable/hwtrimdef_${side}.nii.gz \
            -rm ${SDIR}/t2_bl_iso.nii.gz $SDIR/bltrimhw.nii.gz \
            -ri LABEL 0.2mm -rm $SDIR/seg_bl.nii.gz $SDIR/seg_bltrimhw.nii.gz \
            -r $ALOHADIR/deformable/tse_global_long_${side}_omRAS_half_inv.mat

        # Transform the moving image to the halfway space (affine only)
        greedy -d 3 -threads 1 \
            -rf $ALOHADIR/deformable/hwtrimdef_${side}.nii.gz \
            -rm $SDIR/t2_fu_om.nii.gz $SDIR/futrimom_affine_to_hw.nii.gz \
            -ri LABEL 0.2mm -rm $SDIR/seg_futrimom.nii.gz $SDIR/seg_futrimom_affine_to_hw.nii.gz \
            -r $ALOHADIR/deformable/tse_global_long_${side}_omRAS_half.mat
            
        # Generate a warp by combining xyz components from ANTS
        c3d $ALOHADIR/deformable/tse_antsreg3d_${side}Warpxvec.nii.gz \
            $ALOHADIR/deformable/tse_antsreg3d_${side}Warpyvec.nii.gz \
            $ALOHADIR/deformable/tse_antsreg3d_${side}Warpzvec.nii.gz \
            -omc $SDIR/tse_antsreg3d_${side}_warp.nii.gz

        # Transform the moving image to the halfway space (warp and affine)
        greedy -d 3 -threads 1 \
            -rf $ALOHADIR/deformable/hwtrimdef_${side}.nii.gz \
            -rm $SDIR/t2_fu_om.nii.gz $SDIR/futrimom_warped_to_hw.nii.gz \
            -ri LABEL 0.2mm -rm $SDIR/seg_futrimom.nii.gz $SDIR/seg_futrimom_warped_to_hw.nii.gz \
            -r $SDIR/tse_antsreg3d_${side}_warp.nii.gz $ALOHADIR/deformable/tse_global_long_${side}_omRAS_half.mat

        # Compute overlap between the segmentations in halfway space
        c3d $SDIR/seg_bltrimhw.nii.gz $SDIR/seg_futrimom_affine_to_hw.nii.gz -overlap 1 > $QCDIR/overlap_affine_${side}.txt            
        c3d $SDIR/seg_bltrimhw.nii.gz $SDIR/seg_futrimom_warped_to_hw.nii.gz -overlap 1 > $QCDIR/overlap_warped_${side}.txt            

        # Compute NCC metric?
        c3d $SDIR/seg_bltrimhw.nii.gz -dilate 1 5x5x5 -popas M \
            $SDIR/bltrimhw.nii.gz -as R \
            $SDIR/futrimom_affine_to_hw.nii.gz -ncc 2x2x2 -replace nan 0 -push M -lstat \
            > $QCDIR/ncc_affine_${side}.txt

        c3d $SDIR/seg_bltrimhw.nii.gz -dilate 1 5x5x5 -popas M \
            $SDIR/bltrimhw.nii.gz -as R \
            $SDIR/futrimom_warped_to_hw.nii.gz -ncc 2x2x2 -replace nan 0 -push M -lstat \
            > $QCDIR/ncc_warped_${side}.txt

        # Generate a QC image
        c3d $SDIR/bltrimhw.nii.gz -stretch 0% 99% 0 255 -clip 0 255 -popas R \
            $SDIR/futrimom_affine_to_hw.nii.gz -stretch 0% 99% 0 255 -clip 0 255 -popas FA \
            $SDIR/futrimom_warped_to_hw.nii.gz -stretch 0% 99% 0 255 -clip 0 255 -popas FW \
            -push FA -push R -scale -1 -add -stretch -127 128 0 255 -clip 0 255 -popas FA_diff \
            -push FW -push R -scale -1 -add -stretch -127 128 0 255 -clip 0 255 -popas FW_diff \
            -push R -slice z 20%:10%:80% -tile x -flip y -popas row_R \
            -push FA -slice z 20%:10%:80% -tile x -flip y -popas row_FA \
            -push FW -slice z 20%:10%:80% -tile x -flip y -popas row_FW \
            -push FA_diff -slice z 20%:10%:80% -tile x -flip y -popas row_FA_diff \
            -push FW_diff -slice z 20%:10%:80% -tile x -flip y -popas row_FW_diff \
            -push row_R -push row_FA -push row_FA_diff -push row_FW -push row_FW_diff \
            -type uchar -oo $SDIR/qc_${side}_row_%d.png # \
            # -tile y -o $QCDIR/${SUBJECT}_${TP_BL}_${TP_FU}_aloha_qc_${side}.png \

        magick -delay 100 -font DejaVu-Sans -pointsize 12 -background black -fill white \
            \( \
                \( -size 320x20 -gravity center caption:"${SUBJECT} ${TP_BL} - baseline" \) \
                \( \( $SDIR/qc_${side}_row_0.png $SDIR/qc_${side}_row_2.png -append \) \
                \( -size 120x20 -gravity center caption:"affine" -rotate 270 \) \
                +swap +append \) \
                \( \( $SDIR/qc_${side}_row_0.png $SDIR/qc_${side}_row_4.png -append \) \
                \( -size 120x20 -gravity center caption:"deformable" -rotate 270 \) \
                +swap +append \) \
                -append \) \
            \( \
                \( -size 320x20 -gravity center caption:"${SUBJECT} ${TP_FU} - followup" \) \
                \( \( $SDIR/qc_${side}_row_1.png $SDIR/qc_${side}_row_2.png -append \) \
                \( -size 120x20 -gravity center caption:"affine" -rotate 270 \) \
                +swap +append \) \
                \( \( $SDIR/qc_${side}_row_3.png $SDIR/qc_${side}_row_4.png -append \) \
                \( -size 120x20 -gravity center caption:"deformable" -rotate 270 \) \
                +swap +append \) \
                -append \) \
            -loop 0 $QCDIR/${SUBJECT}_${TP_BL}_${TP_FU}_aloha_qc_${side}.gif

        # Also copy the 3D patch images into the QC dir for additional inspection
        c3d $SDIR/bltrimhw.nii.gz -type short $QCDIR/${SUBJECT}_${TP_BL}_${TP_FU}_aloha_qc_${side}_bltrimhw.nii.gz 
        c3d $SDIR/futrimom_affine_to_hw.nii.gz -type short $QCDIR/${SUBJECT}_${TP_BL}_${TP_FU}_aloha_qc_${side}_futrimom_affine_to_hw.nii.gz
        c3d $SDIR/futrimom_warped_to_hw.nii.gz -type short $QCDIR/${SUBJECT}_${TP_BL}_${TP_FU}_aloha_qc_${side}_futrimom_warped_to_hw.nii.gz

        # Copy the gif to a common directory for easy viewing
        cp $QCDIR/${SUBJECT}_${TP_BL}_${TP_FU}_aloha_qc_${side}.gif tmp/all_qc/

    done

    # Generate a single summary qc file
    OVL_AL=$(cat $QCDIR/overlap_affine_left.txt | sed -e "s/,//g" | awk '{print $6}')
    OVL_WL=$(cat $QCDIR/overlap_warped_left.txt | sed -e "s/,//g" | awk '{print $6}')
    OVL_AR=$(cat $QCDIR/overlap_affine_right.txt | sed -e "s/,//g" | awk '{print $6}')
    OVL_WR=$(cat $QCDIR/overlap_warped_right.txt | sed -e "s/,//g" | awk '{print $6}')
    NCC_AL=$(cat $QCDIR/ncc_affine_left.txt | awk '$1==1 {print $2}')
    NCC_WL=$(cat $QCDIR/ncc_warped_left.txt | awk '$1==1 {print $2}')
    NCC_AR=$(cat $QCDIR/ncc_affine_right.txt | awk '$1==1 {print $2}')
    NCC_WR=$(cat $QCDIR/ncc_warped_right.txt | awk '$1==1 {print $2}') 
    echo "${SUBJECT},${TP_BL},${TP_FU},${OVL_AL},${OVL_WL},${OVL_AR},${OVL_WR},${NCC_AL},${NCC_WL},${NCC_AR},${NCC_WR}" \
        > $QCDIR/${SUBJECT}_${TP_BL}_${TP_FU}_aloha_qc_summary.csv

}


# After CRASHS ran, sample file-scale labels and compute thickness, etc
function crashs_sample_aloha_old_qsub()
{
    SUBJECT=$1
    TP_BL=${2?}
    TP_FU=${3?}
    

    for SIDE in left right; do

        CDIR=${ROOT}/work/${SUBJECT}/${TP_BL}/crashs_${SIDE}
        ID=${SUBJECT}_${TP}_${SIDE}
        ALOHADIR=${ROOT}/work/${SUBJECT}/aloha_${SUBJECT}_${TP_BL}_${TP_FU}

        # Create a temp directory for this side
        SDIR=$TMPDIR/aloha_crashs_${side}
        mkdir -p $SDIR

        # Apply the halfway affine transformation to take the crashs mesh into the space where the ALOHA warp is done
        greedy -d 3 -threads 1 -vtk-bin \
            -rf $ALOHADIR/deformable/hwtrimdef_${SIDE}.nii.gz \
            -rs ${CDIR}/${SUBJECT}_${TP_BL}_${SIDE}_template_thickness_finelabels.vtk ${SDIR}/${SUBJECT}_${TP_BL}_${SIDE}_template_thickness_finelabels_hw.vtk \
            -r $ALOHADIR/deformable/tse_global_long_${SIDE}_omRAS_half.mat

        # Combine the warp components to compute the Jacobian determinant in the halfway space
        c3d $ALOHADIR/deformable/tse_antsreg3d_${SIDE}Warpxvec.nii.gz \
            $ALOHADIR/deformable/tse_antsreg3d_${SIDE}Warpyvec.nii.gz \
            $ALOHADIR/deformable/tse_antsreg3d_${SIDE}Warpzvec.nii.gz \
            -omc $SDIR/tse_antsreg3d_${SIDE}_warp.nii.gz

        # Compute the Jacobian determinant of the warp in the halfway space
        greedy -d 3 -threads 1 \
            -rf $ALOHADIR/deformable/hwtrimdef_${SIDE}.nii.gz \
            -rj $SDIR/tse_antsreg3d_${SIDE}_jacobian.nii.gz \
            -r $SDIR/tse_antsreg3d_${SIDE}_warp.nii.gz

        # Sample the Jacobian determinant
        mesh_image_sample -B \
            ${SDIR}/${SUBJECT}_${TP_BL}_${SIDE}_template_thickness_finelabels_hw.vtk \
            $SDIR/tse_antsreg3d_${SIDE}_jacobian.nii.gz \
            ${SDIR}/${SUBJECT}_${TP_BL}_${SIDE}_template_thickness_finelabels_hw_jac.vtk \
            warp_jacobian

        # Rotate the mesh back
        mkdir -p $ALOHADIR/crashs_sample
        greedy -d 3 -threads 1 -vtk-bin \
            -rf $ALOHADIR/deformable/hwtrimdef_${SIDE}.nii.gz \
            -rs ${SDIR}/${SUBJECT}_${TP_BL}_${SIDE}_template_thickness_finelabels_hw_jac.vtk ${ALOHADIR}/crashs_sample/${SUBJECT}_${TP_BL}_${TP_FU}_${SIDE}_crashs_jac.vtk \
            -r $ALOHADIR/deformable/tse_global_long_${SIDE}_omRAS_half_inv.mat
        
    done
}

# After CRASHS ran, sample file-scale labels and compute thickness, etc
function crashs_sample_aloha_qsub()
{
    SUBJECT=$1
    TP_BL=${2?}
    TP_FU=${3?}
    INPUT=${ROOT}/input/${SUBJECT}
    WORK=${ROOT}/work/${SUBJECT}
    
    for SIDE in left right; do

        CDIR=${ROOT}/work/${SUBJECT}/${TP_BL}/crashs_${SIDE}
        ID=${SUBJECT}_${TP}_${SIDE}
        ALOHADIR=${ROOT}/work/${SUBJECT}/aloha_${SUBJECT}_${TP_BL}_${TP_FU}
        mkdir -p $ALOHADIR/crashs_sample

        # Create a temp directory for this side
        SDIR=$TMPDIR/aloha_crashs_${SIDE}
        mkdir -p $SDIR

        # Do the origin trick for the moving image (same as in qc code)
        REF_FU=$ALOHADIR/global/futrimdef_${SIDE}.nii.gz
        REF_FU_OM=$ALOHADIR/deformable/futrimdef_om_${SIDE}.nii.gz
        c3d $REF_FU_OM $REF_FU ${INPUT}/${TP_FU}/t2_img.nii.gz -reslice-identity -copy-transform -o $SDIR/t2_fu_om.nii.gz

        # Binarize the segmentations to create a registration mask, we don't want all the labels
        c3d ${WORK}/${TP_BL}/preproc/${SIDE}_coarseseg_t2.nii.gz -replace 1 100 3 100 4 100 5 100 7 100 8 100 -thresh 100 inf 1 0 \
            -dilate 1 3x3x3 -o $SDIR/mask_bl.nii.gz

        # Apply the halfway affine transformation to take the tetrahedral medial mesh into halfway space, while also
        # generating the moving image for mesh-regularized deformable registration
        c3d $SDIR/t2_fu_om.nii.gz -scale 0 -shift 1 -o $SDIR/t2_fu_om_fgmask.nii.gz
        greedy -d 3 -threads 1 -vtk-bin \
            -rf $ALOHADIR/deformable/hwtrimdef_${SIDE}.nii.gz \
            -rs ${CDIR}/${SUBJECT}_${TP_BL}_${SIDE}_thickness_tetra.vtk ${SDIR}/${SUBJECT}_${TP_BL}_${SIDE}_thickness_tetra_hw.vtk \
            -rm $SDIR/t2_fu_om.nii.gz $SDIR/futrimom_affine_to_hw.nii.gz \
            -ri NEAREST -rm $SDIR/t2_fu_om_fgmask.nii.gz $SDIR/futrimom_fgmask_affine_to_hw.nii.gz \
            -r $ALOHADIR/deformable/tse_global_long_${SIDE}_omRAS_half.mat

        # Apply the inverse halfway transformation to take the fixed image into halfway space
        c3d ${INPUT}/${TP_BL}/t2_img.nii.gz -scale 0 -shift 1 -o $SDIR/t2_bl_fgmask.nii.gz
        greedy -d 3 -threads 1 \
            -rf $ALOHADIR/deformable/hwtrimdef_${SIDE}.nii.gz \
            -ri LABEL 0.2mm -rm $SDIR/mask_bl.nii.gz $SDIR/mask_bl_hw.nii.gz \
            -ri LINEAR -rm ${INPUT}/${TP_BL}/t2_img.nii.gz $SDIR/bltrimhw.nii.gz \
            -ri NEAREST -rm $SDIR/t2_bl_fgmask.nii.gz $SDIR/bltrimhw_fgmask.nii.gz \
            -r $ALOHADIR/deformable/tse_global_long_${SIDE}_omRAS_half_inv.mat

        # Combine the two foreground masks into a single foreground mask in halfway space
        c3d $SDIR/futrimom_fgmask_affine_to_hw.nii.gz $SDIR/bltrimhw_fgmask.nii.gz -times -type char -o $SDIR/hw_fgmask.nii.gz \
            $SDIR/mask_bl_hw.nii.gz -times -o $SDIR/mask_bl_fg_hw.nii.gz

        # Sample the mask using the tetrahedral mesh, so we know what tetrahedra should be set to NaN before doing stats
        mesh_image_sample -B -b 0 \
            ${SDIR}/${SUBJECT}_${TP_BL}_${SIDE}_thickness_tetra_hw.vtk \
            $SDIR/hw_fgmask.nii.gz \
            ${SDIR}/${SUBJECT}_${TP_BL}_${SIDE}_thickness_tetra_hw_mask.vtk \
            fgmask 

        # We can now perform deformable registration in halfway space. Let's use the same parameters as ALOHA
        # with the addition of a regularization term and NCC instead of Mattes 
        greedy -d 3 -threads 1 -defopt \
            -i $SDIR/bltrimhw.nii.gz $SDIR/futrimom_affine_to_hw.nii.gz \
            -gm $SDIR/mask_bl_fg_hw.nii.gz -bg NAN \
            -m WNCC 2x2x2 \
            -noise 0 -oroot $SDIR/aloha_tjr_warproot.nii.gz \
            -n 1000 -wr 1.0 -noise 0 -s 2.0vox 0.1vox \
            -tjr ${SDIR}/${SUBJECT}_${TP_BL}_${SIDE}_thickness_tetra_hw_mask.vtk 100 

        # Compute the Jacobian of the deformation in mesh space
        greedy -d 3 -threads 1 -vtk-bin \
            -rf $ALOHADIR/deformable/hwtrimdef_${SIDE}.nii.gz \
            -rsj ${SDIR}/${SUBJECT}_${TP_BL}_${SIDE}_thickness_tetra_hw_mask.vtk ${SDIR}/${SUBJECT}_${TP_BL}_${SIDE}_thickness_tetra_hw_jac.vtk \
            -r $SDIR/aloha_tjr_warproot.nii.gz,64

        # Rotate the Jacobian mesh back to fixed image space for sampling
        greedy -d 3 -threads 1 -vtk-bin \
            -rf $ALOHADIR/deformable/hwtrimdef_${SIDE}.nii.gz \
            -rs ${SDIR}/${SUBJECT}_${TP_BL}_${SIDE}_thickness_tetra_hw_jac.vtk $ALOHADIR/crashs_sample/${SUBJECT}_${TP_BL}_${SIDE}_thickness_tetra_jac.vtk \
            -r $ALOHADIR/deformable/tse_global_long_${SIDE}_omRAS_half_inv.mat

        # Sample the Jacobian determinant in the original CRASHS mesh space, this will be used for thickness change analysis
        mesh_tetra_sample -d 1.0 -D SamplingDistance -B \
            ${CDIR}/${SUBJECT}_${TP_BL}_${SIDE}_template_thickness_finelabels.vtk \
            $ALOHADIR/crashs_sample/${SUBJECT}_${TP_BL}_${SIDE}_thickness_tetra_jac.vtk \
            $ALOHADIR/crashs_sample/${SUBJECT}_${TP_BL}_${SIDE}_crashs_tetra_jac.vtk \
            jacobian
        
    done
}

function crashs_sample_aloha_all()
{
    mkdir -p $ROOT/dump
    # export PYBATCH_LSF_OPTS="-q bsc_short"

    IFS=' ' cat $ROOT/manifest/manifest_adni_aloha_pairs.txt | while read SUBJECT TP_BL TP_FU; do
        echo subject $SUBJECT timepoint $TP_BL timepoint $TP_FU
        RESL=${ROOT}/work/${SUBJECT}/aloha_${SUBJECT}_${TP_BL}_${TP_FU}/results/volumes_left.txt
        RESR=${ROOT}/work/${SUBJECT}/aloha_${SUBJECT}_${TP_BL}_${TP_FU}/results/volumes_right.txt
        CRAL=${ROOT}/work/${SUBJECT}/${TP_BL}/crashs_left/${SUBJECT}_${TP_BL}_left_template_thickness_finelabels.vtk
        CRAR=${ROOT}/work/${SUBJECT}/${TP_BL}/crashs_right/${SUBJECT}_${TP_BL}_right_template_thickness_finelabels.vtk

        # Temorary: skip if results exist
        if [[ -f ${ROOT}/work/${SUBJECT}/aloha_${SUBJECT}_${TP_BL}_${TP_FU}/crashs_sample/${SUBJECT}_${TP_BL}_left_crashs_tetra_jac.vtk && \
              -f ${ROOT}/work/${SUBJECT}/aloha_${SUBJECT}_${TP_BL}_${TP_FU}/crashs_sample/${SUBJECT}_${TP_BL}_right_crashs_tetra_jac.vtk ]]; then
            echo "CRASHS sampling already done for ${SUBJECT} at timepoint ${TP_BL}/${TP_FU}. Skipping."
            continue
        else
            echo "CRASHS sampling will be done for ${SUBJECT} at timepoint ${TP_BL}/${TP_FU}."
        fi

        if [[ -f $RESL && -f $RESR && -f $CRAL && -f $CRAL ]]; then
            # Only run for files that haven't rerun recently (temporary)
            $ROOT/pybatch.sh \
                -N "crashs_sample_aloha_${SUBJECT}_${TP_BL}_${TP_FU}" -o $ROOT/dump \
                $0 crashs_sample_aloha_qsub $SUBJECT $TP_BL $TP_FU            
        else
            echo "ALOHA or CRASHS has not been run for ${SUBJECT} at timepoint ${TP_BL}/${TP_FU}. Skipping."
        fi
    done
    $ROOT/pybatch.sh -w "crashs_sample_aloha_*"
}



function test()
{
    side=right
    SDIR=/scratch/ashsxv_adni.fkvvYf/qc_${side}

    magick -delay 100 -font DejaVu-Sans -pointsize 12 -background black -fill white \
        \( \
            \( -size 120x20 -gravity center caption:"Test Image" \) \
            \( \( $SDIR/qc_${side}row_0.png $SDIR/qc_${side}row_2.png -append \) \
               \( -size 120x20 -gravity center caption:"affine" -rotate 270 \) \
               +swap +append \) \
            \( \( $SDIR/qc_${side}row_0.png $SDIR/qc_${side}row_4.png -append \) \
               \( -size 120x20 -gravity center caption:"deformable" -rotate 270 \) \
               +swap +append \) \
            -append \) \
        \( \
            \( -size 120x20 -gravity center caption:"Test Image" \) \
            \( \( $SDIR/qc_${side}row_1.png $SDIR/qc_${side}row_2.png -append \) \
               \( -size 120x20 -gravity center caption:"affine" -rotate 270 \) \
               +swap +append \) \
            \( \( $SDIR/qc_${side}row_3.png $SDIR/qc_${side}row_4.png -append \) \
               \( -size 120x20 -gravity center caption:"deformable" -rotate 270 \) \
               +swap +append \) \
            -append \) \
        -loop 0 tmp/anim.gif

    # magick -delay 100 -gravity north -font DejaVu-Sans -pointsize 12 -fill yellow -background black \( /scratch/ashsxv_adni.fkvvYf/qc_right/qc_rightrow_0.png -annotate +0+4 "baseline" /scratch/ashsxv_adni.fkvvYf/qc_right/qc_rightrow_0.png -annotate +0+4 "baseline" -append \) \( /scratch/ashsxv_adni.fkvvYf/qc_right/qc_rightrow_1.png -annotate +0+4 "affine" /scratch/ashsxv_adni.fkvvYf/qc_right/qc_rightrow_3.png -annotate +0+4 "deformable" -append \) -loop 0 tmp/anim.gif
}

if [[ $1 ]]; then
  command=$1
  shift
  $command $@
else
  main
fi
