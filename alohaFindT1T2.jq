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
	     # Leaving out type selection as it is too hard to allow multiples
	     (.modality == "MR")
	 and ((.classification.Intent | length) > 0)
         and (.classification.Intent | any("Structural"))
	 and ((.classification.Measurement | length) > 0)
         and (.classification.Measurement | any(. == $ClassificationMeasurement))
         and ((.tags | length) > 0)
	 and (.tags | any(. == "AlohaInput"))
     ) 
     | {
	     "FileName": .name
	   , "FileId": .file_id
	   , "FileType": .type
	   , "FileTags": (.tags | sort )
	   , "FileModality": .modality
	   , "FileClassification": (.classification.Measurement|join(":"))
	   , "FileTimestamp": .created
	   , "AcquisitionLabel": $AcquisitionLabel
	   , "AcquisitionId": $AcquisitionId
	   , "AcquistionTimestamp": $AcquisitionTimestamp
	   , "AlohaArgFlag": $AlohaArgFlag
       }] | sort_by(.FileCreated, .FileType, .FileTags)[]
       #| last
     