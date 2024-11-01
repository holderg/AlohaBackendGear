#
# fwfind -1 -j -rgz session=66e4737ead8f9c0ea1ce2750 | jq -r --argjson Atlas '"ASHS-PMC-T1"' --argjson Handedness '"Left"' -f alohaFindSegmentFiles.jq
#
[
	.[]
    |   select( (.state == "complete") and ((.outputs | length) > 0) )
    | .created as $AnalysisCreatedTimestamp
    | .destination.id as $AnalysisId
    | .detail.parent_info.analysis.label as $AnalysisLabel
    | .detail.parent_info.group.label as $GroupLabel
    | .detail.parent_info.project.label as $ProjectLabel
    | .detail.parent_info.subject.label as $SubjectLabel
    | .detail.parent_info.session.label as $SessionLabel
    | 
        .outputs[]
    | select(
                ((.tags | length) > 0)
            and (.tags | any(. == "AlohaInput"))
	    and (.tags | any(. == $Atlas) )
	    and (.tags | any(. == $Handedness) )
 	    and (.modality == "SEG")
     )
   | {
	  "FileName": .name
	, "FileId": .file_id
	, "FileType": .type
	, "FileTags": (.tags | sort | join(":"))
	, "FileModality": .modality
	, "FileTimestamp": .created
#	, "group": $GroupLabel
#	, "project": $ProjectLabel
#	, "subject": $SubjectLabel
#	, "session": $SessionLabel
	, "analysis": $AnalysisLabel
	, "analysisId": $AnalysisId
	, "analysisTimestamp": $AnalysisCreatedTimestamp
      }
      ]
 | sort_by(.FileTimestamp) | last