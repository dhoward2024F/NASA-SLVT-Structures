# GitHub Pages dashboard

The dashboard can be a static website hosted by GitHub. GitHub Actions performs simulations, builds `data.json`, packages the dashboard, and deploys it. Viewers need only a browser. The source repository and full diagnostic artifacts remain private.

## Access decision before enabling

For this personal-account private repository, GitHub Pages serves a **public website**. A private repository does not make its Pages site private. Restricting Pages to repository readers requires a private/internal project repository in an eligible GitHub Enterprise Cloud organization. A personal-account private repository requires GitHub Pro for Pages availability.

`config/automation.json` has Pages enabled by the repository owner. This does not change repository visibility or permissions. Setting `pages.enabled` to false stops future custom-workflow deployments.

The prepared site exposes model performance, section landing masses/speeds/energy/drift/time, requirement statuses, model assumptions, runtime, commit SHA, and timestamp. It excludes model source files, CAD, motor curves, raw JSON configuration files, trajectories, full source-file manifests, and private execution logs. The published result data itself is downloadable by site visitors. The interface is read-only and has no embedded GitHub token, browser sign-in workaround, or simulation execution endpoint.

References: [GitHub Pages publishing and public visibility](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site), [private Pages access requirements](https://docs.github.com/en/enterprise-cloud@latest/pages/getting-started-with-github-pages/changing-the-visibility-of-your-github-pages-site).

## Enable after approving public access

1. In the repository, open **Settings → Pages**. Under **Build and deployment**, set **Source** to **GitHub Actions**. If Pages is unavailable for this private repository, the account needs a supported plan; do not make the repository public merely to bypass that restriction.
2. Set `pages.enabled` to `true` in `config/automation.json`, preserving the other settings, and commit to `main`.
3. Open **Actions → Mission analysis**. The analysis job tests and runs the models, uploads the complete private reports, and packages the site. The **deploy** job publishes the Pages artifact.
4. Open the deployment URL from **deploy → Deploy dashboard** or **Deployments → github-pages → View deployment**. Bookmark that link; downloads and a local server are unnecessary.

The deployment job uses `actions/configure-pages`, `actions/upload-pages-artifact`, and `actions/deploy-pages`. Only this job receives Pages deployment permission. No Pages deployment runs on a pull request, and no repository source is copied wholesale into the site artifact.

When the workflow creates a `github-pages` environment, retain a deployment branch rule that allows only `main`. GitHub's repository Pages source must be configured before the deployment job can succeed; the workflow does not silently enable Pages.

## Updates and failed checks

Relevant pushes to `main` rerun analysis and publish a new snapshot when enabled. Manual **Actions → Mission analysis → Run workflow** also works. The browser refreshes the published JSON periodically, but that does not start simulations.

The separate **Vehicle requirement checks** job may be red because the vehicle prediction violates a configured limit. The independent `deploy` job still publishes those results. If an engine fails, the published dashboard marks the result incomplete or failed rather than treating missing metrics as passes. The existing 30 payload/nosecone energy failures are preserved.

The dashboard's commit and timestamp identify the snapshot. A newer commit may still be running or may have failed before producing a package. The website cannot check someone else's uncommitted model changes. Use its **View analysis run** link when checking freshness.

## Review the prepared site without publishing

Every analysis run keeps `dashboard-site` as a private artifact, even while Pages is disabled. Locally, `python scripts/build_pages.py` produces `_site/` with exactly these files:

- `index.html`
- `app.js`
- `styles.css`
- `data.json`
- `.nojekyll`

The directory is ignored by Git. The optional localhost dashboard continues to work with `python scripts/serve_dashboard.py`.

## Stop future publication

Set `pages.enabled` to `false` to stop future deployments. This does **not** remove an already published site; use **Settings → Pages → Unpublish site** to take the existing site offline. Publicly downloaded copies cannot be revoked by unpublishing.


## Avoid competing Pages workflows

Set **Settings → Pages → Build and deployment → Source** to **GitHub Actions**. A branch-based source starts GitHub's separate Jekyll build and can collide with this repository's custom dashboard deployment. The custom deployment packages only `_site/`; a branch-based build uses a different source.

Deployment waits for successful simulations. A test or engine failure prevents publication; failed vehicle limits remain visible in a separate requirement-check job and do not block publication. Deployment jobs use the `github-pages` concurrency group.
