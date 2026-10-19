param([string]$Sqlite='C:\ProgramData\KroacnetBackup\bin\sqlite3.exe',[string]$Restic='C:\ProgramData\KroacnetBackup\bin\restic.exe')
. "$PSScriptRoot\windows-prepare.ps1"
$fixture=Join-Path $PSScriptRoot ('git-fixture-'+[Guid]::NewGuid().ToString('N'))
New-PrivateDirectory $fixture
$passed=[Collections.Generic.List[string]]::new()
function Assert-Test([bool]$Value,[string]$Name) { if (-not $Value) { throw ('TEST_FAILED '+$Name) }; $passed.Add($Name) }
function Expect-Refusal([scriptblock]$Action,[string]$Expected,[string]$Name) {
    $seen=$false; try { & $Action | Out-Null } catch { $seen=$_.Exception.Message -like ('*'+$Expected+'*') }
    Assert-Test $seen $Name
}
function Put([string]$Path,[string]$Text) { $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)); [IO.File]::WriteAllText($Path,$Text,$script:Utf8) }
function G([string[]]$A) { Invoke-BackupGit $script:Repo $A }
$script:Repo=Join-Path $fixture 'real repo [local]'; New-PrivateDirectory $script:Repo
$null=G @('init','--initial-branch=main')
$null=G @('config','user.name','fixture'); $null=G @('config','user.email','fixture@example.invalid')
$null=G @('config','core.autocrlf','false')
Put (Join-Path $script:Repo '.gitignore') "node_modules/`nartifacts/`n"
foreach ($name in @('tracked.txt','deleted.txt')) { Put (Join-Path $script:Repo $name) "base`n" }
$null=G @('add','--','.gitignore','tracked.txt','deleted.txt'); $null=G @('commit','-m','base')
$base=(G @('rev-parse','HEAD')).Trim()
$null=G @('checkout','-b','unpublished/topic')
Put (Join-Path $script:Repo 'topic.txt') "unpublished commit`n"
$null=G @('add','--','topic.txt'); $null=G @('commit','-m','unpublished')
$topic=(G @('rev-parse','HEAD')).Trim()
$null=G @('tag','-a','local-tag','-m','private fixture tag')
$null=G @('checkout','main')
foreach ($n in @(1,2)) {
    Put (Join-Path $script:Repo 'tracked.txt') "stash$n`n"
    Put (Join-Path $script:Repo ('stash-untracked'+$n+'.txt')) "stash untracked$n`n"
    $null=G @('stash','push','--include-untracked','-m',('stash'+$n))
}
Put (Join-Path $script:Repo 'tracked.txt') "staged version`n"
Put (Join-Path $script:Repo 'staged-only.txt') "staged new object`n"
$null=G @('add','--','tracked.txt','staged-only.txt'); $null=G @('rm','--','deleted.txt')
Put (Join-Path $script:Repo 'tracked.txt') "working differs from staged`n"
Put (Join-Path $script:Repo 'staged-only.txt') "working new differs`n"
Put (Join-Path $script:Repo 'untracked.txt') "uncommitted source`n"
Put (Join-Path $script:Repo 'node_modules\ignored.txt') 'excluded dependency'
Put (Join-Path $script:Repo 'artifacts\ignored.txt') 'excluded generated output'
Put (Join-Path $script:Repo '.git\info\exclude') "local-only-pattern`n"
Put (Join-Path $script:Repo '.git\hooks\post-checkout') "#!/bin/sh`nexit 99`n"
$null=G @('update-ref','refs/remotes/origin/main',$base)
Put (Join-Path $script:Repo '.git\FETCH_HEAD') 'first fetch'
$source=[pscustomobject]@{path=$script:Repo;alias='sources/test';required=$true;git_root=$true;excludes=@('node_modules','artifacts')}
$stage=Join-Path $fixture 'stage'; New-PrivateDirectory $stage
$runtime=Join-Path $fixture 'runtime'; New-PrivateDirectory $runtime
Put (Join-Path $runtime 'settings.json') '{"valid":true}'
$config=@{schema=1;host='chrysaora';stage_dir=$stage;project_root=$fixture;limits=@{max_files=200;max_file_bytes=67108864;max_total_bytes=134217728;max_json_bytes=1048576;max_jsonl_record_bytes=1048576;timeout_seconds=120;sqlite_timeout_seconds=10;busy_timeout_ms=1000};sources=@($source,@{path=$runtime;alias='runtime';required=$true;excludes=@()})}
$configPath=Join-Path $fixture 'config.json'; Write-JsonAtomic $configPath $config
$beforeState=Get-GitLocalState $script:Repo; $beforeWork=Get-TreeGuard $source
$beforeStatus=G @('status','--porcelain=v1','-z','--untracked-files=all')
$beforeDiff=G @('diff','--cached','--binary','--no-ext-diff','--no-textconv')
$beforeStash=G @('stash','list','--format=%H %gs')

