#!/usr/bin/env bash

scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

[ ! -z ${ATLASPROD_PATH+x} ] || ( echo "Env var ATLASPROD_PATH path to the directory needs to be defined." && exit 1 )
[ ! -z ${BASELINE_META_DESTINATION+x} ] || ( echo "Env var BASELINE_META_DESTINATION path to the baseline baseline meta analysis directory needs to be defined." && exit 1 )
[ ! -z ${BLUEPRINT_STUDIES+x} ] || ( echo "Env var BLUEPRINT_STUDIES comma separated blueprint baseline studies needs to be defined." && exit 1 )
[ ! -z ${GTEX_STUDIES+x} ] || ( echo "Env var GTEX_STUDIES comma separated gtex baseline studies needs to be defined." && exit 1 )


export outpath_path=${BASELINE_META_DESTINATION}/output_$(date "+%Y-%m-%d")

# Set path (this is done at this level since this will be executed directly):
for mod in data-exports-bulk; do
    export PATH=$ATLASPROD_PATH/$mod:$PATH
done

## Run the normalisation and batch correction of gtex and associated studies
RUV_normalisation_gtex.R $GTEX_STUDIES $outpath_path
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to normalise Gtex associated studies"
    exit 1
fi

## Run the normalisation and batch correction of blueprint studies
 RUV_normalisation_BluePrint.R $BLUEPRINT_STUDIES $outpath_path
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to normlalise blueprint associated studies"
    exit 1
fi

## combine corrected gtex and blueorint
RUV_gtex_blueprint_combine.R $outpath_path
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to combine studies"
    exit 1
fi
