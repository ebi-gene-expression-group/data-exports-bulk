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
`bin/schema_transform.jslt` file contains logic required to migrate JSON files across different schemas. To run transformation into the new Open Targets schema, use the [JSLT](https://github.com/schibsted/jslt) Java library. The simplest way is to run it via docker container: 

```
./bin/run_schema_transform_container.sh <container>
```
Where <container> is either 'docker' or 'singularity'
The output file will be found in the `outputs` dir within current directory. 

The following variables must be defined: 

- `INPUT_JSON` - absolute path to json file to be transformed. This can either be a single JSON in 'long' format or a multi-line file where each line corresponds to a JSON object. 
- `SCHEMA_TRANSFORM` - absolute path to JSLT file specifying transformation logic. See dcoumentation [here]((https://github.com/schibsted/jslt) for more detail. See file `data/schema_transform.jslt` as example. 

Optional variables: 
- `PROCESSED_JSON` - specify name of output processed json file
- `OUTPUT_DIR` - specify absolute path to output directory
- `IMAGE_NAME` - specify Docker image name to be used



