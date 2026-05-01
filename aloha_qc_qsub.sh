#!/bin/bash

#
# From:
# bscsub:/project/hippogang_2/pauly/longi_for_ashs_xv/test_aloha/runme.sh
#

CmdName=$(basename "$0")
Syntax="${CmdName} [-a AlohaDir][-b BaselineT2Image][-f FollupT2Image][-l LeftT2SegImage][-r RightT2SegImage][-n][-s Subject][-v]"

# ${ROOT}/input/${SUBJECT}/{Date1,Date2,Date3} directory
# $TMPDIR env variable
#

function aloha_qc_qsub()
{
    SUBJECT="${1?}"
    BL_T2="${2?}"
    BL_T2SegLeftFile="${3?}"
    BL_T2SegRightFile="${4?}"
    FU_T2=${5?}
    ALOHADIR=${6}

    TmpDir=/tmp/AlohaQc
    QCDIR="${TmpDir}/qc"
    QcAllDir="${TmpDir}/qc_all"

    #TP_BL is the baseline date in YYYY-MM-DD format
    #TP_FL is the follup date in YYYY-MM-DD format
    TP_BL=2023-11-16
    TP_FU=2023-12-19

    [ -e "$TmpDir" ] || mkdir -p "$TmpDir"
    [ -e "$QCDIR" ] || mkdir -p "$QCDIR"
    [ -e "$QcAllDir" ] || mkdir -p "$QcAllDir"

    # Generate QC images for ALOHA
    for side in left right; do

        # Create a temp directory for this side
        SDIR=$TmpDir/qc_${side}
        [ -e "$SDIR" ] || mkdir -p "$SDIR"

        # Take the baseline and followup T2 segmentations. They should align well in halfway space
#        SEG_BL=${WORK}/${TP_BL}/preproc/${side}_fineseg_t2.nii.gz # tse_blseg_left.nii.gz
#        SEG_FU=${WORK}/${TP_FU}/preproc/${side}_fineseg_t2.nii.gz # 
	if [ "$side" == 'left' ]
	then
	    SEG_BL="$BL_T2SegLeftFile"
	else
	    SEG_BL="$BL_T2SegRightFile"
	fi

        # Upsample the T2 images for ALOHA - see /tmp/aloha/tse_bl*.nii.gz and tse_fu*.nii.gz

        c3d "$BL_T2" -resample 100x100x500% -type ushort -o ${SDIR}/t2_bl_iso.nii.gz
        c3d "$FU_T2" -resample 100x100x500% -type ushort -o ${SDIR}/t2_fu_iso.nii.gz
        # c3d ${INPUT}/${TP_BL}/t2_img.nii.gz -resample 100x100x500% -type ushort -o ${SDIR}/t2_bl_iso.nii.gz
        #c3d ${INPUT}/${TP_FU}/t2_img.nii.gz -resample 100x100x500% -type ushort -o ${SDIR}/t2_fu_iso.nii.gz

        # Binarize the segmentations, we don't want all the labels
        c3d $SEG_BL -replace 1 100 3 100 4 100 5 100 7 100 8 100 -thresh 100 inf 1 0 -o $SDIR/seg_bl.nii.gz
        # c3d $SEG_FU -replace 1 100 3 100 4 100 5 100 7 100 8 100 -thresh 100 inf 1 0 -o $SDIR/seg_fu.nii.gz

        # Crop the moving image and match its origin to the cropped fixed image, this
        # should be done for both the image and segmentation
        REF_FU=$ALOHADIR/global/futrimdef_${side}.nii.gz
        REF_FU_OM=$ALOHADIR/deformable/futrimdef_om_${side}.nii.gz
        c3d $REF_FU_OM $REF_FU ${SDIR}/t2_fu_iso.nii.gz -reslice-identity -copy-transform \
            -o $SDIR/t2_fu_om.nii.gz

        # c3d $REF_FU_OM $REF_FU $SDIR/seg_fu.nii.gz -reslice-identity -copy-transform -thresh 0.5 inf 1 0 \
        #    -o $SDIR/seg_futrimom.nii.gz
    
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
            -r $ALOHADIR/deformable/tse_global_long_${side}_omRAS_half.mat
#            -ri LABEL 0.2mm -rm $SDIR/seg_futrimom.nii.gz $SDIR/seg_futrimom_affine_to_hw.nii.gz \
            
        # Generate a warp by combining xyz components from ANTS
        c3d $ALOHADIR/deformable/tse_antsreg3d_${side}Warpxvec.nii.gz \
            $ALOHADIR/deformable/tse_antsreg3d_${side}Warpyvec.nii.gz \
            $ALOHADIR/deformable/tse_antsreg3d_${side}Warpzvec.nii.gz \
            -omc $SDIR/tse_antsreg3d_${side}_warp.nii.gz

        # Transform the moving image to the halfway space (warp and affine)
        greedy -d 3 -threads 1 \
            -rf $ALOHADIR/deformable/hwtrimdef_${side}.nii.gz \
            -rm $SDIR/t2_fu_om.nii.gz $SDIR/futrimom_warped_to_hw.nii.gz \
            -r $SDIR/tse_antsreg3d_${side}_warp.nii.gz $ALOHADIR/deformable/tse_global_long_${side}_omRAS_half.mat
#            -ri LABEL 0.2mm -rm $SDIR/seg_futrimom.nii.gz $SDIR/seg_futrimom_warped_to_hw.nii.gz \

        # Compute overlap between the segmentations in halfway space
#        c3d $SDIR/seg_bltrimhw.nii.gz $SDIR/seg_futrimom_affine_to_hw.nii.gz -overlap 1 > $QCDIR/overlap_affine_${side}.txt            
#        c3d $SDIR/seg_bltrimhw.nii.gz $SDIR/seg_futrimom_warped_to_hw.nii.gz -overlap 1 > $QCDIR/overlap_warped_${side}.txt            

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
	# keep for the gear output - same as qc files from ashs
        cp $QCDIR/${SUBJECT}_${TP_BL}_${TP_FU}_aloha_qc_${side}.gif "$QcAllDir"

    done

    # Generate a single summary qc file
#    OVL_AL=$(cat $QCDIR/overlap_affine_left.txt | sed -e "s/,//g" | awk '{print $6}')
#    OVL_WL=$(cat $QCDIR/overlap_warped_left.txt | sed -e "s/,//g" | awk '{print $6}')
#    OVL_AR=$(cat $QCDIR/overlap_affine_right.txt | sed -e "s/,//g" | awk '{print $6}')
#    OVL_WR=$(cat $QCDIR/overlap_warped_right.txt | sed -e "s/,//g" | awk '{print $6}')
    NCC_AL=$(cat $QCDIR/ncc_affine_left.txt | awk '$1==1 {print $2}')
    NCC_WL=$(cat $QCDIR/ncc_warped_left.txt | awk '$1==1 {print $2}')
    NCC_AR=$(cat $QCDIR/ncc_affine_right.txt | awk '$1==1 {print $2}')
    NCC_WR=$(cat $QCDIR/ncc_warped_right.txt | awk '$1==1 {print $2}') 
    echo "${SUBJECT},${TP_BL},${TP_FU},${NCC_AL},${NCC_WL},${NCC_AR},${NCC_WR}" \
        > $QCDIR/${SUBJECT}_${TP_BL}_${TP_FU}_aloha_qc_summary.csv

}


while getopts 'a:b:f:l:r:n:s:v' arg
do
    case "$arg" in
	a|b|f|l|n|r|s|v)
	    eval "opt_${arg}='${OPTARG:=1}'"
	    ;;
	*)
	    echo "${CmdName}: Invalid flag '$arg'" 1>&2
	    echo "$Syntax" 1>&2
	    exit 1
    esac
done

shift $(( "$OPTIND" - 1 ))

aloha_qc_qsub "$opt_s" "$opt_b" "$opt_l" "$opt_r" "$opt_f" "$opt_a"
