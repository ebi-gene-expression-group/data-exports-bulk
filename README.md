# Atlas Data Exports module (v0.1.0)

This module provides functionality for the Atlas Production data exports processes:

- OpenTargets json export.
- ChEBI export.
- EBEYE export.
- Large Atlas tar.gz export for bulk.

Exports are normally executed between the pre-release date and the release date,
as they require release data loaded in a wwwdev or equivalent web deployment.

Our central Jenkins provision has execution jobs for all of these.

Version 0.1.0 was used for the Nov 2018 release.

### Open Targets JSON schema transform
`bin/schema_transform.jslt` file contains logic required to migrate JSON files across different schemas. To run transformation into the new Open Targets schema, use the [JSLT](https://github.com/schibsted/jslt) Java library. The simplest way is to run it via command-line: 
```
# build the binary 
cd ./jslt
./gradlew clean shadowJar

java -cp build/libs/*.jar com.schibsted.spt.data.jslt.cli.JSLT transform.jslt old_schema.json
```
