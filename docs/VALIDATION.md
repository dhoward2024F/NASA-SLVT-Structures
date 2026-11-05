# Validation record — November 5, 2026

## Automation and dashboard

Executed against the repository's full-scale model and configured L2200G motor:

- `python -m unittest discover -s tests -v`: six tests passed. Coverage includes 60-case expansion, the paired six-case custom condition, invalid inputs, inclusive limits, file fingerprints, and missing/stale/failed/incomplete report handling. Missing section and requirement records cannot produce a complete report.
- Local HTTP tests verified loopback binding, token/cookie access, Host validation, content security headers, and rejection of model-file and `.git` paths.
- `node --check dashboard/app.js`: passed.
- Browser inspection confirmed the desktop layout, live-data rendering, payload/recovery filters, case search, case drill-down, and three-section retained-payload details. Tests used an isolated local static snapshot for the preview; the shipped local server's access controls were tested separately over HTTP.
- The existing MATLAB numerical source ran under GNU Octave 8.4.0 for all 60 configured cases: 210 section records and 870 requirement evaluations, without simulation errors.
- Real OpenRocket 24.12 / Java 17 simulations ran the ten unique wind/angle conditions in `SLVT_2627_FS_PDR_LVC1_V2.ork`; their explicitly labeled ascent metrics were joined to all 60 case names, producing 180 supplementary checks. No cached `.ork` simulation results were used.
- Both reports were complete and matched the input fingerprint when generated. A subsequent model/config/adapter edit correctly invalidates that status.

The supplied model predicts **30 failed section-energy checks**, all for the deployed payload/nosecone at approximately 105.0 ft-lbf versus the 75 ft-lbf limit. All other supported checks in this run passed. The requirement gate intentionally reports failure while retaining usable reports. These results include the existing mass fallbacks and model assumptions; they are not a flight approval.

The motor path was corrected to the existing L2200G CSV, and `matlab/startSLVT.m` was corrected to locate its adjacent `app/` folder. MATLAB static analysis passed for the two changed `.m` files. The numerical flight engine was not changed in this automation update.

## MATLAB repository integration

`testSLVTRepository` passed in GNU Octave 8.4.0, using the actual MATLAB source, bundled L2200G CSV, and a 0.005-second test timestep:

- 66 cases (60 standard plus 6 custom), 18 distinct vertical trajectories, 231 section results, and 957 requirement evaluations.
- Save/load roundtrip, paths containing spaces, exact paired custom-case expansion, duplicate names, invalid custom inputs, JSON/CSV exports, inclusive bounds, missing metrics, CSV/RASP motor handling, multi-motor rejection, and numerical-failure reporting.
- Agreement with a separate direct call to the shared engine, within the test's 1e-8 trajectory and 1e-9 apogee/energy tolerances.
- An explicitly missing motor in the temporary fixture was rejected. The fixture then saved and analyzed L2200G. This error-path test no longer depends on the real repository having a missing motor file.

The original app's historical validation record remains in `matlab/app/VALIDATION.md`.

## Limits of this validation

Native MATLAB and its desktop GUI were not available in the delivery environment. MATLAB table/MAT exports and UI/settings interactions therefore were not rerun here. The workflow includes optional `testSLVTFlightApp(false)` when a MathWorks license token is configured; on a MATLAB desktop, run `testSLVTFlightApp(true)` and exercise the Repository menu.

No independent flight-model accuracy, complete NASA handbook compliance, CAD reconciliation, or independent OpenRocket payload/recovery model was verified. The OpenRocket comparison covers ascent only. See [model interpretation](AUTOMATION.md).

GitHub execution status is recorded separately by each **Mission analysis** workflow run; the local test results above do not imply that a GitHub runner has already completed.


## GitHub Pages adaptation — November 5, 2026

The dashboard now supports a static Pages data source with relative asset URLs, publication context, and repository/workflow links. The Pages packager uses an explicit file/data allowlist and preserves failed and missing result statuses. Tests confirm that source manifests and other repository files do not enter the site package, stale generated files are removed, and publishing requires a boolean opt-in.

Eight Python tests and JavaScript syntax checking passed. Publishing remains disabled pending the user's decision about public access; these checks do not imply a live Pages deployment.
