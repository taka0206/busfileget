# Windows PowerShell 5.1 helper for DownloadPerf.ttl.
# Wait for Tera Term SCP, verify remote SHA-256, extract, write file manifest.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $Archive,
    [Parameter(Mandatory = $true)][string] $OutputDirectory,
    [Parameter(Mandatory = $true)][string] $ExpectedBytes,
    [Parameter(Mandatory = $true)][string] $ExpectedHash,
    [ValidateRange(1, 86400)][int] $TimeoutSeconds = 3600
)

$ErrorActionPreference = 'Stop'
$logFile = Join-Path -Path $OutputDirectory -ChildPath 'verify_extract.log'

function Log([string] $message) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $message
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
}

try {
    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        throw 'The specified output directory does not exist.'
    }
    $expectedSize = [long]::Parse($ExpectedBytes, [Globalization.CultureInfo]::InvariantCulture)
    if ($expectedSize -le 0 -or $ExpectedHash -cnotmatch '^[a-f0-9]{64}$') {
        throw 'Invalid expected archive size or SHA-256.'
    }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    Log ('Waiting for SCP: {0} bytes' -f $expectedSize)
    $ready = $false

    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $Archive -PathType Leaf) {
            $currentSize = (Get-Item -LiteralPath $Archive).Length
            if ($currentSize -gt $expectedSize) {
                throw ('Received archive is larger than expected: {0} > {1}' -f $currentSize, $expectedSize)
            }
            if ($currentSize -eq $expectedSize) {
                Start-Sleep -Seconds 2
                $currentSize = (Get-Item -LiteralPath $Archive).Length
                if ($currentSize -eq $expectedSize) {
                    $ready = $true
                    break
                }
            }
        }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) {
        throw ('SCP timeout: file did not reach expected size within {0} seconds' -f $TimeoutSeconds)
    }

    Log 'SCP byte count matched; checking SHA-256.'
    $actualHash = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -cne $ExpectedHash) {
        throw ('SHA-256 mismatch. Expected {0}, actual {1}' -f $ExpectedHash, $actualHash)
    }
    Log ('SHA-256 verified: {0}' -f $actualHash)

    # TTPMACRO may start 32-bit PowerShell under WOW64. Use Sysnative if needed.
    $tarCandidates = @(
        (Join-Path $env:WINDIR 'Sysnative\tar.exe'),
        (Join-Path $env:WINDIR 'System32\tar.exe')
    )
    $tarExe = $null
    foreach ($candidate in $tarCandidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $tarExe = $candidate
            break
        }
    }
    if (-not $tarExe) {
        $tarCommand = Get-Command tar.exe -ErrorAction SilentlyContinue
        if ($null -ne $tarCommand) { $tarExe = $tarCommand.Source }
    }
    if (-not $tarExe) { throw 'Windows tar.exe could not be found.' }

    $perfFolder = Join-Path $OutputDirectory 'perf'
    if (Test-Path -LiteralPath $perfFolder) {
        throw 'Destination perf already exists: refusing to overwrite it.'
    }
    Log ('Extracting archive with {0}' -f $tarExe)
    & $tarExe -xzf $Archive -C $OutputDirectory
    if ($LASTEXITCODE -ne 0) {
        throw ('tar.exe extraction failed, exit code {0}' -f $LASTEXITCODE)
    }
    if (-not (Test-Path -LiteralPath $perfFolder -PathType Container)) {
        throw 'Archive extraction completed, but perf folder was not found.'
    }

    # Include files AND directories in this CSV (empty directories are tracked).
    # FileHashes can be added later for a content-level incremental sync workflow.
    $items = @(Get-ChildItem -LiteralPath $perfFolder -Force -Recurse -ErrorAction Stop)
    $manifest = foreach ($item in $items) {
        $relative = $item.FullName.Substring($perfFolder.Length).TrimStart([char]'\')
        [pscustomobject]@{
            RelativePath        = ('perf\' + $relative)
            EntryType           = $(if ($item.PSIsContainer) { 'Directory' } else { 'File' })
            SizeBytes           = $(if ($item.PSIsContainer) { $null } else { $item.Length })
            LastWriteTimeUtc    = $item.LastWriteTimeUtc.ToString('o')
        }
    }
    $manifestPath = Join-Path $OutputDirectory 'manifest.csv'
    if ($manifest.Count -gt 0) {
        $manifest | Sort-Object RelativePath | Export-Csv -LiteralPath $manifestPath -Encoding UTF8 -NoTypeInformation
    }
    else {
        # The root perf directory itself can be empty.
        '"RelativePath","EntryType","SizeBytes","LastWriteTimeUtc"' |
            Set-Content -LiteralPath $manifestPath -Encoding UTF8
    }

    Log ('Extracted {0} nested entries into {1}' -f $items.Count, $perfFolder)
    Log ('Manifest written: {0}' -f $manifestPath)
    exit 0
}
catch {
    try { Log ('ERROR: ' + $_.Exception.Message) } catch { }
    exit 1
}