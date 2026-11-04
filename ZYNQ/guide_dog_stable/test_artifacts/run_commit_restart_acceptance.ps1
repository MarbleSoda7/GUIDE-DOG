$ErrorActionPreference = 'Stop'
$buildId = '20261001T084500Z_commit_restart_v1'
$base = Split-Path $PSScriptRoot -Parent
$build = Join-Path $PSScriptRoot $buildId
$manifest = Get-Content (Join-Path $build 'build_manifest.json') -Raw | ConvertFrom-Json
foreach ($item in $manifest.inputs + $manifest.artifacts) {
    $hash = (Get-FileHash -LiteralPath $item.path -Algorithm SHA256).Hash
    if ($hash -ne $item.sha256) { throw "COMMIT_RESTART_STALE=$($item.path)" }
    Write-Host "COMMIT_RESTART_SHA256=$hash PATH=$($item.path)"
}
$snapshot = Get-Content (Join-Path $build 'source_snapshot.json') -Raw | ConvertFrom-Json
foreach ($item in $snapshot.files) {
    if ((Get-FileHash -LiteralPath $item.path -Algorithm SHA256).Hash -ne $item.sha256) {
        throw "COMMIT_RESTART_SOURCE_CHANGED=$($item.path)"
    }
}
$out = Join-Path $build ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '_board')
New-Item -ItemType Directory -Path $out | Out-Null
$key = Join-Path (Split-Path (Split-Path $base -Parent) -Parent) '.lubancat_codex_ed25519'
$xsdb = 'D:/Software/AMDDesignTools/2026.1/Vitis/bin/xsdb.bat'
& scp -i $key -o BatchMode=yes -o ConnectTimeout=8 (Join-Path $PSScriptRoot 'audit_commit_capture.py') cat@172.31.200.2:/tmp/audit_commit_restart_20261001.py
if ($LASTEXITCODE) { throw 'COMMIT_RESTART_AUDIT_DEPLOY_FAILED' }
$serial = [System.IO.Ports.SerialPort]::new('COM9',115200,'None',8,'One')
$serial.Open()
$processes = @()
try {
    $serial.DiscardInBuffer()
    & $xsdb (Join-Path $PSScriptRoot 'prepare_commit_restart_v1.tcl') *> (Join-Path $out 'prepare.log')
    $prepareText = Get-Content (Join-Path $out 'prepare.log') -Raw
    if ($LASTEXITCODE -or $prepareText -match 'COMMIT_RESTART_PREPARE_FAILED' -or
        $prepareText -notmatch 'COMMIT_RESTART_PREPARED_CPU_STOPPED') {
        throw 'COMMIT_RESTART_PREPARE_FAILED'
    }
    $rk = Start-Process -FilePath 'ssh.exe' -WindowStyle Hidden -PassThru -ArgumentList @(
        '-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=8','cat@172.31.200.2',
        'bash -o pipefail -c ''sudo -n timeout 610 tcpdump -U -ni eth0 -s 0 -B 16384 -w - "ether src 12:34:56:78:9a:bc and udp port 1234" | python3 /tmp/audit_commit_restart_20261001.py -'''
    ) -RedirectStandardOutput (Join-Path $out 'rk_audit.json') -RedirectStandardError (Join-Path $out 'rk_tcpdump.log')
    $processes += $rk
    Start-Sleep -Seconds 1
    $cpu = Start-Process -FilePath $xsdb -WindowStyle Hidden -PassThru -ArgumentList @(
        (Join-Path $PSScriptRoot 'start_monitor_commit_restart_v1.tcl')
    ) -RedirectStandardOutput (Join-Path $out 'cpu.log') -RedirectStandardError (Join-Path $out 'cpu.stderr.log')
    $processes += $cpu
    $deadline = [DateTime]::UtcNow.AddSeconds(650)
    do {
        $text = $serial.ReadExisting()
        if ($text) {
            Add-Content -LiteralPath (Join-Path $out 'COM9.log') -Value $text -NoNewline
            Write-Host -NoNewline $text
        }
        foreach ($p in $processes) { $p.Refresh() }
        Start-Sleep -Milliseconds 100
    } while (($processes | Where-Object { -not $_.HasExited }) -and [DateTime]::UtcNow -lt $deadline)
    foreach ($p in $processes) {
        if (-not $p.HasExited) { throw "COMMIT_RESTART_TIMEOUT=$($p.Id)" }
    }
    if ($cpu.ExitCode -ne 0) { throw 'COMMIT_RESTART_CPU_MONITOR_FAILED' }
    if ($rk.ExitCode -notin @(0,124)) { throw "COMMIT_RESTART_RK_AUDIT_FAILED=$($rk.ExitCode)" }
    Write-Host "COMMIT_RESTART_BOARD_EVIDENCE=$out"
} finally {
    $serial.Close()
    foreach ($p in $processes) {
        $p.Refresh()
        if (-not $p.HasExited) { Stop-Process -Id $p.Id }
    }
}
