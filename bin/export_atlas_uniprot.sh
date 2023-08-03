#!/usr/bin/env bash

# What this script does:
# 1. Gets all unique UniProt IDs in Atlas bulk-analytics collection
# 2. Generates an Atlas search link for each UniProt ID
# 3. Writes everything to file

# Caveats:
# 1. Only works for bulk-analytics for now. There seems to be no  in scxa solr (???) still waiting for reply from devs
# 2. Only gets 100 unique uniprot IDs...seems odd.  Still investigating this.
# Check that relevant env vars are set
[ -z ${SOLR_HOST+x} ] && echo "Env var SOLR_HOST needs to be defined." && exit 1
[ -z ${SOLR_USER+x} ] && echo "Env var SOLR_USER needs to be defined." && exit 1
[ -z ${SOLR_PASS+x} ] && echo "Env var SOLR_PASS needs to be defined." && exit 1

command -v jq &>/dev/null || { echo "jq is not installed."; exit 1; }


atlasUniqueUniprotUrl="http://${SOLR_HOST}/solr/bulk-analytics-v1/select?facet.field=keyword_uniprot&facet=on&q=*:*&rows=0&start=0"
ATLAS_UNIPROT_EXPORT_FILE=${$1:-$ATLAS_UNIPROT_EXPORT_FILE}
today=$( eval date +%F_%Hh%Mm%Ss )
datedExportFile="${ATLAS_UNIPROT_EXPORT_FILE}.${today}"

# Get all unique UNIPROT IDs in bulk-analytics
uniprot_ids=$(curl -u $SOLR_USER:$SOLR_PASS $atlasUniqueUniprotUrl | jq '.facet_counts.facet_fields["keyword_uniprot"]' | grep -Po '(?<=\")[a-z0-9]+')

# Generate Atlas search links
for uniprot_id in $uniprot_ids; do
    url="https://wwwdev.ebi.ac.uk/gxa/search?geneQuery=[{%22value%22:%22${uniprot_id}%22,%20%22category%22:%22uniprot%22}]"
    echo -e "${uniprot_id}\t${url}" >> $datedExportFile
done

rm -f $ATLAS_UNIPROT_EXPORT_FILE
ln -s $ATLAS_UNIPROT_EXPORT_FILE $datedExportFile
