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
