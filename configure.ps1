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

function Write-Message {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Emoji,
        [Parameter(Mandatory = $true)]
        [string]$Item,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host "[$Emoji " -NoNewline -ForegroundColor Yellow
    Write-Host $Item -NoNewline -ForegroundColor Blue
    Write-Host "] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}


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
        Write-Message "⚠️" "Line $lineNumber" "Invalid mapping format. Expected 'LOCAL_NAME: TARGET'."
        $hadErrors = $true
        continue
    }

    $localName = $matches['local'].Trim()
    $targetRaw = $matches['target'].Trim()

    if ([string]::IsNullOrWhiteSpace($localName) -or [string]::IsNullOrWhiteSpace($targetRaw)) {
        Write-Message "⚠️" "Line $lineNumber" "Invalid mapping format. Local name or target path is empty."
        $hadErrors = $true
        continue
    }

    if (($targetRaw.StartsWith('"') -and $targetRaw.EndsWith('"')) -or ($targetRaw.StartsWith("'") -and $targetRaw.EndsWith("'"))) {
        $targetRaw = $targetRaw.Substring(1, $targetRaw.Length - 2)
    }

    try {
        $localFullPath = Get-FullPathRelativeToScript -Path $localName
    } catch {
        Write-Message "⚠️" "Line $lineNumber" "Unable to resolve local path '$localName': $($_.Exception.Message)"
        $hadErrors = $true
        continue
    }

    $expandedTarget = [Environment]::ExpandEnvironmentVariables($targetRaw)

    try {
        $targetFullPath = Get-FullPathRelativeToScript -Path $expandedTarget
    } catch {
        Write-Message "⚠️" "Line $lineNumber" "Unable to resolve target path '$targetRaw': $($_.Exception.Message)"
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
            Write-Message "⚠️" "Line $lineNumber" "Unable to get info for target '$targetFullPath': $($_.Exception.Message)"
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
                Write-Message "✅" $localName "Link ok at $targetRaw"
                continue
            }

            try {
                Remove-Item -LiteralPath $targetFullPath -Force
            } catch {
                Write-Message "❌" $localName "Failed to remove existing link '$targetFullPath': $($_.Exception.Message)"
                $hadErrors = $true
                continue
            }

            try {
                Ensure-ParentDirectory -Path $targetFullPath
                New-Item -Path $targetFullPath -ItemType SymbolicLink -Target $localFullPath | Out-Null
                Write-Message "🔁" $localName "Updated link at $targetRaw"
            } catch {
                Write-Message "❌" $localName "Failed to create symbolic link '$targetFullPath': $($_.Exception.Message)"
                $hadErrors = $true
            }

            continue
        }

        if (-not $targetExists) {
            try {
                Ensure-ParentDirectory -Path $targetFullPath
                New-Item -Path $targetFullPath -ItemType SymbolicLink -Target $localFullPath | Out-Null
                Write-Message "➕" $localName "Created link at $targetRaw"
            } catch {
                Write-Message "❌" $localName "Failed to create symbolic link '$targetFullPath': $($_.Exception.Message)"
                $hadErrors = $true
            }

            continue
        }

        Write-Message "⚠️" $localName "Both local and target exist but target is not a symbolic link. Skipped."
        $hadErrors = $true
        continue
    }

    if ($targetExists) {
        if ($targetIsSymlink) {
            Write-Message "⚠️" $localName "Target '$targetRaw' is a symbolic link but local path '$localFullPath' is missing. Skipped."
            $hadErrors = $true
            continue
        }

        try {
            Ensure-ParentDirectory -Path $localFullPath
            Move-Item -LiteralPath $targetFullPath -Destination $localFullPath
            Write-Message "📦" $localName "Moved $targetRaw to local path"
        } catch {
            Write-Message "❌" $localName "Failed to move '$targetFullPath' to '$localFullPath': $($_.Exception.Message)"
            $hadErrors = $true
            continue
        }

        try {
            Ensure-ParentDirectory -Path $targetFullPath
            New-Item -Path $targetFullPath -ItemType SymbolicLink -Target $localFullPath | Out-Null
            Write-Message "➕" $localName "Created link at $targetRaw"
        } catch {
            Write-Message "❌" $localName "Failed to create symbolic link '$targetFullPath': $($_.Exception.Message)"
            $hadErrors = $true
        }

        continue
    }

    try {
        Ensure-ParentDirectory -Path $localFullPath
        if (-not (Test-Path -LiteralPath $localFullPath -PathType Container)) {
            New-Item -ItemType Directory -Path $localFullPath -Force | Out-Null
            Write-Message "📁" $localName "Created local directory"
        }
    } catch {
        Write-Message "❌" $localName "Failed to create directory '$localFullPath': $($_.Exception.Message)"
        $hadErrors = $true
        continue
    }

    try {
        Ensure-ParentDirectory -Path $targetFullPath
        New-Item -Path $targetFullPath -ItemType SymbolicLink -Target $localFullPath | Out-Null
        Write-Message "➕" $localName "Created link at $targetRaw"
    } catch {
        Write-Message "❌" $localName "Failed to create symbolic link '$targetFullPath': $($_.Exception.Message)"
        $hadErrors = $true
    }
}

if ($hadErrors) {
    exit 1
}

exit 0
