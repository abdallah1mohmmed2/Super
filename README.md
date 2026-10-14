# Store ERP

This repository keeps the original Flutter source archive and a clean GitHub Actions workflow for building the Windows desktop release.

## Build

1. Open the **Actions** tab.
2. Choose **Build Store ERP for Windows**.
3. Tap **Run workflow** (or push an update to the source ZIP/workflow).
4. When the run succeeds, download the **Store-ERP-Windows-Release** artifact.

The workflow expects `store-erp-upload.zip` in the repository root. The ZIP must contain a Flutter project with `pubspec.yaml`.
