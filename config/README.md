# SLVT repository configuration

Copy the config/ folder into the repository root.

- vehicle.json preserves the previously proposed vehicle fields and values.
- launch_conditions.json preserves the previous defaults, with wind direction and launch azimuth removed.
- requirements.json encodes the seven handbook requirements supplied by the team. It is not a complete handbook compliance checklist or an independent handbook verification.
- analysis_cases.json lists all 60 standard simulations explicitly using the previously proposed case field names.

## Simulation cases

The standard cases are the full product of:
- Launch angles from vertical: 5 and 10 degrees.
- Wind speeds: 0, 5, 10, 15, and 20 mph.
- Payload cases: deploy and retain (the app's abort/retain case).
- Recovery configurations: primary=1, secondary=2, tertiary=3 in the MATLAB model.

Each case overrides only the wind speed and launch angle in launch_conditions.json. Other launch settings remain the shared defaults.

To add a custom condition, edit custom_condition at the bottom of analysis_cases.json:
1. Set wind_speed_mph and launch_angle_from_vertical_deg to your desired numbers.
2. Set enabled to true.
3. The runner must expand that one pair across both payload cases and all three recovery configurations (six additional runs, for 66 total).

The disabled custom condition uses null inputs to avoid assuming a desired custom condition. When disabled, skip it. When enabled, require finite numeric inputs, a nonnegative wind speed, and an angle from vertical in the range 0 <= angle < 90 degrees. This is input validation, not a declaration that every such angle is permitted for launch.

## Inputs and model integration

Fill in the existing null vehicle masses, launch-site coordinates/elevation, and rail length before running a model that requires them. Keep the existing motor path consistent with the actual repository file. The three named recovery configurations select the model's existing configurations; their physical definitions remain in the model.

These are configuration data. The Python/MATLAB runners must read these fields, apply the overrides, expand custom_condition when enabled, and export matching result metrics. These files do not themselves execute simulations, change the standalone MATLAB app, or establish that the current app already supports JSON loading.

## Requirements evaluation

All supplied bounds are inclusive: apogee 4000-6000 ft AGL, thrust-to-weight ratio >=5, rail exit velocity >=52 ft/s, maximum Mach <=1, landing kinetic energy <=75 ft-lbf per section, landing drift radius <=2500 ft, and descent time <=100 s.

Check every case separately. For section-scoped checks, retain a result for each independently landing section; every applicable section must pass. Do not add separate-section landing energies together. A missing or unsupported result is not_evaluated, never a pass.

Use the maximum Mach number over the full flight, the horizontal distance from the pad at each section's touchdown, and the elapsed time from vehicle apogee to each section's touchdown. The last touchdown therefore controls the overall descent-time check, including a payload deployed after apogee.

The metric thrust_to_weight_ratio must be supplied by a consistently defined propulsion/model calculation. Do not use the minimum of thrust/weight over the entire flight, which would be zero during coast. This configuration does not impose an average-versus-initial-thrust convention absent from the supplied requirement summary.

For landing kinetic energy in imperial units, use mass in slugs and impact speed in ft/s: KE = 0.5 * mass_slug * speed_fps^2. Convert lbm to slugs using 32.174 lbm/slug. Ensure the model supplies the appropriate impact speed for the handbook check.
