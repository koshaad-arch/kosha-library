# Kosha's Library — one-time setup on Windows.
# Run from inside this folder:   powershell -ExecutionPolicy Bypass -File .\setup.ps1
$ErrorActionPreference = "Stop"

Write-Host "Generating Android platform files..."
# Creates any missing platform files; our lib/, pubspec.yaml and manifest are kept.
flutter create --org com.koshagandhi --project-name kosha_library --platforms android .

# flutter create may overwrite the manifest, so restore ours (camera + internet permissions)
Copy-Item -Force .\setup_files\AndroidManifest.xml .\android\app\src\main\AndroidManifest.xml

# The barcode scanner needs Android 6.0 (API 23) or newer
$gradle = if (Test-Path .\android\app\build.gradle.kts) { ".\android\app\build.gradle.kts" } else { ".\android\app\build.gradle" }
(Get-Content $gradle) -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 23' `
                      -replace 'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 23' | Set-Content $gradle

# Remove the sample test that flutter create adds (it refers to a counter app)
if (Test-Path .\test\widget_test.dart) { Remove-Item .\test\widget_test.dart }

flutter pub get
Write-Host ""
Write-Host "Done. Plug in your phone (USB debugging on) and run:  flutter run"
Write-Host "Or build an installable APK with:                     flutter build apk --release"
