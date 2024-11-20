
     ._id as $JobId
    | .created as $JobCreated
    | 
      [
       (
             .config.inputs[]
           | .location.name as $FileName
     	   | .object
	        | (if (.classification) then .classification.Measurement|join(":") else "" end ) as $FileClassificationMeasurement
		| (if (.classification) then .classification.Intent|join(":") else "" end ) as $FileClassificationIntent
                | {
	                "FileName": $FileName
		      , "FileId": .file_id
		      , "FileType": .type
		      , "FileTags": ( .tags | sort )
		      , "FileModality": .modality
		      , "FileClassificationMeasurement": $FileClassificationMeasurement
		      , "FileClassificationIntent": $FileClassificationIntent
		      , "JobId": $JobId
		      , "JobCreated": $JobCreated
		      , "AlohaArgFlag": $AlohaArgFlag
		   }
         
       )] as $Inputs
    | [
        (
	     .outputs[]
	   | 
	     {
	     	   "FileName": .name
		 , "FileId": .file_id
		 , "FileType": .type
		 , "FileTags": ( .tags | sort )
		 , "FileModality": .modality
		 , "FileTimestamp": .created
		 , "JobId": $JobId
		 , "JobCreated": $JobCreated
		 , "AlohaArgFlag": $AlohaArgFlag
             }
	)
      ] as $Outputs
    |  { "Inputs": $Inputs, "Outputs": $Outputs }




 
