#!/usr/bin/env bash 

export test_data=$(pwd)/test_data
export java_core_lib_path=$(pwd)/jslt/core

run_tests.bats
