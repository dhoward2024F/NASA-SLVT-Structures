# SLVT MATLAB app + repository automation

This package updates the saved SLVT Flight App from October 10, 2026. It retains the existing deploy/retain flight engine, model editor, plots, tables, local settings, and CSV/MAT exports. A repository adapter adds reproducible JSON-driven runs and requirement reports.

## Start the standalone app

Extract this entire folder. In MATLAB, make this folder your Current Folder and run:

```matlab
app = startSLVT;
```

MATLAB R2021a or newer is required for the GUI; no additional toolboxes are required. Standalone means independent of GitHub and repository configuration, with MATLAB installed. This is not a compiled executable.

The app opens with your saved personal settings, or the original L2200G defaults if none exist. Edit variables and run simulations as before. Local settings continue saving in your MATLAB preferences folder. The `matlab/app/` directory is also independently usable: open that directory and run `app = SLVTFlightApp;`.

## Add to your GitHub repository

Copy `startSLVT.m`, `matlab/`, and `.github/workflows/matlab-analysis.yml` into the repository root. Keep your existing four JSON files in `config/` and add `config/matlab_model.json`. Matching copies of the four previously delivered JSONs are included for a new repository. Merge the included `.gitignore` entries into your existing file.

The new `matlab_model.json` holds the section masses, body Cd, propellant fallback, recovery timing, integration settings, and other inputs the four shared JSONs do not contain. It is essential to reproduce the MATLAB model. JSON values in `vehicle.json` and `launch_conditions.json` take precedence for shared inputs; null values use explicit, reported fallbacks from `matlab_model.json`.

### Resolve the motor and model choice once

The previously supplied `vehicle.json` specifies `vehicle/openrocket/motors/L1940X.eng`; that file was not supplied. The saved app includes `AeroTech_L2200G.csv`. The runner deliberately errors if the specified motor is absent.

Choose the model you intend to use:

- To publish the current app model, launch the app, review/edit its variables, then choose **Repository > Save model to repository...**. Select the repository root. This copies the selected motor and updates `vehicle.json`, the elevation/rail-length fields of `launch_conditions.json`, and `matlab_model.json`. It preserves the case definitions and requirements. Commit these changes with the app code.
- To use the L1940X configuration already in your JSONs, add its actual single-motor `.eng` file at the configured path and fill in/review the masses and MATLAB-specific settings. The importer supports two-column CSV and single-motor RASP `.eng` files. `.eng` thrust values are always interpreted as newtons.

The JSON example and original app also differ in fin height and main/payload parachute values. Loading repository inputs intentionally uses the JSON values; saving the app model intentionally replaces those shared values with the selected app settings. No silent motor or model substitution occurs.

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

## GitHub Actions

The included workflow runs integration tests and analyzes the versioned model on relevant pushes, pull requests, and manual dispatches. It uploads reports even when a requirement fails. It uses MATLAB R2024b and the MathWorks setup/run-command actions.

For a private repository, configure the `MLM_LICENSE_TOKEN` repository secret with a MathWorks batch licensing token, or adapt the workflow to an appropriately licensed self-hosted runner. Public repositories are automatically licensed for this base-MATLAB workflow by the MathWorks actions. See [Setup MATLAB](https://github.com/matlab-actions/setup-matlab) and [Run MATLAB Command](https://github.com/matlab-actions/run-command).

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

See `docs/VALIDATION.md` for tests actually executed for this delivery. The older documents in `matlab/app/` describe the original app; this README defines the repository additions.
