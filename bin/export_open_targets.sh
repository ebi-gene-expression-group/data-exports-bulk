#!/bin/bash

scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

#defaults
atlasUrl=${atlasUrl:-"https://wwwdev.ebi.ac.uk/gxa"}
urlParams=${urlParams:-"logFoldChangeCutoff=1.0&pValueCutoff=0.05&maxGenesPerContrast=1000"}
destination=${destination:-"$ATLAS_FTP/experiments/cttv010-$(date "+%Y-%m-%d").json"}
usageMessage="Usage: (-a $atlasUrl) (-p urlParams:$urlParams) (-d destination:$destination) (-o outputPath:outputPath)"
venvPath=${venvPath:-"$ATLAS_PROD/venvs"}

[ ! -z ${jsonSchemaVersion+x} ] || ( echo "Env var jsonSchemaVersion needs to be defined." && exit 1 )


echo "To exclude experiments for open-targets, export env var EXPERIMENTS_TO_EXCLUDE=ACC1;...;ACCi;..ACCn"

while getopts ":a:p:d:o:" opt; do
  case $opt in
    a)
      atlasUrl=$OPTARG;
      ;;
    p)
      urlParams=$OPTARG;
      ;;
    d)
      destination=$OPTARG;
      ;;
    o)
      outputPath=$OPTARG;
      ;;
    ?)
      echo "Unknown option: $OPTARG"
      echo $usageMessage
      exit 2
      ;;
  esac
done

listExperimentsToRetrieve(){
    IFS='; ' read -r -a exclude_exp <<< "$EXPERIMENTS_TO_EXCLUDE"
    printf "%s\n" "${exclude_exp[@]}" > experiments-exclude.tmp
    comm -23 \
      <( curl -s $atlasUrl/json/experiments | jq -c -r '.experiments | map(select(.species=="Homo sapiens")) | map(select(.experimentType | test("(MICROARRAY)|(DIFFERENTIAL)"; "i")) |.experimentAccession) | @csv' | tr -s ',' '\n' | sed 's/"//g' \
        | sort -u ) \
      <( cut -f1 -d ' ' "experiments-exclude.tmp" | sort)
}

rm -rf ${destination}.tmp
touch ${destination}.tmp

trap 'mv -fv ${destination}.tmp ${destination}.failed; exit 1' INT TERM EXIT

listExperimentsToRetrieve | while read -r experimentAccession ; do
  echo "Retrieving experiment $experimentAccession ... "
  curl -s -w "\n" "$atlasUrl/json/experiments/$experimentAccession/evidence?$urlParams" | grep -v -e '^[[:space:]]*$' > $experimentAccession.tmp.json
  if [ -s "$experimentAccession.tmp.json" ]; then
    opentargets_validator --schema https://raw.githubusercontent.com/opentargets/json_schema/${jsonSchemaVersion}/opentargets.json $experimentAccession.tmp.json 2>$experimentAccession.err
    if [ $(wc -l < $experimentAccession.err) -eq 0 ]; then
      cat $experimentAccession.tmp.json >> ${destination}.tmp
      rm $experimentAccession.tmp.json
      rm $experimentAccession.err
    else
      echo "$experimentAccession failed validation."
      cat $experimentAccession.err
      exit 1
    fi
  else
    echo "WARN: $experimentAccession.tmp.json empty response"
  fi 
done
rm -rf experiments-exclude.tmp

trap - INT TERM EXIT


echo "Successfully fetched and validated evidence, zipping..."
mv -nv ${destination}.tmp $destination
gzip $destination

echo "Sanity check .."
"$scriptDir/ot_json_queries_stats.sh" -j ${destination}.gz -o $outputPath
