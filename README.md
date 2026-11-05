# NASA SLVT · Structures & Propulsion

Shared flight models, configuration, and mission-performance checks for Virginia Tech Student Launch. The MATLAB app runs independently; repository automation runs the committed models and supplies a local dashboard.

## Open the dashboard

Install Python 3.10+ and [GitHub CLI](https://cli.github.com/), then sign in once with `gh auth login` using an account with access to this private repository. In your local repository folder:

```sh
git pull
python scripts/sync_results.py
python scripts/serve_dashboard.py
```

The last command opens the dashboard on **your computer**, at `127.0.0.1:8765`, with a per-launch access token. Keep that terminal running; press Ctrl+C to stop it. If the browser does not open, use the complete URL printed in the terminal. On systems where Python is named `python3`, use that instead.

The dashboard provides model comparisons, filters for all cases, individual section landing results, CSV export, requirement traceability, model assumptions, and result freshness checks. No Node installation or web build is needed to view it.

GitHub controls access to the private source and result artifacts. The dashboard has no public hosting or GitHub Pages deployment. Local hosting does not recheck GitHub membership: anyone who already possesses a copy of the files can read that copy. Do not expose the local port through a tunnel or reverse proxy.

## Run the models locally

Install Java 17 and either MATLAB or GNU Octave, then run:

```sh
python -m pip install -r requirements-automation.txt
python scripts/run_analysis.py
python scripts/serve_dashboard.py
```

The runner prefers MATLAB when installed and otherwise uses Octave for the same numerical `.m` source. To choose explicitly, use `--runtime matlab` or `--runtime octave`; `--executable` accepts a path to that runtime. OpenRocket 24.12 is downloaded from its official release and checked against a pinned SHA-256 digest. The first run needs internet access.

To open the standalone MATLAB interface, run these commands in MATLAB from the repository root:

```matlab
addpath('matlab');
app = startSLVT;
```

Use the app's **Repository** menu to load/save shared model settings or run the JSON cases. Ordinary GUI runs remain independent and use your personal saved settings. See [MATLAB instructions](matlab/README.md).

## Automatic analysis

The **Mission analysis** workflow runs on relevant pushes to `main`, pull requests, and manual **Actions → Mission analysis → Run workflow** requests. It validates inputs, tests the adapters, runs both models, and stores reports as the private `mission-analysis` artifact for 30 days. Downloading the artifact requires repository access. `sync_results.py` gets the latest completed main-branch run, including one with failed mission checks.

CI uses GNU Octave for the MATLAB numerical source so the private repository does not require a MATLAB license secret for ordinary analysis. Native MATLAB table/export validation also runs if the repository has an `MLM_LICENSE_TOKEN` secret. The desktop GUI itself requires MATLAB.

**A red mission-limit check can mean a valid simulation predicts a requirement violation.** Reports are uploaded before that check. Missing, errored, incomplete, or outdated results never count as a pass.

## Cases and model coverage

The standard matrix is 5°/10° from vertical × 0/5/10/15/20 mph × deploy/retain × primary/secondary/tertiary: **60 cases**. Enabling the custom angle/wind pair in `config/analysis_cases.json` adds six cases.

| Model | Automated coverage |
|---|---|
| MATLAB source | Every payload/recovery case; all seven configured requirements, including each applicable landing section |
| OpenRocket | Fresh 3D ascent reference for each wind/angle pair; apogee, rail exit velocity, and ascent Mach. Shared across the payload/recovery labels; separate payload/recovery behavior is not modeled by this adapter |

The selected full-scale `.ork` is configured in `config/automation.json`. OpenRocket uses its own stored geometry, mass, motor, and recovery definitions; MATLAB uses the JSON configuration. The dashboard compares them without claiming the two models are identical. Neither CAD files nor models are silently rewritten.

See [automation setup and interpretation](docs/AUTOMATION.md), [configuration details](config/README.md), and [validation record](docs/VALIDATION.md).
