#
# fwget -1  -ra 66e4737ead8f9c0ea1ce2750 | jq -r --argjson AlohaArgFlag '"b"' --argjson ClassificationMeasurement '"T1"' -f alohaFindT1T2.jq
#

      .created as $SessionCreated
   |  select((.acquisitions | length) > 0)
   | [.acquisitions[]
   | .label as $AcquisitionLabel
   | ._id as $AcquisitionId
   | .timestamp as $AcquisitionTimestamp
   | select((.files | length) > 0)
   | .files[]
   | select(
             ((.type == "nifti") or (.type == "archive") or (.type == "dicom"))
	 and (.modality == "MR")
         and (.classification.Intent | any("Structural"))
         and (.classification.Measurement | any(. == $ClassificationMeasurement))
         and ((.tags | length) > 0)
	 and (.tags | any(. == "AlohaInput"))
#         and (.tags | any(. == "Trimmed"))
     ) 
     | {
	     "FileName": .name
	   , "FileId": .file_id
	   , "FileType": .type
	   , "FileTags": (.tags | sort | join(":"))
	   , "FileModality": .modality
	   , "FileClassification": (.classification.Measurement|join(":"))
	   , "FileTimestamp": .created
	   , "AcquisitionLabel": $AcquisitionLabel
	   , "AcquisitionId": $AcquisitionId
	   , "AcquistionTimestamp": $AcquisitionTimestamp
	   , "AlohaArgFlag": $AlohaArgFlag
#           , "SessionCreated":  $SessionCreated
#	   , "SessionId": .parents.session
       }] | sort_by(.FileCreated, .FileTags) | last
     