# SLVT Flight and Recovery App

A programmatic MATLAB app based on David Howard's supplied 10/10/2026 deploy and retain flight scripts, derived from Benjamin Putka's dead-reckoning model. The interface is an editable MATLAB class (`SLVTFlightApp.m`). Requires MATLAB R2021a or later; no additional toolboxes.

## Start

1. Extract the ZIP and open the `SLVT_Flight_App` folder in MATLAB.
2. Keep the `.m` files and the included `AeroTech_L2200G.csv` in that folder.
3. Enter:

```matlab
app = SLVTFlightApp;
```

You can also enter `SLVTFlightApp` without assigning the output. The open window's callbacks keep the app alive.

## Workflow

- **Edit model variables...** opens a separate window with Masses, Drag and geometry, Recovery timing, Environment and numerics, and Motor CSV tabs. Edit only the Value cells. Browse for a motor curve and preview it before applying.
- **Apply and save** validates the settings and motor file, saves them, and closes the editor. Cancel discards the edits. Load original defaults changes the editor's draft until you apply it.
- Set the payload case (Deploy, Retain/abort, or both) and recovery (1, 2, 3, or all). Choose 5°/10° or one custom angle; choose 0/5/10/15/20 mph or one custom wind.
- **Use full sweep** selects 60 cases: 2 payload cases × 3 recoveries × 2 angles × 5 winds. There are 12 vertical calculations because wind affects only post-apogee drift.
- **Run simulations** computes the selected cases. Settings and run controls save after each successful batch. Cancel leaves the previous results available.
- Select a case in the dropdown or click a Case summary row. Flight tables show performance, individual section mass/impact energy, drogue tethered-group energy, drift, and event timing.
- Select multiple summary rows (Ctrl/Cmd-click or drag across cells), then choose **Compare selected summary rows**. Plots support altitude, velocity, acceleration, a three-axis flight profile, drift history, drift versus wind, and the motor curve. Duplicate wind cases share their vertical curve in overlays.
- **Open plot figure** gives you a normal MATLAB figure. **Save plot...** writes PNG, vector PDF, or `.fig`.
- **Export CSV + MAT...** creates a new timestamped folder containing the summary, per-flight tables, JSON model snapshot, and full results/trajectories in `SLVT_results.mat`. Check Include full histories in CSV if needed; it can produce large exports.
- **Send results to workspace** creates/replaces `SLVTResults`, `SLVTConfig`, and `SLVTSelected`. The last contains the selected case, flight, tables, and vehicle/payload history tables.

## Defaults and units

The included values reproduce the supplied scripts' input values. Masses are edited in **lbm**, then converted to slugs using `mass_lbm / g`. Altitudes/distances are ft, time is s, forces are lbf, energy is ft-lbf, and wind inputs are mph. Launch angle is **degrees from vertical**.

| Recovery | Drogue command after apogee | Main command altitude |
|---|---:|---:|
| 1 — Primary | 0 s | 625 ft AGL |
| 2 — Secondary | 1 s | 525 ft AGL |
| 3 — Tertiary | 2 s | 500 ft AGL |

Opening times are drogue 0.1 s, main 1.25 s, and payload 1 s. Payload release is at 300 ft AGL. Launch site elevation is 800 ft ASL.

The original total liftoff mass is 881 oz = 55.0625 lbm. Payload + forward + central + aft masses sum to 859.5 oz = 53.71875 lbm, leaving **1.34375 lbm unassigned**. The app keeps the independently specified total for dynamics and shows the difference. Unassigned mass is not added to a section KE because its location is unknown. Use sum of section masses for liftoff mass if the section values are your complete measured model.

The forward mass in the editor excludes the detachable payload/nosecone. The Retain case automatically combines these two masses, matching the original abort script's 261.5 oz forward mass.

Propellant is included in the aft section at liftoff. Drogue hardware is included in aft, main hardware in central, and payload hardware in payload. Do not add these masses to the section sum a second time.

## What stays the same, and what was corrected

The app preserves the original equations and modeling assumptions:

- `a = F/m`, `v = v0 + a*dt`, `h = h0 + (v+v0)*dt/2`.
- Fixed launch-angle projection of thrust and ascent drag; drag is calculated from vertical speed. Constant body Cd, gravity, sound speed, and propellant burn rate.
- Rail exit uses the original effective rail length as a vertical altitude threshold.
- Negligible body drag in descent, instantaneous full parachute drag after the opening event, and separate payload descent after release.
- The main opens at `mainCommandAlt - mainOpenTime * drogueTerminalEstimate`. It is an altitude-offset approximation, not a timed/inflating parachute model. The terminal estimate uses density at AGL altitude exactly as in the scripts; other drag forces use ASL altitude.
- Drift starts at zero at apogee and is `wind_ft_per_s * (time - apogee_time)`. The model does not predict ascent downrange displacement, wind-induced changes to the vertical trajectory, stability margin, attitude dynamics, or opening loads.
- **Exclude open recovery hardware from suspended mass** defaults on. This preserves the scripts' subtraction of parachute/recovery hardware from suspended section mass as each chute opens. Clear it to include attached hardware in the dynamics and section energy; this intentionally changes results.
- Reported maximum Mach uses vertical speed and the fixed configured sound speed. MaxNetG is net vertical acceleration divided by g, not a full structural load factor.

