# NASA SLVT · Structures & Propulsion

Shared flight models, configuration, and mission-performance checks for Virginia Tech Student Launch. The MATLAB app runs independently; repository automation runs the committed models and packages a GitHub Pages dashboard.

## Open the dashboard on GitHub Pages

The dashboard is prepared for GitHub Pages. Once enabled, open the repository's **Deployments → github-pages → View deployment** link. No application installation or file download is needed. GitHub Actions runs the models and updates the static dashboard after relevant changes to `main`; the browser displays the published results.

**Publishing is currently disabled pending approval of public access.** This is a private repository owned by a personal GitHub account. Standard GitHub Pages publishes a public website even from a private repository; repository-only Pages access requires an eligible GitHub Enterprise Cloud organization. The repository itself remains private. A personal private repository also needs GitHub Pro to use Pages.

To enable after approving public dashboard access:

1. Open **Settings → Pages** and set **Source** to **GitHub Actions**.
2. Set `pages.enabled` to `true` in `config/automation.json` and commit it to `main`.
3. Wait for **Actions → Mission analysis → deploy** to finish. Its deployment URL is the dashboard link.

The site includes case/section results, requirement checks, model assumptions, runtime, analyzed commit, and timestamp. Source models, motor curves, raw input files, and execution logs are excluded from the Pages artifact. Published results and assumptions will nevertheless be visible to anyone who can access the site.

Failed mission limits still publish, so the dashboard does not silently retain an older passing result. Engine failures appear as incomplete/error states. The timestamp identifies the published analysis; a new push may still be running. See [Pages setup and access](docs/PAGES.md).

### Optional local dashboard

Local viewing remains available. Install Python 3.10+ and [GitHub CLI](https://cli.github.com/), sign in with `gh auth login`, then run from the repository root:

```sh
git pull
python scripts/sync_results.py
python scripts/serve_dashboard.py
```

This optional server binds to `127.0.0.1:8765` and uses a per-launch token. It is not needed to view the Pages deployment. Keep the terminal open while using it; Ctrl+C stops it.

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

The **Mission analysis** workflow runs on relevant pushes to `main`, pull requests, and manual **Actions → Mission analysis → Run workflow** requests. It validates inputs, tests the adapters, runs both models, and stores reports as the private `mission-analysis` artifact for 30 days. It also builds a `dashboard-site` artifact. When Pages is explicitly enabled, a separate job publishes that static dashboard from `main`, including runs with failed mission checks. Downloading the artifact requires repository access. `sync_results.py` gets the latest completed main-branch run, including one with failed mission checks.

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
