
def mriInfo(m): (
    if (m.Missing == true) then 
          ("Missing", "Missing", "Missing", "Missing")
    else
           m.AcquisitionLabel
         , m.AcquisitionId
    	 , m.FileName
    	 , m.FileId
    end
);

def segInfo(m): (
      m.AnalysisLabel
    , m.AnalysisId
    , m.FileName
    , m.FileId
);

def baselineSessionInfo(s): (
      s.SessionLabel
    , s.SessionId
    , s.SessionScanDateTime
    , mriInfo(s.T1)
    , mriInfo(s.T2)
    , segInfo(s.T1LeftSegmentation)
    , segInfo(s.T1RightSegmentation)
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

    [ baselineSessionInfo(.Baseline) ] as $BaselineInfo
  | .Followups[] | ($BaselineInfo + [ followupSessionInfo(.) ]) | @csv
