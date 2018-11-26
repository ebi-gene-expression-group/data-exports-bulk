#!/bin/bash

#defaults
atlasUrl="https://wwwdev.ebi.ac.uk/gxa"
urlParams=""
experimentAccession=""

usageMessage="Usage: (-a $atlasUrl) (-p urlParams:$urlParams) -e experimentAccession"

if [[ -v "${JSON_VALIDATOR_CACHE_PATH-}" ]]; then
    export JSON_VALIDATOR_CACHE_PATH
    JSON_VALIDATOR_CACHE_PATH=/var/tmp/open-targets-evidence-schema-cache-`date "+%Y-%m-%d"`
    rm -rf $JSON_VALIDATOR_CACHE_PATH
    mkdir $JSON_VALIDATOR_CACHE_PATH
fi

while getopts ":a:p:e:" opt; do
  case $opt in
    a)
      atlasUrl=$OPTARG;
      ;;
    p)
      urlParams=$OPTARG;
      ;;
    e)
      experimentAccession=$OPTARG;
      ;;
    ?)
      echo "Unknown option: $OPTARG"
      echo $usageMessage
      exit 2
      ;;
  esac
done

if [ ! "$experimentAccession" ] ; then
    echo $usageMessage
    exit 2
fi

>&2 echo "Retrieving experiment $experimentAccession ... "
>&1 curl -s -w "\n" "$atlasUrl/json/experiments/$experimentAccession/evidence?$urlParams" \
    | grep -v -e '^[[:space:]]*$' \
    | "$( dirname "${BASH_SOURCE[0]}" )"/ot_json_schema_validator.pl \
      --schema='https://raw.githubusercontent.com/opentargets/json_schema/master/src/expression.json' \
      --add-validation-stamp
