#
# https://stackoverflow.com/questions/37540717/flatten-nested-json-using-jq/37555908#37555908
#
  reduce ( tostream | select(length==2) | .[0] |= [join("_")] ) as [$p,$v] (
     {}
     ; setpath($p; $v)
  )

