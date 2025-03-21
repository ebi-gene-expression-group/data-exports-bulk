#!/usr/bin/env bash
set -e

scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

[ ! -z ${ATLAS_EXPS+x} ] || ( echo "Env var ATLAS_EXPS path to the experiment needs to be defined." && exit 1 )
[ ! -z ${ATLAS_EBEYE+x} ] || ( echo "Env var ATLAS_EBEYE path to the ebeye dump directory needs to be defined." && exit 1 )
[ ! -z ${ATLAS_PROD+x} ] || ( echo "Env var ATLAS_PROD path to the ebeye dump directory needs to be defined." && exit 1 )

pushd $ATLAS_EBEYE


# backup old XML files
today=$(date +%d%b%Y)
mkdir -p archive/$today
find . -name \*.xml -exec cp -p {} ./archive/$today \;

# run export script
$scriptDir/export_atlas_ebeye_xml.pl
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to generate EB-eye dump"
    exit 1
fi

# copy new XML files to production directory
cp ebeye*.xml "$ATLAS_PROD/EBEYE_dumps"
echo "EB-eye dump successfully updated."

popd
