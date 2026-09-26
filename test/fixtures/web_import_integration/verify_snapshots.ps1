$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$entries = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'snapshots.json') -Raw | ConvertFrom-Json
foreach ($entry in $entries) {
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repoRoot $entry.path)).Hash.ToLowerInvariant()
    if ($actual -ne $entry.sha256) { throw "Snapshot integrity failure: $($entry.id)" }
}
Write-Output "Snapshot integrity: $($entries.Count)/$($entries.Count) PASS"
