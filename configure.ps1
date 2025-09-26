param (
    [string]$MappingsPath = (Join-Path -Path $PSScriptRoot -ChildPath 'mappings.txt')
)

Set-StrictMode -Version 3

if (-not (Test-Path -LiteralPath $MappingsPath)) {
    Write-Error "Mappings file not found at '$MappingsPath'."
    exit 1
}

$hadErrors = $false

function Ensure-ParentDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $parent = Split-Path -Path $Path -Parent
    if ([string]::IsNullOrWhiteSpace($parent)) {
        return
    }

    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function Is-SymbolicLink {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileSystemInfo]$Item
    )

    return (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Get-LinkTargetPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LinkPath
    )

    try {
        $targetValue = (Get-Item -LiteralPath $LinkPath -Force).Target
        if ($targetValue -is [System.Array]) {
            $targetValue = $targetValue[0]
        }

        if (-not [string]::IsNullOrWhiteSpace($targetValue)) {
            if ([System.IO.Path]::IsPathRooted($targetValue)) {
                return [System.IO.Path]::GetFullPath($targetValue)
            }

            $linkDirectory = Split-Path -Path $LinkPath -Parent
            $combined = Join-Path -Path $linkDirectory -ChildPath $targetValue
            return [System.IO.Path]::GetFullPath($combined)
        }
    } catch {
        # ignore and fall back to Resolve-Path
    }

    try {
        $resolved = Resolve-Path -LiteralPath $LinkPath -ErrorAction Stop
        return $resolved.ProviderPath
    } catch {
        return $null
    }
}

function Get-FullPathRelativeToScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    $combined = Join-Path -Path $PSScriptRoot -ChildPath $Path
    return [System.IO.Path]::GetFullPath($combined)
}

Write-Host "Processing mappings from '$MappingsPath'." -ForegroundColor Cyan

