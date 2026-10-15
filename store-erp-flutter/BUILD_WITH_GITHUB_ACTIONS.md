# Build Store ERP for Windows using GitHub Actions

This repository includes `.github/workflows/build-windows.yml` to build the Windows desktop app on a GitHub-hosted Windows runner.

## What triggers a build?
- Push to `main` or `master`.
- Manual run from the repository's **Actions** tab using **Build Store ERP for Windows** → **Run workflow**.

## Download the result on Android
1. Open your repository in a browser and sign in to GitHub.
2. Open the **Actions** tab.
3. Select **Build Store ERP for Windows**.
4. Open the latest run and wait for it to finish.
5. Under **Artifacts**, tap `Store-ERP-Windows-x64` to download the ZIP.
6. Extract the ZIP on a Windows computer and run `store_erp_flutter.exe`.

The ZIP contains the executable and its accompanying runtime files. Do not copy the EXE alone; keep the extracted files together.

## Important
- The first run generates the Windows runner files if they are not present in the repository.
- This workflow creates a Windows x64 release artifact. It does not publish a GitHub Release.
- A successful workflow is required before the executable can be considered built. If the run fails, open the failed step's logs and fix the reported error.
