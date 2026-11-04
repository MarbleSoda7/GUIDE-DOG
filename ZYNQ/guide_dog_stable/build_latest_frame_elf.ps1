param([string]$OutPath = '')
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$gcc = 'D:\Software\AMDDesignTools\2026.1\gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-gcc.exe'
$bsp = Join-Path $root 'bsp/export/sw/standalone_ps7_cortexa9_0'
$camera = Join-Path $root 'led_src'
$ld = Join-Path $root 'led_src/lscript.ld'
$out = if ($OutPath) { [IO.Path]::GetFullPath($OutPath) } else { Join-Path $root 'test_artifacts/stage5_latest_frame_pl_owner.elf' }
$sources = @(
    (Join-Path $root 'sw/stage5_latest_frame_main.c'),
    (Join-Path $camera 'sccb/sccb_init.c'),
    (Join-Path $camera 'ov5640/ov5640_init.c'),
    (Join-Path $root 'led_src/vdma_api/vdma_api.c')
)
$incs = @("-I$bsp/include", "-I$camera/sccb", "-I$camera/ov5640", "-I$camera/vdma_api")
foreach ($path in @($gcc,$bsp,$ld) + $sources) {
    if (-not (Test-Path -LiteralPath $path)) { throw "LATEST_ELF_MISSING=$path" }
}
$objects = @()
foreach ($source in $sources) {
    $object = Join-Path $env:TEMP ('latest_' + [IO.Path]::GetFileNameWithoutExtension($source) + '.o')
    & $gcc '-DSDT' '-mcpu=cortex-a9' '-mfpu=vfpv3' '-mfloat-abi=hard' '-O2' '-Wall' '-Wextra' '-ffunction-sections' '-fdata-sections' '-c' @incs $source '-o' $object
    if ($LASTEXITCODE -ne 0) { throw "LATEST_ELF_COMPILE_FAILED=$source" }
    $objects += $object
}
& $gcc '-mcpu=cortex-a9' '-mfpu=vfpv3' '-mfloat-abi=hard' '-Wl,-build-id=none' "-specs=$bsp/Xilinx.spec" '-Wl,-T' "-Wl,$ld" "-L$bsp/lib" '-Wl,--gc-sections' '-o' $out @objects '-Wl,--start-group' '-lxilstandalone' '-lxiltimer' '-lxil' '-lgcc' '-lc' '-Wl,--end-group'
if ($LASTEXITCODE -ne 0) { throw "LATEST_ELF_LINK_FAILED=$LASTEXITCODE" }
Write-Host "LATEST_ELF=$out"
Write-Host "LATEST_ELF_SHA256=$((Get-FileHash -LiteralPath $out -Algorithm SHA256).Hash)"