# Deterministic fetch-equivalent write AFTER bundle creation but before its
# verification and final source guards. Real Git updates remote ref/reflog;
# source local refs/index/worktree are untouched. No network/production repo.
$script:OriginalGit=${function:Invoke-BackupGit}
$script:Injected=$false
function Invoke-BackupGit([string]$Root,[string[]]$Arguments,[string]$InputText='') {
    $out=& $script:OriginalGit $Root $Arguments $InputText
    if (-not $script:Injected -and $Root -eq $script:Repo -and $Arguments[0] -eq 'bundle' -and $Arguments[1] -eq 'create') {
        $script:Injected=$true
        $null=& $script:OriginalGit $Root @('update-ref','refs/remotes/origin/main',$topic)
        Put (Join-Path $Root '.git\FETCH_HEAD') 'fetch changed while export active'
        Put (Join-Path $Root '.git\refs\remotes\origin\unrelated.lock') 'remote update in progress'
    }
    return $out
}
try { $prepared=Invoke-WindowsPrepare $configPath $stage $Sqlite }
finally { Set-Item -Path function:Invoke-BackupGit -Value $script:OriginalGit }
Assert-Test $script:Injected 'real remote-ref update injected within export guard window'
Assert-TreeEqual $beforeWork (Get-TreeGuard $source)
Assert-GitLocalEqual $beforeState (Get-GitLocalState $script:Repo)
Assert-Test $true 'fetch ref/reflog/FETCH_HEAD/remote lock accepted with local state stable'
Assert-Test ((G @('rev-parse','refs/remotes/origin/main')).Trim() -ceq $topic) 'remote update actually occurred'
Assert-PreparedPayload $prepared
$backup=Join-Path $prepared.Payload 'sources\test'
$gitBackup=Join-Path $backup 'git'
Assert-Test (-not (Test-Path -LiteralPath (Join-Path $backup 'worktree\.git'))) 'no transient raw Git directory copied'
Assert-Test (@(Get-ChildItem -LiteralPath $gitBackup -File -Recurse | Where-Object {$_.Name -eq 'FETCH_HEAD' -or $_.Name -like '*.lock' -or $_.FullName -like '*\refs\remotes\*'}).Count -eq 0) 'fetch bookkeeping and remote reflogs absent'
Assert-Test (-not (Test-Path -LiteralPath (Join-Path $backup 'worktree\node_modules')) -and -not (Test-Path -LiteralPath (Join-Path $backup 'worktree\artifacts'))) 'unchanged exclusions applied'

