# Delivery verification

The actual MATLAB numerical source was executed using GNU Octave 8.4.0. The engine, density, motor import, and configuration validation have no MATLAB-only UI or table dependencies.

- All 12 deploy/retain × recovery 1/2/3 × 5°/10° vertical flights passed at dt = 0.005 s.
- Checks covered positive ordered timestamps, finite states, exact touchdown altitude, common ascent solutions, Newton acceleration, free-fall acceleration, recovery mass changes, payload/vehicle continuity at separation, payload opening delay, and main full-open altitude.
- A Deploy / recovery 1 / 5° run at the app's default dt = 0.001 s passed. Its apogee differed from the 0.005 s run by 0.8974 ft; vehicle and payload impact speeds differed by less than 0.05 ft/s.
- Custom 7.5° angle, attached-hardware option, invalid mass rejection, cancellation, and invalid recovery schedule checks passed.
- All delivered MATLAB files passed MATLAB grammar parsing with tree-sitter-matlab.
- The delivered motor CSV matches the supplied file byte-for-byte.

MATLAB was not installed in the build environment. The UI, MATLAB tables, settings persistence callbacks, plot export, and MAT/CSV export were reviewed and syntax-checked, but were not executed in native MATLAB. The provided `testSLVTFlightApp(false)` checks tables and exports; `testSLVTFlightApp(true)` additionally opens/applies the editor and tests settings restoration. External atmos.m was not supplied and that optional provider was not executed.

`validated_reference_dt_0p005.csv` contains the 12 numerical reference rows from this check. Its time step is intentionally marked; the app defaults to 0.001 s. The wind formula and table/export integrations have dedicated MATLAB checks in `testSLVTFlightApp.m`.

The conversion fixes original CSV/interpolation and payload drift bugs. Its results are not a bit-for-bit reproduction of those bugs or of an unspecified original atmosphere function.

## Numerical check output

```text
PASS Deploy R1 5 deg | apogee 4568.43 ft | impact 9.098 ft/s
PASS Deploy R1 10 deg | apogee 4506.50 ft | impact 9.098 ft/s
PASS Deploy R2 5 deg | apogee 4568.43 ft | impact 9.098 ft/s
PASS Deploy R2 10 deg | apogee 4506.50 ft | impact 9.098 ft/s
PASS Deploy R3 5 deg | apogee 4568.43 ft | impact 9.098 ft/s
PASS Deploy R3 10 deg | apogee 4506.50 ft | impact 9.098 ft/s
PASS Retain R1 5 deg | apogee 4568.43 ft | impact 10.598 ft/s
PASS Retain R1 10 deg | apogee 4506.50 ft | impact 10.598 ft/s
PASS Retain R2 5 deg | apogee 4568.43 ft | impact 10.598 ft/s
PASS Retain R2 10 deg | apogee 4506.50 ft | impact 10.598 ft/s
PASS Retain R3 5 deg | apogee 4568.43 ft | impact 10.598 ft/s
PASS Retain R3 10 deg | apogee 4506.50 ft | impact 10.598 ft/s
PASS dt convergence | apogee difference 0.8974 ft | vehicle impact difference 0.000000 ft/s
PASS custom angle, hardware option, mass checks, cancellation, and invalid schedule
All SLVT engine checks passed. GUI/table/export checks require MATLAB.
```
