# Wires telemetry keys from .env.local into flutter run/build/drive.
# Usage (PowerShell 5.1+):
#   scripts\run_with_telemetry.ps1 -Mode run
#   scripts\run_with_telemetry.ps1 -Mode release -Device <device-id>
#   scripts\run_with_telemetry.ps1 -Mode drive -Target integration_test\onboarding_consent_drive_test.dart -Device <device-id>
#
# Reads .env.local (gitignored) at the project root via Flutter's built-in
# --dart-define-from-file. Keys left blank stay inert: TelemetryService only
# initializes when a key is non-empty AND consent is granted.

param(
    [ValidateSet('run', 'profile', 'release', 'drive')]
    [string]$Mode = 'run',
    [string]$Device = '',
    [string]$Target = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root '.env.local'

if (-not (Test-Path $envFile)) {
    $example = Join-Path $root '.env.local.example'
    Write-Host "Missing $envFile." -ForegroundColor Yellow
    if (Test-Path $example) {
        Write-Host "Copy the example and fill in your keys (no secrets in git):" -ForegroundColor Yellow
        Write-Host "  Copy-Item .env.local.example .env.local" -ForegroundColor Yellow
    } else {
        Write-Host "Create .env.local with:" -ForegroundColor Yellow
    }
    Write-Host "  PLAYA_SENTRY_DSN=" -ForegroundColor Yellow
    Write-Host "  PLAYA_POSTHOG_KEY=" -ForegroundColor Yellow
    Write-Host "  PLAYA_POSTHOG_HOST=https://us.i.posthog.com" -ForegroundColor Yellow
    Write-Host "  PLAYA_TELEMETRY_DEBUG=" -ForegroundColor Yellow
    Write-Host "Keys are build-time only via --dart-define-from-file; TelemetryService stays inert until consent." -ForegroundColor DarkGray
    exit 1
}

Push-Location $root
try {
    $base = @('--dart-define-from-file=.env.local')
    $deviceArgs = @()
    if ($Device) { $deviceArgs = @('-d', $Device) }

    switch ($Mode) {
        'run' {
            & flutter run @base @deviceArgs
        }
        'profile' {
            & flutter run --profile @base @deviceArgs
        }
        'release' {
            & flutter run --release @base @deviceArgs
        }
        'drive' {
            if (-not $Target) {
                Write-Host 'drive mode requires -Target <integration_test/xxx_test.dart>' -ForegroundColor Yellow
                exit 1
            }
            & flutter drive --driver=test_driver/integration_test.dart --target=$Target @base @deviceArgs
        }
    }
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
    Pop-Location
}
