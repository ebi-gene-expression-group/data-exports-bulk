#!/usr/bin/env bash
set -e

scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

[ ! -z ${ATLAS_EXPS+x} ] || ( echo "Env var ATLAS_EXPS path to the experiment needs to be defined." && exit 1 )
[ ! -z ${ATLAS_EBEYE+x} ] || ( echo "Env var ATLAS_EBEYE path to the ebeye dump directory needs to be defined." && exit 1 )

pushd $ATLAS_EBEYE


## back up oldfiles
today=`eval date +%d%b%Y`
mkdir -p archive/$today
find . -name \*.xml -exec cp -p {} ./archive/$today \;

$scriptDir/export_atlas_ebeye_xml.pl
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to generate EB-eye dump"
    exit 1
fi
cp ebeye*.xml $ATLAS_EXPS
popd
