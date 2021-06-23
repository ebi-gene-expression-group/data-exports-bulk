#!/usr/bin/env bats

@test "Check JSON schema transformation in container" {
    run rm -f $PROCESSED_JSON &&\
        run_schema_transform_container.sh $container

    [ "$status" -eq 0 ]
    [ -f "outputs/processed_output.json" ]
}

@test "Run enrichEBEyeXMLDump doctests" {
    run pytest bin/enrichEBEyeXMLDump.py
    
    [ "$status" -eq 0 ]
}
