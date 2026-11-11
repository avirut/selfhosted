$script:GitExe='C:\Program Files\Git\cmd\git.exe'
function Invoke-BackupGit([string]$Root,[string[]]$Arguments,[string]$InputText='') {
    $rootFull=Assert-PlainPath $Root
    Test-Deadline
    $seconds=120
    if ($script:Deadline) { $seconds=[int][Math]::Max(1,[Math]::Min(120,($script:Deadline-[DateTime]::UtcNow).TotalSeconds)) }
    $envValues=@{GIT_CONFIG_NOSYSTEM='1';GIT_CONFIG_SYSTEM='/dev/null';GIT_CONFIG_GLOBAL='/dev/null';GIT_OPTIONAL_LOCKS='0';GIT_TERMINAL_PROMPT='0';GIT_NO_LAZY_FETCH='1'}
    $prefix=@('--no-replace-objects','-c',('safe.directory='+$rootFull),'-c','core.fsmonitor=false','-c','core.hooksPath=/dev/null','-c','gc.auto=0','-c','maintenance.auto=false','-C',$rootFull)
    $r=Invoke-Native $script:GitExe ($prefix+$Arguments) $InputText $seconds $envValues
    if ($r.Exit -ne 0) { throw 'git_command_failed' }
    return $r.Out
}
function Get-GitControlFiles([string]$Root) {
    $dir=Assert-PlainPath ([IO.Path]::Combine($Root,'.git'))
    if (-not [IO.Directory]::Exists($dir)) { throw 'git_control_directory_missing' }
    foreach ($name in @('commondir','shallow','MERGE_HEAD','CHERRY_PICK_HEAD','REVERT_HEAD','REBASE_HEAD','rebase-apply','rebase-merge','sequencer','index.lock','HEAD.lock','config.lock','objects/info/alternates')) {
        if (Test-Path -LiteralPath ([IO.Path]::Combine($dir,$name.Replace('/','\')))) { throw 'git_operation_or_layout_unsupported' }
    }
    foreach ($name in @('HEAD','index','config','config.worktree','description','ORIG_HEAD','info/exclude','info/attributes')) {
        $path=[IO.Path]::Combine($dir,$name.Replace('/','\')); $null=Assert-PlainPath $path
        if ([IO.File]::Exists($path)) { [pscustomobject]@{Path=$path;Relative=$name} }
    }
    foreach ($path in [IO.Directory]::EnumerateFiles($dir,'sharedindex.*')) {
        $null=Assert-PlainPath $path; [pscustomobject]@{Path=$path;Relative=[IO.Path]::GetFileName($path)}
    }
    foreach ($sub in @('logs','hooks')) {
        $base=[IO.Path]::Combine($dir,$sub)
        if ([IO.Directory]::Exists($base)) {
            $source=[pscustomobject]@{path=$base;required=$true;excludes=@('refs/remotes','*.lock')}
            foreach ($f in @(Get-SourceFiles $source)) { [pscustomobject]@{Path=$f.Path;Relative=($sub+'/'+$f.Relative)} }
        }
    }
}
function Get-GitLocalState([string]$Root) {
    $controls=@(Get-GitControlFiles $Root)
    $top=(Invoke-BackupGit $Root @('rev-parse','--show-toplevel')).Trim()
    if ([IO.Path]::GetFullPath($top) -ine [IO.Path]::GetFullPath($Root)) { throw 'git_root_mismatch' }
    $format=(Invoke-BackupGit $Root @('rev-parse','--show-object-format')).Trim()
    if ($format -notin @('sha1','sha256')) { throw 'git_object_format_unsupported' }
    $configText=Invoke-BackupGit $Root @('config','--local','--list')
    if ($configText -match '(?im)^(extensions\.(partialclone|refstorage)|remote\..*\.promisor)=') { throw 'git_operation_or_layout_unsupported' }
    $refs=[Collections.Generic.SortedDictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach ($line in ((Invoke-BackupGit $Root @('for-each-ref','--format=%(refname) %(objectname) %(symref)')) -split "`n")) {
        if (-not $line) { continue }
        if ($line -notmatch '^(refs/\S+) ([0-9a-f]{40,64}) ?(.*)$') { throw 'git_ref_invalid' }
        if ($Matches[1].StartsWith('refs/remotes/')) { continue }
        $refs.Add($Matches[1],($Matches[2]+' '+$Matches[3].TrimEnd("`r")))
    }
    $head=(Invoke-BackupGit $Root @('rev-parse','--verify','HEAD')).Trim()
    $map=[Collections.Generic.SortedDictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach ($f in $controls) {
        $i=[IO.FileInfo]::new($f.Path)
        $map.Add($f.Relative,('{0}:{1}:{2}:{3}' -f $i.Length,$i.LastWriteTimeUtc.Ticks,$i.CreationTimeUtc.Ticks,(Get-Hash $f.Path)))
    }
    $objects=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in ((Invoke-BackupGit $Root @('ls-files','--stage','-z')) -split "`0")) {
        if (-not $entry) { continue }
        if ($entry -notmatch '^(\d{6}) ([0-9a-f]{40,64}) [0-3]\t') { throw 'git_index_invalid' }
        if ($Matches[1] -ne '160000' -and $Matches[2] -notmatch '^0+$') { $null=$objects.Add($Matches[2]) }
    }
    return [pscustomobject]@{Root=$Root;Head=$head;Format=$format;Refs=$refs;Controls=$map;ControlFiles=$controls;IndexObjects=@($objects | Sort-Object)}
}
function Assert-GitLocalEqual($Before,$After) {
    if ($Before.Head -cne $After.Head -or $Before.Format -cne $After.Format) { throw 'repository_changed' }
    Assert-TreeEqual $Before.Refs $After.Refs
    Assert-TreeEqual $Before.Controls $After.Controls
    if (($Before.IndexObjects -join "`n") -cne ($After.IndexObjects -join "`n")) { throw 'repository_changed' }
}
function Export-GitLogical($State,[string]$Destination,$Limits,[string]$Sqlite) {
    $null=Assert-PlainPath $Destination
    $null=[IO.Directory]::CreateDirectory($Destination)
    $bundle=[IO.Path]::Combine($Destination,'history.bundle')
    $null=Invoke-BackupGit $State.Root @('bundle','create',$bundle,'--all','--reflog')
    $null=Invoke-BackupGit $State.Root @('bundle','verify',$bundle)
    $bundleRefs=@{}
    foreach ($line in ((Invoke-BackupGit $State.Root @('bundle','list-heads',$bundle)) -split "`n")) {
        if (-not $line) { continue }
        if ($line -notmatch '^([0-9a-f]{40,64}) (.+)$') { throw 'git_bundle_ref_invalid' }
        $bundleRefs[$Matches[2].TrimEnd("`r")]=$Matches[1]
    }
    foreach ($ref in $State.Refs.Keys) {
        if (-not $bundleRefs.ContainsKey($ref) -or $bundleRefs[$ref] -cne $State.Refs[$ref].Split(' ')[0]) { throw 'repository_changed' }
    }
    if (-not $bundleRefs.ContainsKey('HEAD') -or $bundleRefs['HEAD'] -cne $State.Head) { throw 'repository_changed' }
    $indexPack=$null
    if ($State.IndexObjects.Count) {
        $prefix=[IO.Path]::Combine($Destination,'index-objects')
        $hash=(Invoke-BackupGit $State.Root @('pack-objects','--revs',$prefix) (($State.IndexObjects -join "`n")+"`n")).Trim()
        if ($hash -notmatch '^[0-9a-f]{40,64}$') { throw 'git_index_pack_invalid' }
        $indexPack='index-objects-'+$hash
        $null=Invoke-BackupGit $State.Root @('verify-pack',([IO.Path]::Combine($Destination,$indexPack+'.idx')))
    }
    foreach ($f in $State.ControlFiles) {
        $target=[IO.Path]::Combine($Destination,('control/'+$f.Relative).Replace('/','\'))
        $record=Copy-PreparedFile $f.Path $target $true $Limits $Sqlite
        if ($record.sha256 -cne $State.Controls[$f.Relative].Split(':')[-1]) { throw 'repository_changed' }
    }
    Assert-GitLocalEqual $State (Get-GitLocalState $State.Root)
    $refs=@($State.Refs.Keys | ForEach-Object { @{name=$_;oid=$State.Refs[$_].Split(' ')[0];symref=$State.Refs[$_].Substring($State.Refs[$_].IndexOf(' ')+1)} })
    Write-JsonAtomic ([IO.Path]::Combine($Destination,'recovery.json')) @{schema=1;representation='git-bundle-index-v1';object_format=$State.Format;head=$State.Head;local_refs=$refs;index_pack=$indexPack;bundle='history.bundle';controls='control';working_tree='../worktree';remote_refs='point_in_time_bundle_only';excluded_control='fetch bookkeeping, remote reflogs, locks, other worktree administrative state'}
    Get-SourceFiles ([pscustomobject]@{path=$Destination;required=$true;excludes=@()})
}
