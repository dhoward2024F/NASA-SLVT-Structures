# SLVT MATLAB app + repository automation

This package updates the saved SLVT Flight App from October 10, 2026. It retains the existing deploy/retain flight engine, model editor, plots, tables, local settings, and CSV/MAT exports. A repository adapter adds reproducible JSON-driven runs and requirement reports.

## Start the standalone app

Extract this entire folder. In MATLAB, make this folder your Current Folder and run:

```matlab
app = startSLVT;
```

MATLAB R2021a or newer is required for the GUI; no additional toolboxes are required. Standalone means independent of GitHub and repository configuration, with MATLAB installed. This is not a compiled executable.

The app opens with your saved personal settings, or the original L2200G defaults if none exist. Edit variables and run simulations as before. Local settings continue saving in your MATLAB preferences folder. The `matlab/app/` directory is also independently usable: open that directory and run `app = SLVTFlightApp;`.

## Repository inputs

This app is already integrated into this repository. `config/matlab_model.json` holds section masses, body Cd, propellant fallback, recovery timing, integration settings, and inputs the shared JSONs do not contain. Shared values in `vehicle.json` and `launch_conditions.json` take precedence; null values use explicit, reported fallbacks.

The current configured motor is L2200G at `vehicle/openrocket/motors/AeroTech_L2200G.csv`. If you select another motor, commit the actual CSV or single-motor RASP `.eng` file and update the path. `.eng` thrust is interpreted as newtons. The runner fails if the selected file is missing.

GUI preferences and repository JSON values can differ. Loading repository inputs uses the JSON values; saving from the app intentionally updates shared values from the applied app settings. Review the model before saving. Case definitions and requirements are preserved.

## Use the Repository menu

- **Load model from repository...** loads model inputs. The ordinary Run simulations button still uses the visible GUI angle/wind/payload/recovery controls.
- **Save model to repository...** explicitly writes your current applied model settings and copies its motor. Apply any open editor changes first. It does not change `analysis_cases.json` or `requirements.json`.
- **Run repository cases...** reloads the committed/on-disk JSON inputs, runs exactly those cases, displays results in the app, and writes the machine-readable reports. Save your model first if you want recent editor changes included. This action does not overwrite personal app preferences.

Equivalent MATLAB calls:

```matlab
app.loadRepository(pwd);
app.saveRepository(pwd);
app.runRepository(pwd);
```

## Run without the interface

From the repository root:

```matlab
addpath('matlab');
report = run_ci(pwd, false);   % calculate and report, without failing on requirement limits
```

Or from a terminal in the repository root:

```sh
matlab -batch "addpath('matlab'); run_ci(pwd, true)"
```

`true` enables the requirement gate: the process fails after writing reports if any modeled check fails or is not evaluated. Numerical/configuration errors fail regardless of this setting. No GitHub service, UI, personal settings, or current-directory change is needed by the runner.

The standard JSON defines 60 cases. Enable `custom_condition` and provide its angle/wind pair to add six cases, for 66 total. The runner preserves the pair: it does not cross the new angle with every standard wind or vice versa. Identical vertical flights are cached because wind affects only drift in the inherited model (12 vertical simulations for the standard sweep, usually 18 with a new custom angle).

## Outputs

Each run writes these files to `results/matlab/`:

| File | Contents |
|---|---|
| `summary.json` | All cases, section results, requirement statuses, assumptions, and GitHub commit ID when available |
| `case_summary.csv` | One row per requested case |
| `sections.csv` | Section landing mass, speed, energy, drift, and descent time |
| `requirements.csv` | One row per requirement and applicable section/case |
| `resolved_model.json` | Exact effective MATLAB configuration |
| `inputs/` | Copies of the five source JSON files and motor curve |

These report filenames represent the latest run and are replaced by subsequent runs. GitHub retains each workflow's uploaded artifact separately. Headless mode does not export full histories by default. To retain them from a manual call:

```matlab
addpath('matlab/app');
[report, results] = slvtRunRepository(pwd);
save('results/matlab/full_results.mat', 'results', '-v7.3');
```

## GitHub Actions and dashboard

The combined `mission-analysis.yml` workflow runs this numerical source headlessly in GNU Octave, plus the selected OpenRocket ascent model, and stores results as a private artifact. Optional native MATLAB table/export tests run when `MLM_LICENSE_TOKEN` is configured. No MATLAB license secret is needed for the ordinary Octave analysis. See [automation instructions](../docs/AUTOMATION.md).

For dashboard use, prefer `python scripts/run_analysis.py` from the repository root over calling `run_ci` directly. The Python wrapper attaches the file fingerprints used to detect outdated results. The MATLAB app and direct `run_ci` interface remain independent of Python for their own runs/reports.

## Model interpretation

This is the existing staged vertical model, not a new 3D solver or OpenRocket integration. The adapter does not alter its equations or recovery schedules.

- Temperature, pressure, latitude, and longitude are recorded but not applied by the existing atmosphere model. Density uses site elevation and the selected standard/external atmosphere implementation.
- Wind affects descent drift only. Drift assumes constant wind from apogee and no lateral ascent displacement.
- Rail exit retains the original vertical-altitude threshold. Repository maximum Mach scans both complete vertical histories (including descent), using the configured constant sound speed; existing GUI tables retain their original ascent-based maximum-speed metric.
- Thrust-to-weight is burn-average thrust divided by liftoff weight. Confirm that convention when using the result for formal handbook verification.
- Each section's landing energy uses the same section-mass conventions as the existing app. Vehicle sections share the vehicle touchdown speed; the deployed payload uses its own touchdown speed. The original hardware-exclusion option and measured-total/section-mass discrepancy remain visible in notes.
- Descent time is vehicle apogee to each section's touchdown, including the payload. Every applicable section must pass its own check. Missing or unsupported metrics are `not_evaluated`, never a pass.

The seven bounds are exactly those supplied in the prior request. Report statuses assess this model and are labeled `model_estimate`; they are not certification of complete NASA compliance. JSON configuration does not launch OpenRocket or reconcile a CAD model.

## Validation

```matlab
addpath('matlab/app');
testSLVTRepository;        % JSON roundtrip, sweep, parity, reporting, error paths
testSLVTNumerics;          % original numerical regression checks
testSLVTFlightApp(false);  % original MATLAB tables/exports checks
testSLVTFlightApp(true);   % original GUI/settings smoke check on a desktop
```

See [the validation record](../docs/VALIDATION.md) for tests actually executed for this delivery. The older documents in `matlab/app/` describe the original app; this README defines the repository additions.
