$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$modelName = 'gemma-4-E2B-it.litertlm'
$source = Join-Path $projectRoot "local_models/$modelName"
$assetDirectory = Join-Path $projectRoot 'android/app/src/main/assets'
$destination = Join-Path $assetDirectory $modelName
$expectedLength = 2588147712
$expectedHash = '181938105E0EEFD105961417E8DA75903EACDA102C4FCE9CE90F50B97139A63C'

if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "Falta $source"
}
if ((Get-Item -LiteralPath $source).Length -ne $expectedLength) {
    throw 'El archivo del modelo tiene un tamaño incorrecto.'
}
if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $expectedHash) {
    throw 'El archivo del modelo no coincide con el SHA-256 esperado.'
}
New-Item -ItemType Directory -Path $assetDirectory -Force | Out-Null
Copy-Item -LiteralPath $source -Destination $destination -Force
Write-Output "Modelo preparado para incluirse automáticamente en el APK: $destination"
