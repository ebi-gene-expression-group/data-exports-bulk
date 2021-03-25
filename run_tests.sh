#!/usr/bin/env bash 

export test_data=$(pwd)/test_data
export INPUT_JSON=$test_data/'test_input.json'
export SCHEMA_TRANSFORM=$test_data/'schema_transform.jslt'
export IMAGE_NAME="quay.io/ebigxa/json_schema_transform"
export container="docker"

# run test in container 
run_tests.bats
