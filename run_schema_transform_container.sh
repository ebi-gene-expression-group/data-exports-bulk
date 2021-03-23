#!/usr/bin/env bash 

[ -z ${INPUT_JSON+x} ] && echo "Error: variable INPUT_JSON is not defined." && exit 1 
[ -z ${SCHEMA_TRANSFORM+x} ] && echo "Error: variable SCHEMA_TRANSFORM is not defined." && exit 1 
[ -z ${PROCESSED_JSON+x} ] && PROCESSED_JSON="processed_output.json"
[ -z ${IMAGE_NAME+x} ] && IMAGE_NAME="json_schema_transform"

[ -z ${OUTPUT_DIR+x} ] && OUTPUT_DIR=$(pwd)/"outputs"
[ ! -d $OUTPUT_DIR ] && mkdir $OUTPUT_DIR

container=$1
if [ $container == "docker" ]; then
    docker run -v $INPUT_JSON:/data/input.json \
               -v $SCHEMA_TRANSFORM:/data/schema_transform.jslt \
               -v $OUTPUT_DIR:/data/outputs \
               -e PROCESSED_JSON=$PROCESSED_JSON \
               $IMAGE_NAME /src/run_schema_transform.sh
elif [ $container == "singularity" ]; then
    singularity exec -B $INPUT_JSON:/data/input.json \
               -B $SCHEMA_TRANSFORM:/data/schema_transform.jslt \
               -B $OUTPUT_DIR:/data/outputs \
               --env PROCESSED_JSON=$PROCESSED_JSON \
               docker://$IMAGE_NAME /src/run_schema_transform.sh
else
    echo "Variable 'container' must be set to 'docker' or 'singularity', please provide one of them as first argument." && exit 1
fi
