
#
# jq -r -f alohaPrettyPrintJobs.jq /tmp/Aloha/BaselineJobs.json 
#

select(.detail.state == "complete")
   | ._id as $JobId
   | .created as $JobDateTime
   | .gear_info.id as $GearId
   | .gear_info.category as $GearCategory
   | .gear_info.version as $GearVersion
   | .gear_info.name as $GearName

   | ( 
       [
           .config.inputs[] 
	      |
	          {
	                "FileName": .object.file_id
		      , "FileId": .object.file_id
		      , "FileType": .location.name
      		  }
       ]
     ) as $Inputs
   | (
        [
	   .outputs[]
              |
             {
	                "FileName": .name
		      , "FileId": .file_id
		      , "FileType": .type
	     }
	 ]
      ) as $Outputs

    | {
         "JobInfo": {
	       "JobId": $JobId
	     , "JobDateTime": $JobDateTime
	    }
	  , "GearInfo": {
	        "GearId": $GearId
		, "GearName": $GearName
		, "GearVersion": $GearVersion
	    }
	  , "Inputs": $Inputs
	  , "Outputs": $Outputs
	}