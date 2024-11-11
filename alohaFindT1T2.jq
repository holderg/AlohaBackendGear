#
# Finds the T1/T2 acquisition from an session.json file
# fwget -1  -ra 66e4737ead8f9c0ea1ce2750 | jq -r --argjson AlohaArgFlag '"-b"' --argjson ClassificationMeasurement '"T1"' -f alohaFindT1T2.jq
# 66e4737ead8f9c0ea1ce2750 is a session id
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
	     # Only want the original scan -- dicom or archive. nifti is a derived image
             ((.type == "archive") or (.type == "dicom") )
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
       }] | sort_by(.FileCreated, .FileType, .FileTags)[]
       #| last
     