$lineNumber = 0
foreach ($rawLine in Get-Content -LiteralPath $MappingsPath) {
    $lineNumber++

    $trimmed = $rawLine.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        continue
    }

    $lineWithoutComment = $trimmed
    $commentIndex = $lineWithoutComment.IndexOf('#')
    if ($commentIndex -ge 0) {
        $lineWithoutComment = $lineWithoutComment.Substring(0, $commentIndex).TrimEnd()
    }

    if ([string]::IsNullOrWhiteSpace($lineWithoutComment)) {
        continue
    }

    if ($lineWithoutComment -notmatch '^(?<local>[^:]+):(?<target>.+)$') {
        Write-Warning "[Line $lineNumber] Invalid mapping format. Expected 'LOCAL_NAME: TARGET'."
        $hadErrors = $true
        continue
    }

    $localName = $matches['local'].Trim()
    $targetRaw = $matches['target'].Trim()

    if ([string]::IsNullOrWhiteSpace($localName) -or [string]::IsNullOrWhiteSpace($targetRaw)) {
        Write-Warning "[Line $lineNumber] Mapping must contain both local name and target path."
        $hadErrors = $true
        continue
    }

    if (($targetRaw.StartsWith('"') -and $targetRaw.EndsWith('"')) -or ($targetRaw.StartsWith("'") -and $targetRaw.EndsWith("'"))) {
        $targetRaw = $targetRaw.Substring(1, $targetRaw.Length - 2)
    }

    try {
        $localFullPath = Get-FullPathRelativeToScript -Path $localName
    } catch {
        Write-Warning "[Line $lineNumber] Unable to resolve local path '$localName': $($_.Exception.Message)"
        $hadErrors = $true
        continue
    }

    $expandedTarget = [Environment]::ExpandEnvironmentVariables($targetRaw)

    try {
        $targetFullPath = Get-FullPathRelativeToScript -Path $expandedTarget
    } catch {
        Write-Warning "[Line $lineNumber] Unable to resolve target path '$targetRaw': $($_.Exception.Message)"
        $hadErrors = $true
        continue
    }

    $localExists = Test-Path -LiteralPath $localFullPath -PathType Any
    $targetExists = Test-Path -LiteralPath $targetFullPath -PathType Any

    $targetItem = $null
    $targetIsSymlink = $false
    if ($targetExists) {
        try {
            $targetItem = Get-Item -LiteralPath $targetFullPath -Force
            $targetIsSymlink = Is-SymbolicLink -Item $targetItem
        } catch {
            Write-Warning "[Line $lineNumber] Unable to inspect target '$targetFullPath': $($_.Exception.Message)"
            $hadErrors = $true
            continue
        }
    }

    $targetPointsToLocal = $false
    if ($targetIsSymlink -and $localExists) {
        $resolvedLocal = $null
        try {
            $resolvedLocal = (Resolve-Path -LiteralPath $localFullPath -ErrorAction Stop).ProviderPath
        } catch {
            $resolvedLocal = $localFullPath
        }

        $linkTarget = Get-LinkTargetPath -LinkPath $targetFullPath
        if ($linkTarget) {
            $targetPointsToLocal = ($linkTarget -ieq $resolvedLocal)
        }
    }

    if ($localExists) {
        if ($targetIsSymlink) {
            if ($targetPointsToLocal) {
                Write-Host "[Line $lineNumber] Target '$targetFullPath' already links to '$localFullPath'."
                continue
            }

            try {
                Remove-Item -LiteralPath $targetFullPath -Force
            } catch {
                Write-Warning "[Line $lineNumber] Failed to remove existing link '$targetFullPath': $($_.Exception.Message)"
                $hadErrors = $true
                continue
            }

            try {
                Ensure-ParentDirectory -Path $targetFullPath
                New-Item -Path $targetFullPath -ItemType SymbolicLink -Target $localFullPath | Out-Null
                Write-Host "[Line $lineNumber] Updated symbolic link '$targetFullPath' -> '$localFullPath'."
            } catch {
                Write-Warning "[Line $lineNumber] Failed to create symbolic link '$targetFullPath': $($_.Exception.Message)"
                $hadErrors = $true
            }

            continue
        }

        if (-not $targetExists) {
            try {
                Ensure-ParentDirectory -Path $targetFullPath
                New-Item -Path $targetFullPath -ItemType SymbolicLink -Target $localFullPath | Out-Null
                Write-Host "[Line $lineNumber] Created symbolic link '$targetFullPath' -> '$localFullPath'."
            } catch {
                Write-Warning "[Line $lineNumber] Failed to create symbolic link '$targetFullPath': $($_.Exception.Message)"
                $hadErrors = $true
            }

            continue
        }

        Write-Warning "[Line $lineNumber] Both local '$localFullPath' and target '$targetFullPath' exist but target is not a symbolic link. Skipped."
        $hadErrors = $true
        continue
    }

    if ($targetExists) {
        if ($targetIsSymlink) {
            Write-Warning "[Line $lineNumber] Local path '$localFullPath' is missing while target '$targetFullPath' is a symbolic link. Skipped."
            $hadErrors = $true
            continue
        }

        try {
            Ensure-ParentDirectory -Path $localFullPath
            Move-Item -LiteralPath $targetFullPath -Destination $localFullPath
            Write-Host "[Line $lineNumber] Moved '$targetFullPath' to '$localFullPath'."
        } catch {
            Write-Warning "[Line $lineNumber] Failed to move '$targetFullPath' to '$localFullPath': $($_.Exception.Message)"
            $hadErrors = $true
            continue
        }

        try {
            Ensure-ParentDirectory -Path $targetFullPath
            New-Item -Path $targetFullPath -ItemType SymbolicLink -Target $localFullPath | Out-Null
            Write-Host "[Line $lineNumber] Created symbolic link '$targetFullPath' -> '$localFullPath'."
        } catch {
            Write-Warning "[Line $lineNumber] Failed to create symbolic link '$targetFullPath': $($_.Exception.Message)"
            $hadErrors = $true
        }

        continue
    }

    try {
        Ensure-ParentDirectory -Path $localFullPath
        if (-not (Test-Path -LiteralPath $localFullPath -PathType Container)) {
            New-Item -ItemType Directory -Path $localFullPath -Force | Out-Null
            Write-Host "[Line $lineNumber] Created directory '$localFullPath'."
        }
    } catch {
        Write-Warning "[Line $lineNumber] Failed to create directory '$localFullPath': $($_.Exception.Message)"
        $hadErrors = $true
        continue
    }

    try {
        Ensure-ParentDirectory -Path $targetFullPath
        New-Item -Path $targetFullPath -ItemType SymbolicLink -Target $localFullPath | Out-Null
        Write-Host "[Line $lineNumber] Created symbolic link '$targetFullPath' -> '$localFullPath'."
    } catch {
        Write-Warning "[Line $lineNumber] Failed to create symbolic link '$targetFullPath': $($_.Exception.Message)"
        $hadErrors = $true
    }
}

if ($hadErrors) {
    exit 1
}

exit 0
