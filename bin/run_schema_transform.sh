#!/usr/bin/env bash 
touch /data/outputs/$PROCESSED_JSON
java -cp /app/run-jslt.jar com.schibsted.spt.data.jslt.cli.MultiLineJSLT \
         /data/schema_transform.jslt /data/input.json | jq -c . >> /data/outputs/$PROCESSED_JSON
