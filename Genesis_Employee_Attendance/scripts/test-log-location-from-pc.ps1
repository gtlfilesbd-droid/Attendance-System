# Test that the backend accepts and saves a location (proves backend works).
# Run from Genesis_Employee_Attendance folder.
# Optional: pass your real coordinates so the map shows your location:
#   .\scripts\test-log-location-from-pc.ps1 -Latitude 23.8103 -Longitude 90.4125
param(
  [double]$Latitude = 23.8103,
  [double]$Longitude = 90.4125
)
$base = "http://localhost:8000"
$email = "ashraf.anam@gel.com.bd"
$password = "Open@4321"

Write-Host "=== 1. Login ==="
$body = @{ email = $email; password = $password } | ConvertTo-Json
$login = Invoke-RestMethod -Uri "$base/api/employees/auth/login/" -Method POST -ContentType "application/json" -Body $body
if (-not $login.success) { Write-Host "Login failed: $login"; exit 1 }
$token = $login.data.access
Write-Host "Token obtained."

Write-Host "=== 2. Send one location (lat=$Latitude, lng=$Longitude) ==="
$ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
$locBody = @{
  latitude = $Latitude
  longitude = $Longitude
  accuracy = 10.5
  battery_level = 85
  timestamp = $ts
} | ConvertTo-Json
$headers = @{ Authorization = "Bearer $token" }
try {
  $locResp = Invoke-RestMethod -Uri "$base/api/tracking/log-location/" -Method POST -ContentType "application/json" -Headers $headers -Body $locBody
  Write-Host "Response: $($locResp | ConvertTo-Json -Compress)"
  Write-Host "Now run: docker compose exec web python manage.py check_locations"
} catch {
  Write-Host "Error: $_"
  if ($_.Exception.Response) { Write-Host "Status: $($_.Exception.Response.StatusCode)" }
}
