#!/usr/bin/env bats


@test "Check JSON schema transformation" {
    run rm -f $test_data/reproduced_file.json &&\
    java -cp $java_core_lib_path/build/libs/core-0.1.11-all.jar\
             com.schibsted.spt.data.jslt.cli.JSLT $test_data/schema_transform.jslt\
             $test_data/old_schema.json > $test_data/reproduced_file.json 

    [ "$status" -eq 0 ]
    [ -f $test_data/reproduced_file.json ]
}


