
def mriInfo(m): (
    if (m.Missing == true) then 

             "Missing"
           , "Missing"
           , "Missing"
           , "Missing"

    else

            m.AcquisitionLabel
         ,  m.AcquisitionId
    	 ,  m.FileName
    	 ,  m.FileId

    end
);

def segAnalysisInfo(m): (
            m.AnalysisLabel
    	  , m.AnalysisId
);

def segInfo(m): (

    	    m.FileName
    	  , m.FileId

);

def baselineSessionInfo(s): (

            s.SessionLabel
	  , s.SessionId
	  , s.SessionScanDateTime
	  , mriInfo(s.T1)
	  , mriInfo(s.T2)
	  , segAnalysisInfo(s.T1LeftSegmentation)
	  , segInfo(s.T1LeftSegmentation)
	  , segInfo(s.T1RightSegmentation)
	  , segAnalysisInfo(s.T2LeftSegmentation)
	  , segInfo(s.T2LeftSegmentation)
	  , segInfo(s.T2RightSegmentation)

);

def followupSessionInfo(s): (

        s.SessionLabel
      , s.SessionId
      , s.SessionScanDateTime
      , mriInfo(s.T1)
      , mriInfo(s.T2)

);

if ($Headers) then
   [
   	"BaselineSessionLabel"
      , "BaselineSessionId"
      , "BaselineSessionScanDateTime"
      , "BaselineT1AcquisitionLabel"
      , "BaselineT1AcquisitionId"
      , "BaselineT1FileName"
      , "BaselineT1FileId"
      , "BaselineT2AcquisitionLabel"
      , "BaselineT2AcquisitionId"
      , "BaselineT2FileName"
      , "BaselineT2FileId"
      , "BaselineT1AnalysisLabel"
      , "BaselineT1AnalysisId"
      , "BaselineT1LeftSegmentationFileName"
      , "BaselineT1LeftSegmentationFileId"
      , "BaselineT1RightSegmentationFileName"
      , "BaselineT1RightSegmentationFileId"
      , "BaselineT2AnalysisLabel"
      , "BaselineT2AnalysisId"
      , "BaselineT2LeftSegmentationFileName"
      , "BaselineT2LeftSegmentationFileId"
      , "BaselineT2RightSegmentationFileName"
      , "BaselineT2RightSegmentationFileId"
      , "FollowupSessionLabel"
      , "FollowupSessionId"
      , "FollowupSessionScanDateTime"
      , "FollowupT1AcquisitionLabel"
      , "FollowupT1AcquisitionId"
      , "FollowupT1FileName"
      , "FollowupT1FileId"
      , "FollowupT2AcquisitionLabel"
      , "FollowupT2AcquisitionId"
      , "FollowupT2FileName"
      , "FollowupT2FileId"
  ] | @csv
else
    [ baselineSessionInfo(.Baseline) ] as $BaselineInfo
  | .Followups[] | ($BaselineInfo + [ followupSessionInfo(.) ])  | @csv
end