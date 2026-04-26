$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Build = Join-Path $Root "build"
$Zip = Join-Path $Root "process-image.zip"

if (Test-Path $Build) {
  Remove-Item -Recurse -Force $Build
}
if (Test-Path $Zip) {
  Remove-Item -Force $Zip
}

New-Item -ItemType Directory -Path $Build | Out-Null
Copy-Item (Join-Path $Root "index.mjs") (Join-Path $Build "index.mjs")
Copy-Item (Join-Path $Root "package.json") (Join-Path $Build "package.json")

Push-Location $Build
try {
  npm install --omit=dev --os=linux --cpu=x64 --libc=glibc
} finally {
  Pop-Location
}

Compress-Archive -Path (Join-Path $Build "*") -DestinationPath $Zip -Force
Write-Host "Created $Zip"
