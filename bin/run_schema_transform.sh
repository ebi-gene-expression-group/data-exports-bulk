#!/usr/bin/env bash 

touch /data/processed_output.json

while read line; do
    echo $line > tmp.json
    java -cp /app/run-jslt.jar com.schibsted.spt.data.jslt.cli.JSLT /data/schema_transform.jslt  /data/old_schema.json >> /data/reproduced_file.json
done < input_file.json 