
def mriInfo(m): (
    if (m.Missing == true) then 
       {
             "AcquisitionLabel": "Missing"
           , "AcquisitionId": "Missing"
           , "FileName": "Missing"
           , "FileId": "Missing"
       }
    else
       {
            "AcquisitionLabel": m.AcquisitionLabel
         ,  "AcquisitionId": m.AcquisitionId
    	 ,  "FileName": m.FileName
    	 ,  "FileId": m.FileId
       }
    end
);

def segAnalysisInfo(m): (
    {
            "AnalysisLabel": m.AnalysisLabel
    	  , "AnalysisId": m.AnalysisId
	  , "AnalysisTimestamp": m.AnalysisTimestamp
    }
);

def segInfo(m): (
    {
    	    "FileName": m.FileName
    	  , "FileId": m.FileId
    }
);

def baselineSessionInfo(s): (
    {
            "SessionLabel": s.SessionLabel
	  , "SessionId": s.SessionId
	  , "SessionScanDateTime": s.SessionScanDateTime
	  , "T1": mriInfo(s.T1)
	  , "T2": mriInfo(s.T2)
	  , "T1Analysis": segAnalysisInfo(s.T1LeftSegmentation)
	  , "T1LeftSegmentation": segInfo(s.T1LeftSegmentation)
	  , "T1RightSegmentation": segInfo(s.T1RightSegmentation)
	  , "T2Anlysis": segAnalysisInfo(s.T2LeftSegmentation)
	  , "T2LeftSegmentation": segInfo(s.T2LeftSegmentation)
	  , "T2RightSegmentation": segInfo(s.T2RightSegmentation)
    }
);

def followupSessionInfo(s): (
    {
        "SessionLabel": s.SessionLabel
      , "SessionId": s.SessionId
      , "SessionScanDateTime": s.SessionScanDateTime
      , "T1": mriInfo(s.T1)
      , "T2": mriInfo(s.T2)
    }
);

    baselineSessionInfo(.Baseline) as $BaselineInfo
  | .Followups[] | { "Baseline": $BaselineInfo, "Followup": followupSessionInfo(.) }
