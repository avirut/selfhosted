[CmdletBinding()]
param(
    [string]$Root='C:\',
    [string]$Base='C:\ProgramData\KroacnetBackup',
    [switch]$DryRun
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$state=Join-Path $Base 'state'
$null=New-Item -ItemType Directory -Force -Path $state
function Save-Result([hashtable]$Value) {
    $Value.completed_utc=[DateTime]::UtcNow.ToString('o')
    $Value | ConvertTo-Json -Compress | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $state 'last-attempt.json')
}
try {
    foreach ($line in [IO.File]::ReadAllLines((Join-Path $Base 'shared.env'))) {
        if ($line -match '^([A-Z0-9_]+)=(.*)$') {
            $name=$Matches[1]; $value=$Matches[2]
            if ($value -match "^'(.*)'$") { $value=$Matches[1] }
            [Environment]::SetEnvironmentVariable($name,$value,'Process')
        }
    }
    $arguments=@('--json','--cache-dir',(Join-Path $state 'cache'),'--retry-lock','5m','backup',$Root,'--use-fs-snapshot','--exclude-caches','--exclude-cloud-files',
        '--iexclude-file',(Join-Path $Base 'native\excludes.txt'),'--iexclude',$state,'--host','chrysaora','--tag','apps')
    if ($DryRun) { $arguments+='--dry-run' }
    $ErrorActionPreference='Continue'
    & (Join-Path $Base 'bin\restic.exe') @arguments > (Join-Path $state 'backup.jsonl') 2> (Join-Path $state 'unreadable.jsonl')
    $status=$LASTEXITCODE
    $ErrorActionPreference='Stop'
    if ($status -ne 0 -and $status -ne 3) { throw "restic exited $status" }
    $summary=Get-Content (Join-Path $state 'backup.jsonl') | Where-Object { $_ -match '"message_type":"summary"' } | Select-Object -Last 1 | ConvertFrom-Json
    if (-not $summary.snapshot_id) { throw 'restic reported no snapshot' }
    Save-Result @{status='success';snapshot_id=$summary.snapshot_id;files=$summary.total_files_processed;bytes=$summary.total_bytes_processed;added=$summary.data_added_packed}
    exit 0
} catch {
    Save-Result @{status='failed';reason=$_.Exception.Message}
    exit 1
}
