[CmdletBinding()]
param(
    [ValidateSet('Prepare','Backup')][string]$Mode='Backup',
    [string]$ConfigPath='C:\ProgramData\KroacnetBackup\windows-native.json',
    [string]$EnvPath='C:\ProgramData\KroacnetBackup\shared.env',
    [string]$Restic='C:\ProgramData\KroacnetBackup\bin\restic.exe',
    [string]$Sqlite='C:\ProgramData\KroacnetBackup\bin\sqlite3.exe'
)
. "$PSScriptRoot\windows-prepare.ps1"
$lock=$null; $stage=$null; $started=[DateTime]::UtcNow.ToString('o')
try {
    Assert-Private $ConfigPath
    $config=[IO.File]::ReadAllText($ConfigPath) | ConvertFrom-Json
    $stage=Assert-PlainPath $config.stage_dir; Assert-Private $stage
    $lockPath=[IO.Path]::Combine($stage,'native-backup.lock'); $null=Assert-PlainPath $lockPath
    try { $lock=[IO.File]::Open($lockPath,'OpenOrCreate','ReadWrite','None') } catch { throw 'backup_already_running' }
    $result=Invoke-WindowsPrepare $ConfigPath $stage $Sqlite
    if ($Mode -eq 'Prepare') {
        Write-Output (@{status='prepared';run_id=$result.RunId;files=$result.Files;bytes=$result.Bytes;manifest_sha256=$result.ManifestHash} | ConvertTo-Json -Compress)
        exit 0
    }
    Assert-Private $Restic
    $values=Read-SharedEnv $EnvPath
    $cache=[IO.Path]::Combine($stage,'restic-cache'); New-PrivateDirectory $cache
    Assert-PreparedPayload $result
    # Credentials are child-process environment only, never argv or machine/user env.
    # No init/forget/prune/unlock, repository selection or password substitution.
    $r=Invoke-Native $Restic @('--json','--cache-dir',$cache,'--retry-lock','2m','backup','--host','chrysaora','--tag','apps','--','payload') '' 7200 $values ([IO.Path]::GetDirectoryName($result.Payload))
    $values.Clear()
    if ($r.Exit -ne 0) { throw ('restic_exit_'+$r.Exit) }
    Assert-PreparedPayload $result
    $summary=@($r.Out -split "`n" | Where-Object {$_} | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object {$_.message_type -eq 'summary'})
    if ($summary.Count -ne 1 -or $summary[0].snapshot_id -notmatch '^[a-f0-9]{8,64}$') { throw 'restic_summary_missing' }
    $success=@{status='success';started_utc=$started;completed_utc=[DateTime]::UtcNow.ToString('o');host='chrysaora';tag='apps';run_id=$result.RunId;snapshot_id=$summary[0].snapshot_id;files=$result.Files;bytes=$result.Bytes;manifest_sha256=$result.ManifestHash;browser_preferences='excluded_unavailable'}
    Write-JsonAtomic ([IO.Path]::Combine($stage,'last-success.json')) $success
    Write-JsonAtomic ([IO.Path]::Combine($stage,'last-attempt.json')) $success
    Remove-OwnedPending $stage
    Write-Output ($success | ConvertTo-Json -Compress)
    exit 0
} catch {
    $category='native_failure'
    if ($_.Exception.Message -match '^[a-z][a-z0-9_]{1,80}$') { $category=$_.Exception.Message }
    if ($lock -and $stage) {
        try { Remove-OwnedPending $stage } catch { $category+=':pending_cleanup_failed' }
        try { Write-JsonAtomic ([IO.Path]::Combine($stage,'last-attempt.json')) @{status='failed';category=$category;started_utc=$started;completed_utc=[DateTime]::UtcNow.ToString('o')} } catch {}
    }
    [Console]::Error.WriteLine('KROACNET_BACKUP_FAILED '+$category)
    exit 1
} finally { if ($lock) { $lock.Dispose() } }