Corrections made in conversion:

1. The supplied motor CSV's metadata/header rows are safely skipped; columns become numeric vectors. The helper in the old scripts interpolated a full curve every step, offset it by the first timestamp, and could run beyond its last index. The app interpolates once at actual burn sample times, adding `(0, 0)` when the curve starts after zero.
2. Payload drift uses its independent touchdown time relative to the shared apogee. The old deploy script used `i` instead of `j` and included ascent time in the payload drift clock.
3. Apogee, rail exit, deployment crossings, and touchdown are located inside an integration step. The same constant-acceleration equation is used for these event crossings.
4. Traces grow as needed instead of stopping at a fixed 100000-sample allocation. There are input checks, cancellation, and a maximum-time guard.
5. Individual drogue section KE and combined tethered-group KE are separate tables. The old table repeated the entire forward tethered group's energy on each section row.
6. An internal 1976 standard lower-atmosphere density function removes the missing `atmos.m` dependency. It uses geopotential altitude, a troposphere lapse rate, and the 11–20 km isothermal layer. You can select External atmos.m and put your original helper on the MATLAB path if you want that density implementation.

Because the interpolation/indexing errors and event times were corrected, and the original `atmos.m` was not supplied, results are not expected to match the old scripts bit-for-bit. The model notes inside the app also explain these choices.

## Saved models and reproducibility

Personal settings are in:

```matlab
fullfile(prefdir, 'SLVTFlightApp', 'settings.json')
```

The app automatically restores that file on its next launch. Apply saves immediately, and successful runs save again. Each results structure stores a snapshot of its configuration, run selection, and motor samples; editing the model does not alter old results. Exports include that exact snapshot.

You can keep a separate settings profile for a model or vehicle:

```matlab
app = SLVTFlightApp(fullfile(pwd, 'Venture_settings.json'));
```

If you move a motor file, browse to its new location in the editor. The included motor is relocated automatically when its filename is found beside the app.

## Run without the GUI

```matlab
cfg = slvtDefaultConfig();
cfg.bodyCd = 0.52;
cfg.motorFile = fullfile(pwd, 'AeroTech_L2200G.csv');
selection = struct('Modes', {{'Deploy','Retain'}}, ...
    'Recoveries', 1:3, 'AnglesDeg', [5 10], 'WindsMph', 0:5:20);
results = slvtRunCases(cfg, selection);
disp(results.Summary)
slvtExportResults(results, pwd, false);
```

A single custom case:

```matlab
selection = struct('Modes', {{'Retain'}}, ...
    'Recoveries', 2, 'AnglesDeg', 7.5, 'WindsMph', 12.3);
results = slvtRunCases(cfg, selection);
```

Engine-only access:

```matlab
motor = slvtReadMotor(cfg.motorFile, cfg.motorThrustUnit);
flight = slvtSimulate(cfg, motor, 'Deploy', 1, 5);
tables = slvtBuildTables(flight, cfg, [0 5 10 15 20]);
history = slvtTraceTable(flight.Vehicle, flight.Metrics.TimeToApogeeS, 10);
```

Trace columns are time, altitude, vertical velocity, acceleration, suspended mass in lbm, and phase code. An empty Payload trace and NaN payload metrics mean not applicable for Retain. Descent and impact speeds shown in tables are positive magnitudes; velocity histories are signed.

## Checks

Run the supplied MATLAB checks from the app folder:

```matlab
testSLVTNumerics         % engine checks, also usable in GNU Octave
testSLVTFlightApp(false)  % numerical, case tables, custom cases, invalid inputs, exports
testSLVTFlightApp(true)   % also creates the UI, opens/applies the model editor, restores settings
```

The GUI requires MATLAB and is not supported by GNU Octave. See `VALIDATION.md` for checks performed during delivery.

## Files

`SLVTFlightApp.m` owns the interface and settings; `slvtSimulate.m` is the stage engine; `slvtRunCases.m` builds the case matrix without repeating wind-independent dynamics. Other helpers handle defaults, validation, density, motor import, tables, plotting, and export. The old scripts and `plotORdata.m` are no longer dependencies.

MathWorks references: [programmatic apps](https://www.mathworks.com/help/matlab/creating_guis/create-and-run-a-simple-programmatic-app.html), [grid layouts](https://www.mathworks.com/help/matlab/ref/uigridlayout.html), [UI tables](https://www.mathworks.com/help/matlab/ref/uitable.html), and [plot export](https://www.mathworks.com/help/matlab/ref/exportgraphics.html).

Atmosphere reference: [U.S. Standard Atmosphere, 1976, NASA-TM-X-74335](https://ntrs.nasa.gov/api/citations/19770009539/downloads/19770009539.pdf).
