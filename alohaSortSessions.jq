#
# fwget -1 -raGz 66e4737e1b4b58bc3236d6d1 | 
# where 66e4737e1b4b58bc3236d6d1 is a SubjectId
#
# *** This uses the file created date, which is when the file hits flywheel, not when the dicom.zip file was created
#

include "FwLib";

def getFileCreatedDateTime(f): (
    (if (f.info.AcquisitionDate) then f.info.AcquisitionDate else f.info.SeriesDate end)
);

def fmtDateTime(d; t): (
    (
       d | sub("(?<year>\\d{4})(?<month>\\d{2})(?<day>\\d{2})"; "\(.year)-\(.month)-\(.day)")
    )
    + "T" +
    (
	t | sub("(?<hours>\\d{2})(?<minutes>\\d{2})(?<seconds>\\d{2})\\.\\d+"; "\(.hours):\(.minutes):\(.seconds)")
    )
    + "+00:00"
);


      [.sessions[]
          |[ .label as $SessionLabel
          | ._id as $SessionId
	  | sessionScanDateTime(.) as $SessionScanDateTime
	  | select((.acquisitions | length) > 0)
          | .acquisitions[]
	       | .label as $AcquisitionLabel
	       | ._id as $AcquisitionId
	       | .created as $AcquisitionCreated
	       | .files[]
               |    select(
                                ((.type == "nifti") or (.type == "archive") or (.type == "dicom"))
                            and (.modality == "MR")
			    and ((.classification | length) > 0)
			    and ((.classification.Intent | length) > 0)
                            and (.classification.Intent | any("Structural"))
			    and ((.classification.Measurement | length) > 0)
                            and (.classification.Measurement | any((. == "T1") or (. == "T2")))
                            and ((.tags | length) > 0)
                            and (.tags | any(. == "AlohaInput"))
			    and (getFileCreatedDateTime(.) != null)
                   ) 
                   | .name as $FileName
		   | .file_id as $FileId
		   |
	                { 
			    "SessionLabel": $SessionLabel
			  , "SessionId": $SessionId
			  , "SessionScanDateTime": $SessionScanDateTime
#			  , "AcquisitionLabel": $AcquisitionLabel
#			  , "AcquisitionId": $AcquisitionId
#			  , "AcquisitionCreated": $AcquisitionCreated
#			  , "FileName": $FileName
#			  , "FileId": $FileId
#			  , "FileCreated": .created
#			  , "FileClassificationMeasurement": .classification.Measurement[]
			}
            ] | sort_by(.SessionScanDateTime) | last

      ]
      | [ .[] | select(.)] |  sort_by(.SessionScanDateTime)
	as $SessionInfo
	| {
 	      "Baseline": ($SessionInfo | first)
	    , "Followups": ($SessionInfo | .[1:])
	  }
