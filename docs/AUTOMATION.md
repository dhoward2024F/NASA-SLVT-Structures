# Mission analysis and dashboard

## Configuration ownership

| File | Purpose |
|---|---|
| `config/vehicle.json` | Shared MATLAB geometry, masses, parachutes, and motor-file reference |
| `config/launch_conditions.json` | Shared launch defaults; no wind-direction or launch-azimuth fields |
| `config/analysis_cases.json` | Explicit 60-case sweep and optional paired custom condition |
| `config/requirements.json` | The seven team-supplied NASA limits and requirement IDs |
| `config/matlab_model.json` | Section masses, model-specific settings, and explicit fallbacks for null shared fields |
| `config/automation.json` | Repository name, selected `.ork`, stored simulation index, pinned OpenRocket runtime, and deterministic wind settings |

The selected full-scale file is `vehicle/openrocket/SLVT_2627_FS_PDR_LVC1_V2.ork`, simulation index 0. The subscale model remains in the repository and is not selected. Change `model_file` and `simulation_index` deliberately when the authoritative model changes. The adapter rejects a motor designation that differs from `vehicle.json`; it does not replace the motor embedded in OpenRocket.

Repository MATLAB runs ignore personal GUI preferences. Null liftoff/payload mass, elevation, and rail-length fields use the explicit `matlab_model.json` fallbacks and are reported in the assumptions. Review those inputs before treating estimates as the current vehicle. The configured L2200G CSV has been connected to its actual repository path.

The `.gitattributes` file keeps text inputs at LF line endings across platforms so Windows Git checkout conversion does not falsely invalidate report fingerprints.

## GitHub Pages

The browser can load a published static dashboard directly from GitHub Pages. [Pages setup and access](PAGES.md) describes the explicit publishing opt-in and the public visibility of Pages on a personal account. The local server remains optional.

## Local usage

Viewing downloaded results needs only Python 3.10+ and GitHub CLI authenticated to this repository:

```sh
git pull
python scripts/sync_results.py
python scripts/serve_dashboard.py
```

To download a particular run, use `python scripts/sync_results.py --run-id NUMBER`. If no completed run exists yet, wait for **Actions → Mission analysis**, or run the models locally. Alternatively download the `mission-analysis` artifact from its GitHub Actions run and extract its `matlab/` and `openrocket/` folders under `results/`.

For local simulation, install Java 17, MATLAB or GNU Octave, and `python -m pip install -r requirements-automation.txt`. Commands from the repository root:

```sh
python scripts/preflight.py
python scripts/run_analysis.py
python scripts/check_requirements.py
```

`run_analysis.py` exits nonzero for engine/configuration failure. `check_requirements.py` additionally exits nonzero for failed limits or incomplete coverage. To run only one engine, add `--model matlab` or `--model openrocket`; the dashboard will still flag a missing or outdated counterpart. To choose the numerical runtime, use `--runtime matlab` or `--runtime octave`. For a nonstandard installation path, also supply `--executable "path/to/runtime"`.

The OpenRocket adapter uses JPype and the official Java core, not the GUI and not cached simulation values in the `.ork`. The pinned runtime is cached in `.tools/`. Its release version and full SHA-256 are in `config/automation.json`. The model is read without writing changes to the source file, and stored simulation extensions are rejected.

The standalone app remains available with `addpath('matlab'); app = startSLVT;` from MATLAB at the repository root. The UI needs MATLAB; Octave is only a headless numerical option. Running `run_ci` directly writes MATLAB reports, but use the Python wrapper for dashboard runs so provenance and freshness metadata are also attached.

## Automated workflow

`.github/workflows/mission-analysis.yml` runs on changes to models, config, adapters, dashboard, tests, or the workflow. It uses Ubuntu 24.04, Python 3.12, Java 17, and GNU Octave. Its stages are:

1. Install dependencies and restore the checked OpenRocket JAR cache.
2. Validate inputs, Python reporting/access tests, JavaScript syntax, and MATLAB repository integration.
3. Optionally run native MATLAB table/export tests with `MLM_LICENSE_TOKEN` on non-PR runs.
4. Run the current models and attach input fingerprints, runtime, time, commit, and workflow run ID.
5. Upload the `mission-analysis` artifact, including logs, even when simulation/mission checks fail.
6. Package `_site/` from the three dashboard assets and an allowlisted results snapshot; keep it as the private `dashboard-site` artifact.
7. In the separate **Vehicle requirement checks** job, require complete current reports and passing supported mission checks.
8. If `pages.enabled` is true, publish the dashboard from `main` in the separate `deploy` job, even if the mission-limit check failed. Test or simulation failures prevent deployment. Pull requests never deploy.

No repository-content write permission is granted to the workflow. It does not commit generated results. The separate Pages job has `pages: write` and `id-token: write`; it runs only after explicit Pages opt-in. Private repository Actions minutes and artifact limits still apply under the repository's GitHub plan. A test/setup failure can produce incomplete dashboard data; inspect the failed step rather than assuming there is a valid simulation report.

## Outputs and provenance

