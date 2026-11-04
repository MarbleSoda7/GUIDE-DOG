[CmdletBinding()]
param(
  [switch]$Build,
  [switch]$Force
)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path $PSScriptRoot).Path
$Copy = Join-Path $Root 'zynq_project/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy'
$HlsTcl = Join-Path $Copy 'run_pl_remap_hls.tcl'
$IntegrateTcl = Join-Path $Copy 'integrate_pl_remap.tcl'
$Check = Join-Path $Root 'tools/build_pl_rectify.py'
$ManifestTool = Join-Path $Root 'tools/build_pl_manifest.py'
$Artifacts = Join-Path $Root 'artifacts/pl_rectify'

function Invoke-Checked([string]$File, [string[]]$ArgumentList, [hashtable]$Env = @{}) {
  $old = @{}
  foreach ($k in $Env.Keys) { $old[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, [string]$Env[$k], 'Process') }
  try {
    Push-Location $Copy
    try { & $File @ArgumentList } finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { throw "$File failed with exit code $LASTEXITCODE" }
  } finally {
    foreach ($k in $Env.Keys) { [Environment]::SetEnvironmentVariable($k, $old[$k], 'Process') }
  }
}

if (-not (Test-Path -LiteralPath $Check)) { throw "Missing static checker: $Check" }
$py = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
if ($null -eq $py) { throw 'Python is required for the short preflight' }
Invoke-Checked -File $py.Source -ArgumentList @($Check)
if (-not $Build) {
  Write-Host 'PRECHECK ONLY: no HLS/Vivado/synth/impl/SD action was requested.'
  exit 0
}
if (-not $Force) {
  throw 'Build is destructive/long-running; rerun explicitly with -Build -Force after reviewing the copied project.'
}
$hls = Get-Command vitis_hls -ErrorAction SilentlyContinue
if ($null -eq $hls) { throw 'vitis_hls is not on PATH; no build was started' }
$vivado = Get-Command vivado -ErrorAction SilentlyContinue
if ($null -eq $vivado) { throw 'vivado is not on PATH; no build was started' }
if (-not (Test-Path -LiteralPath $HlsTcl)) { throw "Missing HLS script: $HlsTcl" }
if (-not (Test-Path -LiteralPath $IntegrateTcl)) { throw "Missing integration script: $IntegrateTcl" }
New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null
$BuildOutput = Join-Path $Copy 'build_output'
$Canonical = @('led_test_wrapper.bit','led_test_wrapper.hwh','led_test_wrapper.xsa')
foreach ($name in $Canonical) {
  $dest = Join-Path $Artifacts $name
  if (Test-Path -LiteralPath $dest) { throw "Refusing to overwrite existing artifact: $dest" }
}
$KernelHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Copy 'pl_remap_accel.cpp')).Hash
Invoke-Checked -File $hls.Source -ArgumentList @('-f', $HlsTcl) -Env @{ PL_RECTIFY_BUILD = '1' }
Invoke-Checked -File $vivado.Source -ArgumentList @('-mode','batch','-source',$IntegrateTcl) -Env @{ PL_RECTIFY_BUILD = '1' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Copy 'pl_remap_accel.cpp')).Hash -ne $KernelHash) { throw 'Kernel source changed during HLS build' }
$Inputs = Join-Path $Artifacts 'source_inputs.json'
Invoke-Checked -File $py.Source -ArgumentList @($ManifestTool, '--snapshot', $Inputs)
# The only allowed full flow is this explicit -Build path.
Invoke-Checked -File $vivado.Source -ArgumentList @('-mode','batch','-source',(Join-Path $Root 'tools/launch_pl_rectify_build.tcl')) -Env @{ PL_RECTIFY_BUILD = '1' }
$manifest = [ordered]@{ schema = 1; generated_utc = [DateTime]::UtcNow.ToString('o'); project = $Copy; files = @{} }
foreach ($name in $Canonical) {
  $source = Join-Path $BuildOutput $name
  if (-not (Test-Path -LiteralPath $source)) { throw "Build completed without canonical artifact: $source" }
  $dest = Join-Path $Artifacts $name
  Copy-Item -LiteralPath $source -Destination $dest
  $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $dest).Hash.ToLowerInvariant()
  $manifest.files[$name] = [ordered]@{ source = $source; sha256 = $hash; length = (Get-Item -LiteralPath $dest).Length }
}
Invoke-Checked -File $py.Source -ArgumentList @($ManifestTool, '--seal', $Artifacts, '--inputs', $Inputs)
Write-Host "BUILD_ARTIFACTS=$Artifacts"
