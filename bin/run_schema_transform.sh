#!/usr/bin/env bash 

[ -z ${PROCESSED_JSON}+x ] && echo "Error: variable PROCESSED_JSON is not defined." && exit 1 
[ -z ${INPUT_JSON}+x ] && echo "Error: variable INPUT_JSON is not defined." && exit 1 
[ -z ${SCHEMA_TRANSFORM}+x ] && echo "Error: variable SCHEMA_TRANSFORM is not defined." && exit 1 

touch /data/$PROCESSED_JSON
touch /data/tmp_1.txt

while read line; do
    echo "LINE" >> /data/tmp_1.txt
    echo $line > tmp.json
    java -cp /app/run-jslt.jar com.schibsted.spt.data.jslt.cli.JSLT /data/$SCHEMA_TRANSFORM tmp.json >> /data/$PROCESSED_JSON
done < /data/$INPUT_JSON