# Reconstruct into an EMPTY isolated repo, no source fetch/reset/checkout.
$restore=Join-Path $fixture 'restore'; New-PrivateDirectory $restore
$recovery=Get-Content -LiteralPath (Join-Path $gitBackup 'recovery.json') -Raw | ConvertFrom-Json
$null=Invoke-BackupGit $restore @('init',('--object-format='+$recovery.object_format),'--initial-branch=main')
$null=Invoke-BackupGit $restore @('bundle','verify',(Join-Path $gitBackup 'history.bundle'))
Assert-Test $true 'bundle verified in empty repository without source prerequisites'
$heads=Invoke-BackupGit $restore @('bundle','unbundle',(Join-Path $gitBackup 'history.bundle'))
foreach ($line in ($heads -split "`n")) {
    if ($line -match '^([0-9a-f]{40,64}) (refs/[^\s]+)\s*$') { $null=Invoke-BackupGit $restore @('update-ref',$Matches[2],$Matches[1]) }
}
foreach ($r in $recovery.local_refs) { if ($r.symref) { $null=Invoke-BackupGit $restore @('symbolic-ref',$r.name,$r.symref) } }
foreach ($f in Get-ChildItem -LiteralPath $gitBackup -File -Filter 'index-objects-*') {
    Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $restore ('.git\objects\pack\'+$f.Name.Replace('index-objects-','pack-')))
}
foreach ($f in @(Get-SourceFiles ([pscustomobject]@{path=(Join-Path $gitBackup 'control');required=$true;excludes=@()}))) {
    $target=Join-Path $restore ('.git\'+$f.Relative.Replace('/','\')); $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)); Copy-Item -LiteralPath $f.Path -Destination $target
}
foreach ($f in @(Get-SourceFiles ([pscustomobject]@{path=(Join-Path $backup 'worktree');required=$true;excludes=@()}))) {
    $target=Join-Path $restore $f.Relative.Replace('/','\'); $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)); Copy-Item -LiteralPath $f.Path -Destination $target
}
Assert-Test ((Invoke-BackupGit $restore @('rev-parse','refs/heads/unpublished/topic')).Trim() -ceq $topic) 'unpublished branch recovered'
Assert-Test ((Invoke-BackupGit $restore @('rev-parse','refs/tags/local-tag')).Trim() -ceq (G @('rev-parse','refs/tags/local-tag')).Trim()) 'annotated local tag recovered'
Assert-Test ((Invoke-BackupGit $restore @('stash','list','--format=%H %gs')) -ceq $beforeStash) 'both stash records including older reflog entry recovered'
foreach ($n in @(0,1)) { $null=Invoke-BackupGit $restore @('cat-file','-e',('stash@{'+$n+'}^3:stash-untracked'+(2-$n)+'.txt')) }
Assert-Test $true 'older/newer stash untracked content objects recoverable'
Assert-Test ((Invoke-BackupGit $restore @('show',':tracked.txt')) -ceq "staged version`n") 'index restores staged content distinct from worktree'
Assert-Test ((Invoke-BackupGit $restore @('show',':staged-only.txt')) -ceq "staged new object`n") 'uncommitted index-only blob recovered from additional pack'
Assert-Test ((Invoke-BackupGit $restore @('diff','--cached','--binary','--no-ext-diff','--no-textconv')) -ceq $beforeDiff) 'staged additions/modifications/deletion exact'
Assert-Test ((Invoke-BackupGit $restore @('status','--porcelain=v1','-z','--untracked-files=all')) -ceq $beforeStatus) 'working/untracked/staged status exact after restore'
Assert-Test ((Get-Hash (Join-Path $restore '.git\index')) -ceq (Get-Hash (Join-Path $script:Repo '.git\index'))) 'index bytes preserved'
Assert-Test ((Get-Hash (Join-Path $restore '.git\config')) -ceq (Get-Hash (Join-Path $script:Repo '.git\config')) -and (Get-Hash (Join-Path $restore '.git\info\exclude')) -ceq (Get-Hash (Join-Path $script:Repo '.git\info\exclude'))) 'local config/exclude exact'
$null=Invoke-BackupGit $restore @('fsck','--full','--no-dangling')
Assert-Test $true 'restored history/index/reflogs pass full Git fsck'

# A later independent source may be copied after this repository has changed.
# Commit/HEAD/index/working changes are injected ONLY when runtime/settings.json
# starts copying, after the repository's own cut has already been validated.
$cutHead=(G @('rev-parse','HEAD')).Trim()
$cutStatus=G @('status','--porcelain=v1','-z','--untracked-files=all')
$cutDiff=G @('diff','--cached','--binary','--no-ext-diff','--no-textconv')
$cutIndex=Get-Hash (Join-Path $script:Repo '.git\index')
$cutWorking=Get-Hash (Join-Path $script:Repo 'tracked.txt')
$script:OriginalCopy=${function:Copy-PreparedFile}; $script:AfterCutUTC=$null
function Copy-PreparedFile([string]$Path,[string]$Target,[bool]$Opaque,$Limits,[string]$Sqlite) {
    if ($Path -eq (Join-Path $runtime 'settings.json') -and -not $script:AfterCutUTC) {
        $script:AfterCutUTC=[DateTime]::UtcNow.ToString('o')
        Put (Join-Path $script:Repo 'tracked.txt') "later committed content`n"
        $null=G @('add','--','tracked.txt'); $null=G @('commit','-m','after repository cut')
        Put (Join-Path $script:Repo 'untracked.txt') "later untracked content`n"
    }
    & $script:OriginalCopy $Path $Target $Opaque $Limits $Sqlite
}
try { $cutPrepared=Invoke-WindowsPrepare $configPath $stage $Sqlite }
finally { Set-Item -Path function:Copy-PreparedFile -Value $script:OriginalCopy }
Assert-Test ($script:AfterCutUTC -and (G @('rev-parse','HEAD')).Trim() -cne $cutHead) 'later runtime copy really committed local branch after Git cut'
Assert-PreparedPayload $cutPrepared
$cutManifest=Get-Content -LiteralPath (Join-Path $cutPrepared.Payload 'manifest.json') -Raw | ConvertFrom-Json
Assert-Test ($cutManifest.git_cuts.Count -eq 1 -and $cutManifest.git_cuts[0].alias -ceq 'sources/test' -and $cutManifest.git_cuts[0].head -ceq $cutHead -and [DateTime]$cutManifest.git_cuts[0].validated_utc -le [DateTime]$script:AfterCutUTC -and [DateTime]$cutManifest.git_cuts[0].capture_started_utc -le [DateTime]$cutManifest.git_cuts[0].validated_utc) 'manifest records earlier individual repository cut'
Assert-Test ((Get-Hash (Join-Path $cutPrepared.Payload 'sources\test\worktree\tracked.txt')) -ceq $cutWorking) 'completed cut retains earlier working bytes'
$cutLocalRepo=Join-Path $fixture 'cut-restic-repository'
$cutEnv=@{RESTIC_REPOSITORY=$cutLocalRepo;RESTIC_PASSWORD='synthetic-cut-password-only'}
$r=Invoke-Native $Restic @('--json','--no-cache','init') '' 30 $cutEnv
Assert-Test ($r.Exit -eq 0) 'cut fixture local Restic repository initialized'
$r=Invoke-Native $Restic @('--json','--no-cache','backup','--host','chrysaora','--tag','apps','--','payload') '' 60 $cutEnv ([IO.Path]::GetDirectoryName($cutPrepared.Payload))
Assert-Test ($r.Exit -eq 0 -and $r.Out -match '"snapshot_id"') 'generation uploads earlier coherent cut to local-only Restic'
$archiveRestore=Join-Path $fixture 'cut-archive-restored'
$r=Invoke-Native $Restic @('--no-cache','restore','latest','--target',$archiveRestore) '' 60 $cutEnv
Assert-Test ($r.Exit -eq 0) 'post-cut-change archive restored in isolation'
$restoredManifest=@(Get-ChildItem -LiteralPath $archiveRestore -Recurse -File -Filter 'manifest.json')
Assert-Test ($restoredManifest.Count -eq 1 -and (Get-Hash $restoredManifest[0].FullName) -ceq $cutPrepared.ManifestHash) 'restored cut manifest matches generation'
$restoredPayload=$restoredManifest[0].DirectoryName
$restoredCut=Join-Path $restoredPayload 'sources\test'
$gitCut=Join-Path $restoredCut 'git'
foreach ($file in $cutManifest.files) {
    if ((Get-Hash (Join-Path $restoredPayload $file.path.Replace('/','\'))) -cne $file.sha256) { throw 'restored_cut_hash_mismatch' }
}
Assert-Test $true 'all restored archive bytes match cut manifest'
$cutRestore=Join-Path $fixture 'cut-reconstructed'; New-PrivateDirectory $cutRestore
$cutRecovery=Get-Content -LiteralPath (Join-Path $gitCut 'recovery.json') -Raw | ConvertFrom-Json
$null=Invoke-BackupGit $cutRestore @('init',('--object-format='+$cutRecovery.object_format),'--initial-branch=main')
$null=Invoke-BackupGit $cutRestore @('bundle','verify',(Join-Path $gitCut 'history.bundle'))
$heads=Invoke-BackupGit $cutRestore @('bundle','unbundle',(Join-Path $gitCut 'history.bundle'))
foreach ($line in ($heads -split "`n")) {
    if ($line -match '^([0-9a-f]{40,64}) (refs/[^\s]+)\s*$') { $null=Invoke-BackupGit $cutRestore @('update-ref',$Matches[2],$Matches[1]) }
}
foreach ($ref in $cutRecovery.local_refs) { if ($ref.symref) { $null=Invoke-BackupGit $cutRestore @('symbolic-ref',$ref.name,$ref.symref) } }
foreach ($f in Get-ChildItem -LiteralPath $gitCut -File -Filter 'index-objects-*') {
    Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $cutRestore ('.git\objects\pack\'+$f.Name.Replace('index-objects-','pack-')))
}
foreach ($f in @(Get-SourceFiles ([pscustomobject]@{path=(Join-Path $gitCut 'control');required=$true;excludes=@()}))) {
    $target=Join-Path $cutRestore ('.git\'+$f.Relative.Replace('/','\')); $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)); Copy-Item -LiteralPath $f.Path -Destination $target
}
foreach ($f in @(Get-SourceFiles ([pscustomobject]@{path=(Join-Path $restoredCut 'worktree');required=$true;excludes=@()}))) {
    $target=Join-Path $cutRestore $f.Relative.Replace('/','\'); $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)); Copy-Item -LiteralPath $f.Path -Destination $target
}
Assert-Test ((Invoke-BackupGit $cutRestore @('rev-parse','HEAD')).Trim() -ceq $cutHead) 'archive reconstructs earlier HEAD and branch despite later commit'
Assert-Test ((Get-Hash (Join-Path $cutRestore '.git\index')) -ceq $cutIndex -and (Invoke-BackupGit $cutRestore @('diff','--cached','--binary','--no-ext-diff','--no-textconv')) -ceq $cutDiff) 'archive reconstructs earlier index and staged state'
Assert-Test ((Get-Hash (Join-Path $cutRestore 'tracked.txt')) -ceq $cutWorking -and (Invoke-BackupGit $cutRestore @('status','--porcelain=v1','-z','--untracked-files=all')) -ceq $cutStatus) 'archive reconstructs earlier working and untracked state'
$null=Invoke-BackupGit $cutRestore @('fsck','--full','--no-dangling')
Assert-Test $true 'reconstructed earlier cut passes full Git fsck'
[IO.File]::AppendAllText((Join-Path $cutPrepared.Payload 'sources\test\git\history.bundle'),'tampered',$script:Utf8)
Expect-Refusal { Assert-PreparedPayload $cutPrepared } 'payload_changed' 'completed Git cut still refuses staged hash tampering'

# End-to-end per-repository guards still refuse mutations INSIDE capture,
# injected immediately after one working file is copied, before its final guard.
foreach ($script:InsideMode in @('ref','work','index','head')) {
    $script:InsideChanged=$false
    function Copy-PreparedFile([string]$Path,[string]$Target,[bool]$Opaque,$Limits,[string]$Sqlite) {
        $result=& $script:OriginalCopy $Path $Target $Opaque $Limits $Sqlite
        if (-not $script:InsideChanged -and $Path -eq (Join-Path $script:Repo 'tracked.txt')) {
            $script:InsideChanged=$true
            switch ($script:InsideMode) {
                'ref' { $null=G @('update-ref','refs/heads/inside-cut',$base) }
                'work' { Put (Join-Path $script:Repo 'tracked.txt') 'inside capture working mutation' }
                'index' { $null=G @('add','--','untracked.txt') }
                'head' { $null=G @('update-ref','--no-deref','HEAD',$topic) }
            }
        }
        return $result
    }
    try { Expect-Refusal { Invoke-WindowsPrepare $configPath $stage $Sqlite } 'repository_changed' ('inside capture '+$script:InsideMode+' mutation refused') }
    finally { Set-Item -Path function:Copy-PreparedFile -Value $script:OriginalCopy }
    Assert-Test ($script:InsideChanged -and -not (Test-Path -LiteralPath (Join-Path $stage 'pending\ready.json'))) ('inside capture '+$script:InsideMode+' mutation leaves no ready generation')
}
$null=G @('symbolic-ref','HEAD','refs/heads/main')

# Mutations must refuse; each change occurs only in this disposable fixture.
$saved=Get-GitLocalState $script:Repo
$null=G @('update-ref','refs/heads/new-local',$base)
Expect-Refusal { Assert-GitLocalEqual $saved (Get-GitLocalState $script:Repo) } 'repository_changed' 'new local ref rejected'
$null=G @('update-ref','-d','refs/heads/new-local')
$saved=Get-GitLocalState $script:Repo
$null=G @('update-ref','refs/heads/unpublished/topic',$base)
Expect-Refusal { Assert-GitLocalEqual $saved (Get-GitLocalState $script:Repo) } 'repository_changed' 'changed local branch rejected'
$null=G @('update-ref','refs/heads/unpublished/topic',$topic)
$guard=Get-TreeGuard $source; Put (Join-Path $script:Repo 'untracked.txt') 'changed authored file'
Expect-Refusal { Assert-TreeEqual $guard (Get-TreeGuard $source) } 'repository_changed' 'untracked file mutation rejected'
$saved=Get-GitLocalState $script:Repo
$null=G @('add','--','untracked.txt')
Expect-Refusal { Assert-GitLocalEqual $saved (Get-GitLocalState $script:Repo) } 'repository_changed' 'index/staged mutation rejected'
$saved=Get-GitLocalState $script:Repo
$null=G @('symbolic-ref','HEAD','refs/heads/unpublished/topic')
Expect-Refusal { Assert-GitLocalEqual $saved (Get-GitLocalState $script:Repo) } 'repository_changed' 'HEAD switch rejected'
$null=G @('symbolic-ref','HEAD','refs/heads/main')
$saved=Get-GitLocalState $script:Repo
$null=G @('config','fixture.changed','true')
Expect-Refusal { Assert-GitLocalEqual $saved (Get-GitLocalState $script:Repo) } 'repository_changed' 'local config change rejected'
$oldGitDir=$env:GIT_DIR
try { $env:GIT_DIR=Join-Path $restore '.git'; $isolated=Get-GitLocalState $script:Repo; Assert-Test ($isolated.Controls['config'] -ceq (Get-GitLocalState $script:Repo).Controls['config']) 'inherited GIT_DIR cannot redirect source' }
finally { $env:GIT_DIR=$oldGitDir }

# Deliberately fail cleanup after invalid runtime JSON. Original fixed error
# survives; no ready stage/upload path is returned. No live data involved.
Put (Join-Path $runtime 'settings.json') '{invalid'
$script:OriginalCleanup=${function:Remove-OwnedPending}; $script:CleanupCalls=0
function Remove-OwnedPending([string]$Stage) {
    $script:CleanupCalls++
    if ($script:CleanupCalls -gt 1) { throw 'fixture_cleanup_locked' }
    & $script:OriginalCleanup $Stage
}
try { Expect-Refusal { Invoke-WindowsPrepare $configPath $stage $Sqlite } 'invalid_json' 'original prep error survives cleanup exception' }
finally { Set-Item -Path function:Remove-OwnedPending -Value $script:OriginalCleanup }
Assert-Test (-not (Test-Path -LiteralPath (Join-Path $stage 'pending\ready.json'))) 'failed preparation never becomes uploadable'
Remove-OwnedPending $stage

# Exercise the REAL runner's fixed error category with a fixture-only cleanup
# fault. Runtime installed source and real stage are never changed.
$runnerDir=Join-Path $fixture 'runner-error-fixture'; New-PrivateDirectory $runnerDir
foreach ($name in @('windows-native-common.ps1','windows-git.ps1','windows-prepare.ps1','windows-run.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $runnerDir $name)
}
$injection=@'

$script:CleanupActual=${function:Remove-OwnedPending}; $script:CleanupCount=0
function Remove-OwnedPending([string]$Stage) {
    $script:CleanupCount++
    if ($script:CleanupCount -gt 1) { throw 'fixture_cleanup_locked' }
    & $script:CleanupActual $Stage
}
'@
[IO.File]::AppendAllText((Join-Path $runnerDir 'windows-prepare.ps1'),$injection,$script:Utf8)
Write-JsonAtomic (Join-Path $stage 'last-success.json') @{sentinel='keep prior success'}
$priorSuccess=Get-Hash (Join-Path $stage 'last-success.json')
$r=Invoke-Native 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','RemoteSigned','-File',(Join-Path $runnerDir 'windows-run.ps1'),'-ConfigPath',$configPath) '' 40
$attempt=Get-Content -LiteralPath (Join-Path $stage 'last-attempt.json') -Raw | ConvertFrom-Json
Assert-Test ($r.Exit -eq 1 -and $attempt.category -ceq 'invalid_json:pending_cleanup_failed') 'actual runner retains primary fixed category with cleanup suffix'
Assert-Test ((Get-Hash (Join-Path $stage 'last-success.json')) -ceq $priorSuccess) 'cleanup failure retains previous success record'
Assert-Test (-not (Test-Path -LiteralPath (Join-Path $stage 'pending\ready.json'))) 'cleanup failure cannot upload failed stage'
Remove-OwnedPending $stage
$receipt=@{utc=[DateTime]::UtcNow.ToString('o');passed=$passed.Count;tests=@($passed.ToArray());fixture=$fixture;git_version=(G @('--version')).Trim();cloud_access=$false;production_source_preparation=$false}
Write-JsonAtomic (Join-Path $PSScriptRoot 'git-test-receipt.json') $receipt
$receipt | ConvertTo-Json -Depth 4
