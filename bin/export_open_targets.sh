#!/bin/bash
set -euo pipefail

[ ! -z ${dbConnection+x} ] || ( echo "Env var dbConnection for the atlas database." && exit 1 )

scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

#defaults
atlasUrl=${atlasUrl:-"https://wwwdev.ebi.ac.uk/gxa"}
urlParams=${urlParams:-"logFoldChangeCutoff=1.0&pValueCutoff=0.05&maxGenesPerContrast=1000"}
destination=${destination:-"$ATLAS_FTP/experiments/cttv010-$(date "+%Y-%m-%d").json"}
usageMessage="Usage: (-a $atlasUrl) (-p urlParams:$urlParams) (-d destination:$destination) (-o outputPath:outputPath)"

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
      <( psql $dbConnection -tA -F $'\t' <<< "select distinct accession from experiment where species='Homo sapiens' and type like '%DIFFERENTIAL' and private='F' " \
        | sort ) \
      <( cut -f1 -d ' ' "experiments-exclude.tmp" | sort)
}

rm -rf ${destination}.tmp
touch ${destination}.tmp

trap 'mv -fv ${destination}.tmp ${destination}.failed; exit 1' INT TERM EXIT

listExperimentsToRetrieve | while read -r experimentAccession ; do
    "$scriptDir/ot_fetch_evidence.sh" -e $experimentAccession -a $atlasUrl -p $urlParams >> ${destination}.tmp
done
rm -rf experiments-exclude.tmp

trap - INT TERM EXIT


echo "Successfully fetched and validated evidence, zipping..."
mv -nv ${destination}.tmp $destination
gzip $destination

echo "Sanity check .."
"$scriptDir/ot_json_queries_stats.sh" -j ${destination}.gz -o $outputPath
