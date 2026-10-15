# LA County Grade Watch

A phone-installable web app listing Los Angeles County restaurants and markets whose
health inspection grade changed, with the violations behind each change.

- `site/` – the app (`index.html`, install manifest, offline service worker, icons)
- `scripts/build-data.ps1` – downloads the County's inspection + violation CSVs and writes
  `site/data/changes.json` (~2 MB) with only the facilities whose grade changed
- `.github/workflows/deploy.yml` – builds the data and publishes `site/` to GitHub Pages
  on every push and every Monday, so new County data shows up automatically

Data: [LA County Open Data](https://data.lacounty.gov) – Environmental Health Restaurant and
Market Inspections and Violations (updated quarterly). Pasadena, Long Beach and Vernon are not included.

## Publish on GitHub Pages (one time)

1. On github.com click **New repository**. Name it `la-grade-watch`, choose **Public**,
   leave everything else unchecked, and click **Create repository**.
2. On the new empty repo page, click **uploading an existing file**. Drag in everything
   from this folder: `.github`, `scripts`, `site`, `.gitignore`, `README.md`, `serve.ps1`.
   Click **Commit changes**.
3. Go to **Settings → Pages**. Under *Build and deployment → Source*, choose **GitHub Actions**.
4. Go to the **Actions** tab, click **Build data and deploy**, then **Run workflow**.
   It takes about 5 minutes.
5. Your app is at `https://YOUR-USERNAME.github.io/la-grade-watch/`.

## Install on your phone

- **iPhone (Safari):** open the link, tap **Share**, then **Add to Home Screen**.
- **Android (Chrome):** open the link and tap **Install** in the banner (or ⋮ → **Install app**).

## Preview locally (Windows)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-data.ps1
powershell -ExecutionPolicy Bypass -File serve.ps1
```

Then open http://localhost:8765/.
