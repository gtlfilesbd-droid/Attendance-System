# Full backend check: restart web, wait, check_locations, test log-location from PC, check_locations again, summary.
# Run from Genesis_Employee_Attendance folder: .\scripts\full-check-backend.ps1
# Or from anywhere: & "E:\Attendance System\Genesis_Employee_Attendance\scripts\full-check-backend.ps1" (script will cd to project root)

$ErrorActionPreference = "Stop"
$scriptDir = $PSScriptRoot
$projectRoot = (Get-Item $scriptDir).Parent.FullName
Set-Location $projectRoot

Write-Host "=== Full backend check (Genesis_Employee_Attendance) ===" -ForegroundColor Cyan
Write-Host "Project root: $projectRoot"

Write-Host "`n--- 1. Restart web (docker compose up -d --build web) ---"
docker compose up -d --build web
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: docker compose up failed" -ForegroundColor Red
    exit 1
}

Write-Host "`n--- 2. Waiting 45 seconds for web to be ready ---"
Start-Sleep -Seconds 45

Write-Host "`n--- 3. check_locations (before test) ---"
$outBefore = docker compose exec -T web python manage.py check_locations 2>&1
$outBefore | ForEach-Object { Write-Host $_ }

Write-Host "`n--- 4. Test log-location from PC (login + POST one location) ---"
& "$scriptDir\test-log-location-from-pc.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: test-log-location-from-pc.ps1 failed (login or log-location)" -ForegroundColor Yellow
}

Write-Host "`n--- 5. check_locations (after test) ---"
$outAfter = docker compose exec -T web python manage.py check_locations 2>&1
$outAfter | ForEach-Object { Write-Host $_ }

# Parse "Today's location logs: N" from last run
$todayLogs = 0
foreach ($line in $outAfter) {
    if ($line -match "Today's location logs:\s*(\d+)") {
        $todayLogs = [int]$Matches[1]
        break
    }
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Backend OK; today's logs: $todayLogs"
if ($todayLogs -gt 0) {
    Write-Host "Dashboard Present Today should show >= 1 after you refresh the dashboard page." -ForegroundColor Green
} else {
    Write-Host "No locations today yet. If the app is logging, check baseUrl and backend logs." -ForegroundColor Yellow
}
