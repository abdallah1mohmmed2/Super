# Store ERP — Windows build

The GitHub Actions workflow is at `.github/workflows/build-windows.yml`.

## Build from an Android phone

1. Open the repository: https://github.com/abdallah1mohmmed2/Super
2. Open the **Actions** tab.
3. Select **Build Store ERP for Windows**.
4. Tap **Run workflow**, select branch `main`, then tap **Run workflow** again.
5. Open the new run and wait for it to finish.
6. If it succeeds, scroll to **Artifacts** and download **Store-ERP-Windows-Release**.
7. Extract the downloaded ZIP on a Windows computer. The folder should contain the app executable and its runtime files; keep them together.

## Important

- The workflow expects `store-erp-upload.zip` in the repository root.
- The archive must contain a Flutter project with `pubspec.yaml`.
- The first build can take several minutes.
- A successful workflow confirms that the Windows release build completed. The app should still be tested on a Windows computer before real business use.
