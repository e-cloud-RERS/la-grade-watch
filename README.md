# LA County Grade Watch

A phone-installable web app listing Los Angeles County restaurants and markets whose
health inspection grade changed, with the violations behind each change.

Features: grade-change list with search and filters (city, cuisine guessed from the name,
direction, new grade, dates), inspection reports with every past inspection, a watch list
with grade-change alerts, a Near me tab (list or map), and shareable links to any restaurant.

- `site/` – the app (`index.html`, install manifest, offline service worker, icons)
- `scripts/build-data.ps1` – downloads the County's inspection, violation and facility-location
  data and writes `site/data/changes.json` (~2 MB, facilities whose grade changed, with violations)
  and `site/data/facilities.json` (~6 MB, every graded facility's grade history, used by the watch list)
- `.github/workflows/deploy.yml` – builds the data and publishes `site/` to GitHub Pages
  on every push and every Monday, so new County data shows up automatically

Data: [LA County Open Data](https://data.lacounty.gov) – Environmental Health Restaurant and
Market Inspections, Violations and Inventory (updated quarterly). Pasadena, Long Beach and Vernon
are not included. Map tiles © OpenStreetMap contributors.

## Publish on GitHub Pages (one time)

1. On github.com click **New repository**. Name it `la-grade-watch`, choose **Public**,
   leave everything else unchecked, and click **Create repository**.
2. On the new empty repo page, click **uploading an existing file**. Drag in `scripts`, `site`,
   `README.md` and `serve.ps1`, then click **Commit changes**.
3. GitHub's uploader skips the `.github` folder, so create the workflow by hand:
   **Add file → Create new file**, name it `.github/workflows/deploy.yml`, paste in the contents
   of that file from this folder, and commit.
4. Go to **Settings → Pages**. Under *Build and deployment → Source*, choose **GitHub Actions**.
5. Go to the **Actions** tab, click **Build data and deploy**, then **Run workflow**.
   It takes about 5 minutes.
6. Your app is at `https://YOUR-USERNAME.github.io/la-grade-watch/`.

To update the app later, upload changed files into the same folders (dragging the whole `site`
folder is easiest); GitHub republishes automatically.

## Install on your phone

- **iPhone (Safari):** open the link, tap **Share**, then **Add to Home Screen**.
- **Android (Chrome):** open the link and tap **Install** in the banner (or ⋮ → **Install app**).

## Preview locally (Windows)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-data.ps1
powershell -ExecutionPolicy Bypass -File serve.ps1
```

Then open http://localhost:8765/.
