$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Build = Join-Path $Root "build"
$Zip = Join-Path $Root "process-audio.zip"

if (Test-Path $Build) {
  Remove-Item -Recurse -Force $Build
}
if (Test-Path $Zip) {
  Remove-Item -Force $Zip
}

New-Item -ItemType Directory -Path $Build | Out-Null
Copy-Item (Join-Path $Root "lambda_function.py") (Join-Path $Build "lambda_function.py")

Compress-Archive -Path (Join-Path $Build "*") -DestinationPath $Zip -Force
Write-Host "Created $Zip"
