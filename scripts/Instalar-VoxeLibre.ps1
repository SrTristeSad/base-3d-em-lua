$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$GameRoot = Join-Path $ProjectRoot "games\voxelibre"
$Revision = "4492ce6ff8d856daa4567abe2ea689f4e7a39842"
if (Test-Path (Join-Path $GameRoot "game.conf")) {
    Write-Host "VoxeLibre ja existe em: $GameRoot"
    exit 0
}
$Temp = Join-Path ([System.IO.Path]::GetTempPath()) ("voxelibre-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $Temp | Out-Null
try {
    $ZipPath = Join-Path $Temp "voxelibre.zip"
    $Extract = Join-Path $Temp "unpack"
    $Uri = "https://github.com/VoxeLibre/VoxeLibre/archive/$Revision.zip"
    Write-Host "Baixando VoxeLibre completo (commit $Revision)..."
    Invoke-WebRequest -Uri $Uri -OutFile $ZipPath
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $Extract
    $Source = Get-ChildItem $Extract -Directory | Select-Object -First 1
    if (-not $Source -or -not (Test-Path (Join-Path $Source.FullName "game.conf"))) {
        throw "ZIP do VoxeLibre nao possui game.conf"
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $GameRoot) | Out-Null
    Move-Item -LiteralPath $Source.FullName -Destination $GameRoot
    Write-Host "VoxeLibre completo instalado em $GameRoot"
} finally {
    if (Test-Path $Temp) { Remove-Item -LiteralPath $Temp -Recurse -Force }
}
