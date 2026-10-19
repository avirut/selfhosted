# Windows PowerShell 5.1; shared by prepare/run. No Python or provider runtime.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Utf8 = [Text.UTF8Encoding]::new($false, $true)
$script:Deadline = $null
$script:Trusted = @('S-1-5-18','S-1-5-32-544','S-1-5-21-2723258411-2665015537-3239607709-1001')
if (-not ('KroacnetFileIdentity' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class KroacnetFileIdentity {
 [StructLayout(LayoutKind.Sequential)] struct Info {
  public uint Attr,CreateLo,CreateHi,AccessLo,AccessHi,WriteLo,WriteHi,Volume,SizeHi,SizeLo,Links,IndexHi,IndexLo;
 }
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle h,out Info i);
 public static string Get(FileStream f) { Info i; if(!GetFileInformationByHandle(f.SafeFileHandle,out i)) throw new IOException("identity_failed");
  return i.Volume.ToString("x8")+":"+i.IndexHi.ToString("x8")+i.IndexLo.ToString("x8"); }
}
'@
}
function Assert-PlainPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if ($full -notmatch '^[A-Za-z]:\\' -or $full.Substring(2).Contains(':')) { throw 'nonlocal_path' }
    $p = $full
    while ($p) {
        if ([IO.File]::Exists($p) -or [IO.Directory]::Exists($p)) {
            if (([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'reparse_path' }
        }
        $p = [IO.Path]::GetDirectoryName($p)
    }
    return $full
}
function Assert-Private([string]$Path) {
    $null = Assert-PlainPath $Path
    $acl = Get-Acl -LiteralPath $Path
    $raw=[Security.AccessControl.RawSecurityDescriptor]::new($acl.GetSecurityDescriptorBinaryForm(),0)
    if ($null -eq $raw.DiscretionaryAcl -or ($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclPresent) -eq 0) { throw 'null_dacl' }
    $owner = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
    if ($owner -notin $script:Trusted) { throw 'untrusted_owner' }
    foreach ($ace in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
        if ($ace.AccessControlType -eq 'Allow' -and $ace.IdentityReference.Value -notin ($script:Trusted + 'S-1-3-4')) { throw 'broad_acl' }
    }
}
function New-PrivateDirectory([string]$Path) {
    $full = Assert-PlainPath $Path
    $parent = [IO.Path]::GetDirectoryName($full)
    Assert-Private $parent
    if (-not [IO.Directory]::Exists($full)) { $null = [IO.Directory]::CreateDirectory($full) }
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetOwner([Security.Principal.SecurityIdentifier]::new($script:Trusted[2]))
    $acl.SetAccessRuleProtection($true,$false)
    foreach ($sid in $script:Trusted) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
    }
    Set-Acl -LiteralPath $full -AclObject $acl
    Assert-Private $full
}
function Write-JsonAtomic([string]$Path,$Value) {
    $null = Assert-PlainPath $Path
    Assert-Private ([IO.Path]::GetDirectoryName($Path))
    $temp = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($temp,($Value | ConvertTo-Json -Depth 16),$script:Utf8)
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp,$Path,[NullString]::Value) }
    else { [IO.File]::Move($temp,$Path) }
}
function Read-SharedEnv([string]$Path) {
    Assert-Private $Path
    if (([IO.FileInfo]::new($Path)).Length -gt 16384) { throw 'env_size_limit' }
    $values=@{}
    foreach ($line in [IO.File]::ReadAllLines($Path,$script:Utf8)) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
        if ($line -notmatch '^(RESTIC_REPOSITORY|RESTIC_PASSWORD|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY)=(.*)$') { throw 'invalid_env' }
        $key=$Matches[1]; $raw=$Matches[2]; $value=[Text.StringBuilder]::new(); $pos=0
        if ($values.ContainsKey($key)) { throw 'duplicate_env_key' }
        while ($pos -lt $raw.Length) {
            $ch=$raw[$pos]
            if ($ch -eq [char]39) {
                $end=$raw.IndexOf([char]39,$pos+1)
                if ($end -lt 0) { throw 'invalid_env_quoting' }
                $null=$value.Append($raw.Substring($pos+1,$end-$pos-1)); $pos=$end+1
            } elseif ($ch -eq [char]34 -and $pos+2 -lt $raw.Length -and $raw[$pos+1] -eq [char]39 -and $raw[$pos+2] -eq [char]34) {
                $null=$value.Append([char]39); $pos+=3
            } elseif ($ch -eq [char]92 -and $pos+1 -lt $raw.Length -and $raw[$pos+1] -eq [char]39) {
                $null=$value.Append([char]39); $pos+=2
            } elseif ([string]$ch -cmatch '^[A-Za-z0-9_.,:/+=@%\-]$') {
                $null=$value.Append($ch); $pos++
            } else { throw 'invalid_env_quoting' }
        }
        if ($value.Length -eq 0 -or $value.ToString().Contains([char]0)) { throw 'invalid_env' }
        $values[$key]=$value.ToString()
    }
    if ($values.Count -ne 4 -or $values.RESTIC_REPOSITORY -notmatch '^(s3:|b2:)') { throw 'invalid_env' }
    return $values
}
function Get-Hash([string]$Path) {
    $null = Assert-PlainPath $Path
    $s = [IO.File]::Open($Path,'Open','Read','ReadWrite')
    $h = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($h.ComputeHash($s))).Replace('-','').ToLowerInvariant() }
    finally { $s.Dispose(); $h.Dispose() }
}
function Get-PrefixHash([IO.FileStream]$Stream,[long]$Length) {
    $Stream.Position = 0
    $h = [Security.Cryptography.SHA256]::Create(); $buffer = New-Object byte[] 1048576
    try {
        $left = $Length
        while ($left -gt 0) {
            Test-Deadline
            $n=$Stream.Read($buffer,0,[int][Math]::Min($left,$buffer.Length))
            if ($n -eq 0) { throw 'source_shrank' }
            $null=$h.TransformBlock($buffer,0,$n,$buffer,0); $left-=$n
        }
        $null=$h.TransformFinalBlock([byte[]]@(),0,0)
        return ([BitConverter]::ToString($h.Hash)).Replace('-','').ToLowerInvariant()
    } finally { $h.Dispose() }
}
function Test-Deadline {
    if ($script:Deadline -and [DateTime]::UtcNow -gt $script:Deadline) { throw 'preparation_timeout' }
}
function Invoke-Native([string]$Exe,[string[]]$Arguments,[string]$InputText='',[int]$TimeoutSeconds=60,[hashtable]$Environment=@{},[string]$WorkingDirectory='') {
    $null = Assert-PlainPath $Exe
    $quoted = foreach ($arg in $Arguments) {
        if ($arg -match '["\r\n\x00]') { throw 'invalid_native_argument' }
        '"' + ([regex]::Replace($arg,'(\\+)$','$1$1')) + '"'
    }
    $si=[Diagnostics.ProcessStartInfo]::new($Exe,($quoted -join ' '))
    $si.UseShellExecute=$false; $si.CreateNoWindow=$true
    $si.RedirectStandardInput=$true; $si.RedirectStandardOutput=$true; $si.RedirectStandardError=$true
    $si.StandardOutputEncoding=$script:Utf8; $si.StandardErrorEncoding=$script:Utf8
    if ($WorkingDirectory) { $si.WorkingDirectory=$WorkingDirectory }
    foreach ($key in @($si.EnvironmentVariables.Keys)) {
        if ($key -match '^(RESTIC|AWS|B2|RCLONE)_') { $si.EnvironmentVariables.Remove($key) }
    }
    foreach ($key in $Environment.Keys) { $si.EnvironmentVariables[$key]=$Environment[$key] }
    $p=[Diagnostics.Process]::new(); $p.StartInfo=$si
    try {
        $null=$p.Start(); $out=$p.StandardOutput.ReadToEndAsync(); $err=$p.StandardError.ReadToEndAsync()
        $p.StandardInput.Write($InputText); $p.StandardInput.Close()
        if (-not $p.WaitForExit($TimeoutSeconds*1000)) { $p.Kill(); $p.WaitForExit(); throw 'native_timeout' }
        return [pscustomobject]@{Exit=$p.ExitCode;Out=$out.Result;Error=$err.Result}
    } finally { $p.Dispose() }
}
function Test-Excluded([string]$Relative,[string[]]$Patterns) {
    foreach ($pattern in $Patterns) {
        $candidate=$Relative
        if (-not $pattern.Contains('/')) { $candidate=($Relative.Split('/') | Select-Object -Last 1) }
        $wc=[Management.Automation.WildcardPattern]::new($pattern,[Management.Automation.WildcardOptions]::CultureInvariant)
        if ($wc.IsMatch($candidate)) { return $true }
    }
    return $false
}
function Get-SourceFiles($Source) {
    $root=Assert-PlainPath $Source.path
    if (-not [IO.File]::Exists($root) -and -not [IO.Directory]::Exists($root)) {
        if ($Source.required) { throw 'required_source_missing' }; return
    }
    if ([IO.File]::Exists($root)) { [pscustomobject]@{Path=$root;Relative=''}; return }
    $todo=[Collections.Generic.Stack[string]]::new(); $todo.Push($root)
    while ($todo.Count) {
        Test-Deadline
        $dir=$todo.Pop()
        foreach ($p in [IO.Directory]::EnumerateFileSystemEntries($dir)) {
            $rel=$p.Substring($root.Length+1).Replace('\','/')
            if (Test-Excluded $rel @($Source.excludes)) { continue }
            $null=Assert-PlainPath $p
            $attr=[IO.File]::GetAttributes($p)
            if (($attr -band [IO.FileAttributes]::Directory) -ne 0) { $todo.Push($p) }
            else { [pscustomobject]@{Path=$p;Relative=$rel} }
        }
    }
}
function Get-TreeGuard($Source) {
    $map=[Collections.Generic.SortedDictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach ($file in @(Get-SourceFiles $Source)) {
        Test-Deadline
        if ($file.Relative -match '^\.git/.*\.lock$') { throw 'git_lock_present' }
        $i=[IO.FileInfo]::new($file.Path); $hash=Get-Hash $file.Path
        $map.Add($file.Relative,('{0}:{1}:{2}:{3}' -f $i.Length,$i.LastWriteTimeUtc.Ticks,$i.CreationTimeUtc.Ticks,$hash))
    }
    return ,$map
}
function Assert-TreeEqual($Before,$After) {
    if ($Before.Count -ne $After.Count) { throw 'repository_changed' }
    foreach ($key in $Before.Keys) {
        if (-not $After.ContainsKey($key) -or $Before[$key] -cne $After[$key]) { throw 'repository_changed' }
    }
}
function Remove-OwnedPending([string]$Stage) {
    $stageFull=Assert-PlainPath $Stage
    Assert-Private $stageFull
    $pending=Assert-PlainPath ([IO.Path]::Combine($stageFull,'pending'))
    if ([IO.Path]::GetDirectoryName($pending) -cne $stageFull -or [IO.Path]::GetFileName($pending) -cne 'pending') { throw 'unsafe_pending_path' }
    if ([IO.Directory]::Exists($pending)) {
        $scan=[Collections.Generic.Stack[string]]::new(); $scan.Push($pending)
        while ($scan.Count) {
            $dir=$scan.Pop(); $null=Assert-PlainPath $dir
            foreach ($p in [IO.Directory]::EnumerateFileSystemEntries($dir)) {
                $null=Assert-PlainPath $p
                if ([IO.Directory]::Exists($p)) { $scan.Push($p) }
            }
        }
        Remove-Item -LiteralPath $pending -Recurse -Force
    }
}