| Output | Use |
|---|---|
| `results/matlab/summary.json` | Cases, landing sections, requirements, model notes, and provenance |
| `results/matlab/*.csv` | Case, section, and requirement tables |
| `results/matlab/resolved_model.json` and `inputs/` | Effective configuration and copied MATLAB inputs |
| `results/openrocket/summary.json` | Ascent comparisons, supported checks, sampled trajectories, warnings, source model, and provenance |
| `results/*/run.log` | Engine diagnostics |
| `results/dashboard.json` | Combined portable snapshot |

The local server rebuilds its data from the engine reports and current files on each refresh. Pages uses the snapshot packaged at analysis time, identified by commit and timestamp; refreshing Pages does not rerun simulations or check uncommitted local files. A SHA-256 manifest includes config, MATLAB source, motor curves, OpenRocket models, and automation source. Local input edits therefore invalidate old reports even without a new commit. Matching a commit ID alone is insufficient. Pull the matching models or rerun to resolve an **Outdated** badge. Generated outputs and runtime caches are ignored by Git.

## Interpreting the checks

| Requirement | Limit | MATLAB model | OpenRocket adapter |
|---|---|---|---|
| 2.1 | 4,000–6,000 ft AGL | Vertical apogee | 3D apogee |
| 2.12 | Thrust-to-weight ≥ 5 | Burn-average thrust / liftoff weight | Not covered |
| 2.14 | Rail exit ≥ 52 ft/s | Inherited vertical rail-threshold estimate | OpenRocket launch-rod/rail exit speed |
| 2.20.6 | Mach ≤ 1 throughout flight | Maximum over vehicle and payload vertical histories | Ascent maximum only; supplementary comparison |
| 3.2 | Landing KE ≤ 75 ft-lbf per section | Each applicable section, using original section-mass convention | Not covered |
| 3.10 | Drift radius ≤ 2,500 ft | Constant wind × section descent time; lateral ascent excluded | Not covered |
| 3.11 | Apogee to touchdown ≤ 100 s | Each applicable section; last touchdown controls | Not covered |

All bounds are inclusive. A reported pass is a modeled estimate under these assumptions, not independent verification of the complete NASA handbook. The requirements file retains the team's supplied year/limits. The MATLAB ascent is vertical; its constant sound-speed and rail conventions are preserved. Shared temperature/pressure/coordinates are recorded but are not applied by the original MATLAB atmosphere model.

OpenRocket runs ten distinct wind/angle simulations for the standard matrix, then shares their **ascent** results across the six payload/recovery labels. Its geometry/mass/recovery definitions remain those in the `.ork`; shared geometry/mass JSON values do not update it. Latitude/longitude use the shared values when present; rail length/elevation use shared values or the documented MATLAB fallbacks. Wind direction, rail azimuth, and atmosphere settings remain those of the stored simulation. Fixed seed and zero turbulence give a deterministic comparison. OpenRocket does not claim independent recovery coverage for those labels.

The MATLAB model calculates 60 logical cases and reuses identical vertical histories where wind only changes drift. Deploy cases report four landing sections, retain cases three. Any measured-total/section-mass discrepancy and original excluded-hardware convention remain explicit in its notes. Reconcile those engineering inputs before using the landing-energy estimate as formal verification.

## Local access

The server binds only to `127.0.0.1`. Each launch creates a random access token, exchanges it for an HttpOnly/SameSite cookie, and removes it from the address bar. Only the dashboard assets and read-only results API are served; model files and `.git` are not exposed. There is no run-command endpoint, external asset/CDN dependency, or cross-origin API access.

This protects the local listener; it is not a GitHub membership authentication system. Repository access governs obtaining source and CI artifacts. A person who already has downloaded files retains that copy after repository access changes. For the optional local server, keep the repository private and do not forward the port or put it on a shared host. Pages has a separate public-access implication described in [Pages setup](PAGES.md). Stop the terminal with Ctrl+C when finished. Use `--port 8766` if the default port is occupied, or `--no-browser` to print the URL without opening it.

## Verification and troubleshooting

```sh
python -m unittest discover -s tests -v
node --check dashboard/app.js
```

In MATLAB or headless Octave, `addpath('matlab/app'); testSLVTRepository` exercises the numerical repository adapter. Native MATLAB also supports `testSLVTFlightApp(false)` and the desktop GUI smoke test `testSLVTFlightApp(true)`.

If the dashboard says **No results**, sync an artifact or run locally. If it says **Run failed**, inspect `results/<model>/run.log`. If inputs changed mid-run, rerun with files held steady. If GitHub rejects artifact access, check `gh auth status` and your repository permission. If an artifact has expired, manually run the workflow again. If a mission-limit check fails, inspect the failing case/section; changing workflow status does not fix the vehicle prediction.

Runtime references: [OpenRocket core](https://openrocket.readthedocs.io/en/latest/dev_guide/using_openrocket_core.html), [OpenRocket 24.12](https://github.com/openrocket/openrocket/releases/tag/release-24.12), [MathWorks setup action](https://github.com/matlab-actions/setup-matlab), [MathWorks command action](https://github.com/matlab-actions/run-command).
