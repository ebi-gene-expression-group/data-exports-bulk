set -euo pipefail

scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

atlasUrl=${atlasUrl:-"https://wwwdev.ebi.ac.uk/gxa"}

[ ! -z ${lastReleaseDate+x} ] || ( echo "Env var lastReleaseDate as DDMonYYYY needs to be defined. " && exit 1 )
[ ! -z ${ATLAS_EXPS+x} ] || ( echo "Env var ATLAS_EXPS needs to be defined. " && exit 1 )

# Get mapping between Atlas experiments and Ensembl DBs that own their species
get_experiments_loaded_since_date() {
    sinceDateSecondsEpoch=$(date --date="$1" +%s)

    # dates from REST API come formatted as dd-mm-yyyy so we need to transform them
    curl -s $atlasUrl/json/experiments \
      | jq -r --arg sinceDate "$sinceDateSecondsEpoch" '.aaData | map( .lastUpdate |= (strptime("%d-%m-%Y") | mktime) | select( .lastUpdate > ($sinceDate | tonumber) ) | .experimentAccession) | @csv' \
      | tr -s ',' '\n' | sed 's/"//g' | sort -u
}


pushd $ATLAS_EXPS

rm -rf ~/tmp/release_data.aux.*
aux=~/tmp/release_data.aux.$$

# 7. tar/gz all experiments in $ATLAS_EXPS into  $ATLAS_EXPS/atlas-latest-data.tar.gz
# Identify all experiments loaded since $lastReleaseDate
get_experiments_loaded_since_date $lastReleaseDate > $aux.exps_loaded_since_$lastReleaseDate
# Unzip previous release tar.gz
gunzip atlas-latest-data.tar.gz
# Identify all experiments removed since $lastReleaseDate
tar -tvf atlas-latest-data.tar | grep '/$' | sed 's|\/$||' | awk '{print $NF}' | sort | uniq > $aux.exps_in_release_$lastReleaseDate
ls -la | grep E- | egrep -v 'rwxr-x-' | awk '{print $NF}' | sort > $aux.all_current_experiments
comm -3 $aux.exps_in_release_$lastReleaseDate $aux.all_current_experiments | grep '^E-'> $aux.exps_removed_since_last_release
# First remove from atlas-latest-data.tar all experiments in $aux.exps_removed_since_last_release
for e in $(cat $aux.exps_removed_since_last_release); do
    echo "Removing $e ..."
    tar --delete $e -f atlas-latest-data.tar
    if [ $? -ne 0 ]; then
        echo "ERROR: removing $e from atlas-latest-data.tar"
        exit 1
    fi
done
# Now add/update in atlas-latest-data.tar all experiments in $aux.exps_loaded_since_$lastReleaseDate
for e in $(cat $aux.exps_loaded_since_$lastReleaseDate); do
    echo "Adding/updating $e ..."
    tar -r $e --exclude "$e/qc" --exclude "$e/archive" -f atlas-latest-data.tar
    if [ $? -ne 0 ]; then
        echo "ERROR: adding/updating $e in atlas-latest-data.tar"
        exit 1
    fi
done
gzip atlas-latest-data.tar
