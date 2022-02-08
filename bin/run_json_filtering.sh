#!/usr/bin/env bash

# parse arguments
json_to_process=$1
ensembl_genes=$2
excluded_biotypes=$3

[  -z $json_to_process ] && echo "Error: JSON file to process must be defined." && exit 1
[  -z $ensembl_genes ] && echo "Error: Ensembl genes file must be defined." && exit 1
[  -z $excluded_biotypes ] && echo "Error: excluded biotypes file must be defined." && exit 1

# filter evidence strings where target.activity is unknown
[ -f tmp.json ] && rm -f tmp.json
[ -f tmp.discarded_activity.json ] && rm -f tmp.discarded_activity.json

jq -c '. | select( .target.activity == "" or ( .target.activity | contains("unknown")) | not )' $json_to_process > tmp.json
jq -c '. | select( .target.activity == "" or ( .target.activity | contains("unknown")) )' $json_to_process > tmp.discarded_activity.json

if [[ -f tmp.json ]]; then
    # find genes that have correct biotype
    cat $ensembl_genes | grep -v -f $excluded_biotypes | grep -v "ensgene" | cut -f 1,1 > filtered_genes.txt
    # filter out genes with unwanted biotype
    grep -f filtered_genes.txt tmp.json
else
    echo "No evidence lines with target.activity detected"
fi
