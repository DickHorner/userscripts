<#
.SYNOPSIS
    Restores all files from the Recycle Bin to their original locations using robocopy.

.DESCRIPTION
    This script silently restores all files from the Windows Recycle Bin using robocopy,
    avoiding the GUI dialogs that freeze the system. It allows selecting which drives' 
    Recycle Bins to restore from, and can run as a background job. Uses robocopy for
    fast, silent, multi-threaded file operations.

.PARAMETER Background
    Run the restoration as a background job. Returns job object for monitoring.

.PARAMETER LogPath
    Path to the log file. Optional - enables logging if specified.

.PARAMETER NoDialog
    Skip the interactive dialog and use command-line parameters only.

.PARAMETER Drives
    Specific drive letters to restore from (e.g., 'C','D'). If not specified, dialog allows selection.

.EXAMPLE
    .\Restore-RecycleBin.ps1
    Displays interactive dialog to select drives and options.

.EXAMPLE
    .\Restore-RecycleBin.ps1 -Background
    Runs as background job with interactive dialog setup.

.EXAMPLE
    .\Restore-RecycleBin.ps1 -NoDialog -Drives C,D -LogPath C:\recovery.log
    Restores C: and D: drives without dialog, with logging.

.NOTES
    Version:        3.0
    Author:         https://gist.github.com/DickHorner/
    Creation Date:  2025-12-07
    
    Requirements:
    - Windows PowerShell 5.1 or PowerShell 7+
    - Administrator privileges (required to access Recycle Bin)
    - robocopy (built-in on Windows)
    
    Features:
    - Silent operation using robocopy (no GUI dialogs)
    - Multi-drive selection
    - Optional logging
    - Background job support
    - Non-blocking execution
    - Files recovered to \RecycleBin_Recovery on each drive
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Background,
    
    [Parameter(Mandatory = $false)]
    [string]$LogPath,
    
    [Parameter(Mandatory = $false)]
    [switch]$NoDialog,
    
    [Parameter(Mandatory = $false)]
    [char[]]$Drives
)

#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AvailableDrives {
    <#
    .SYNOPSIS
        Gets list of available drives with Recycle Bin contents.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()
    
    $drives = @()
    
    foreach ($drive in Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:' }) {
        $driveLetter = $drive.Name
        $recycleBinPath = "$($driveLetter):\`$RECYCLE.BIN"
        
        if (Test-Path -Path $recycleBinPath -ErrorAction SilentlyContinue) {
            try {
                $itemCount = @(Get-ChildItem -Path $recycleBinPath -Force -ErrorAction SilentlyContinue | 
                    Where-Object { $_.PSIsContainer -eq $false }).Count
                
                if ($itemCount -gt 0) {
                    $drives += [PSCustomObject]@{
                        Drive    = "$driveLetter`:"
                        Path     = $recycleBinPath
                        Items    = $itemCount
                        Selected = $false
                    }
                }
            }
            catch {
                # Skip drives we can't access
            }
        }
    }
    
    return $drives
}

function Show-RestoreDialog {
    <#
    .SYNOPSIS
        Displays an interactive dialog for restoration options.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    Clear-Host
    
    # ASCII art header
    $artLines = @'
 ╔══════════════════════════════════════════════════════════════════════════╗
 ║                                                                          ║
 ║                    ⚡ RECYCLE BIN RESTORATION TOOL ⚡                      ║
 ║                      Silent Robocopy-Based Restore                       ║
 ║                                                                          ║
 ╚══════════════════════════════════════════════════════════════════════════╝
'@ -split "`n"
    
    foreach ($line in $artLines) {
        Write-Host $line -ForegroundColor Cyan
    }
    
    Write-Host ""
    
    # Get available drives
    Write-Host "Scanning for Recycle Bin contents..." -ForegroundColor Yellow
    $availableDrives = Get-AvailableDrives
    
    if ($availableDrives.Count -eq 0) {
        Write-Host ""
        Write-Host "✗ No items found in any Recycle Bin." -ForegroundColor Green
        Write-Host ""
        Write-Host "Press any key to exit..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        exit 0
    }
    
    Write-Host "✓ Found items in $($availableDrives.Count) drive(s):" -ForegroundColor Green
    Write-Host ""
    
    # Display available drives
    $selectedDrives = @()
    foreach ($idx in 0..($availableDrives.Count - 1)) {
        $drive = $availableDrives[$idx]
        Write-Host "   [$($idx + 1)] $($drive.Drive) - $($drive.Items) item(s)" -ForegroundColor White
    }
    
    Write-Host ""
    Write-Host "Select drives to restore (comma-separated, e.g., 1,2 or 'all')" -ForegroundColor Yellow -NoNewline
    Write-Host " [all]: " -ForegroundColor DarkGray -NoNewline
    $driveSelection = Read-Host
    
    if ([string]::IsNullOrWhiteSpace($driveSelection) -or $driveSelection -eq 'all') {
        $selectedDrives = $availableDrives
    } else {
        $selections = $driveSelection -split ',' | ForEach-Object { $_.Trim() }
        foreach ($sel in $selections) {
            if ($sel -match '^\d+$') {
                $idx = [int]$sel - 1
                if ($idx -ge 0 -and $idx -lt $availableDrives.Count) {
                    $selectedDrives += $availableDrives[$idx]
                }
            }
        }
    }
    
    if ($selectedDrives.Count -eq 0) {
        Write-Host ""
        Write-Host "No drives selected. Exiting." -ForegroundColor Yellow
        exit 0
    }
    
    Write-Host ""
    
    # Logging preference
    Write-Host "1. Logging" -ForegroundColor Cyan
    Write-Host "   ───────" -ForegroundColor DarkGray
    Write-Host "   [1] Enable logging (recommended)" -ForegroundColor White
    Write-Host "   [2] No logging" -ForegroundColor White
    Write-Host ""
    
    do {
        Write-Host "   Select option (1-2) [1]: " -ForegroundColor Yellow -NoNewline
        $logInput = Read-Host
        if ([string]::IsNullOrWhiteSpace($logInput)) { $logInput = "1" }
        $validLog = $logInput -match '^[12]$'
        if (-not $validLog) {
            Write-Host "   Invalid input. Please enter 1 or 2." -ForegroundColor Red
        }
    } while (-not $validLog)
    
    $enableLogging = ($logInput -eq "1")
    $logPath = $null
    
    if ($enableLogging) {
        Write-Host ""
        $defaultLog = Join-Path $env:TEMP "RecycleBinRestore_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        Write-Host "   Log file location" -ForegroundColor Cyan
        Write-Host "   Default: $defaultLog" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "   Press ENTER for default or specify custom path: " -ForegroundColor Yellow -NoNewline
        $customLog = Read-Host
        
        $logPath = if ([string]::IsNullOrWhiteSpace($customLog)) {
            $defaultLog
        } else {
            try {
                $parentDir = Split-Path -Path $customLog -Parent
                if ($parentDir -and -not (Test-Path $parentDir)) {
                    New-Item -Path $parentDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
                }
                $customLog
            }
            catch {
                Write-Host "   Invalid path. Using default." -ForegroundColor Yellow
                $defaultLog
            }
        }
    }
    
    Write-Host ""
    
    # Execution mode
    Write-Host "2. Execution Mode" -ForegroundColor Cyan
    Write-Host "   ──────────────" -ForegroundColor DarkGray
    Write-Host "   [1] Foreground (shows progress, blocks terminal)" -ForegroundColor White
    Write-Host "   [2] Background job (returns immediately)" -ForegroundColor White
    Write-Host ""
    
    do {
        Write-Host "   Select mode (1-2) [2]: " -ForegroundColor Yellow -NoNewline
        $modeInput = Read-Host
        if ([string]::IsNullOrWhiteSpace($modeInput)) { $modeInput = "2" }
        $validMode = $modeInput -match '^[12]$'
        if (-not $validMode) {
            Write-Host "   Invalid input. Please enter 1 or 2." -ForegroundColor Red
        }
    } while (-not $validMode)
    
    $backgroundMode = ($modeInput -eq "2")
    Write-Host ""
    
    # Summary
    Write-Host "────────────────────────────────────────────────────────" -ForegroundColor Yellow
    Write-Host "Configuration Summary" -ForegroundColor Yellow
    Write-Host "────────────────────────────────────────────────────────" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Drives to restore:   " -ForegroundColor White -NoNewline
    Write-Host ($selectedDrives.Drive -join ', ') -ForegroundColor Green
    Write-Host "  Total items:         " -ForegroundColor White -NoNewline
    Write-Host ($selectedDrives | Measure-Object -Property Items -Sum).Sum -ForegroundColor Green
    Write-Host "  Logging:             " -ForegroundColor White -NoNewline
    Write-Host $(if ($enableLogging) { "Enabled - $logPath" } else { "Disabled" }) -ForegroundColor Green
    Write-Host "  Execution:           " -ForegroundColor White -NoNewline
    Write-Host $(if ($backgroundMode) { "Background Job" } else { "Foreground" }) -ForegroundColor Green
    Write-Host ""
    Write-Host "────────────────────────────────────────────────────────" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Proceed with restoration? [Y/n]: " -ForegroundColor Green -NoNewline
    $confirm = Read-Host
    
    if ($confirm -and $confirm -notmatch '^[Yy]') {
        Write-Host ""
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        exit 0
    }
    
    Write-Host ""
    Write-Host "⚡ Starting restoration..." -ForegroundColor Green
    Write-Host ""
    
    return @{
        Background      = $backgroundMode
        LogPath         = $logPath
        Drives          = $selectedDrives
        EnableLogging   = $enableLogging
    }
}

# Script block for background execution
$restorationScriptBlock = {
    param(
        [PSCustomObject[]]$Drives,
        [string]$LogPath,
        [bool]$EnableLogging
    )
    
    $ErrorActionPreference = 'Stop'
    
    function Write-Log {
        param(
            [string]$Message,
            [ValidateSet('Info', 'Success', 'Warning', 'Error')]
            [string]$Level = 'Info'
        )
        
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $logMessage = "[$timestamp] [$Level] $Message"
        
        Write-Output $logMessage
        
        if ($using:EnableLogging -and $using:LogPath) {
            Add-Content -Path $using:LogPath -Value $logMessage -ErrorAction SilentlyContinue
        }
    }
    
    Write-Log "=== Recycle Bin Restoration Started ===" -Level Info
    Write-Log "Using robocopy for silent file transfer" -Level Info
    
    $totalFiles = 0
    $successCount = 0
    $failCount = 0
    $startTime = Get-Date
    
    foreach ($driveInfo in $using:Drives) {
        Write-Log "Processing: $($driveInfo.Drive)" -Level Info
        Write-Output "Processing $($driveInfo.Drive)..."
        
        $recycleBinPath = $driveInfo.Path
        
        if (-not (Test-Path -Path $recycleBinPath)) {
            Write-Log "Recycle Bin not found on $($driveInfo.Drive)" -Level Warning
            continue
        }
        
        try {
            # Get all files in Recycle Bin
            $files = @(Get-ChildItem -Path $recycleBinPath -File -Force -Recurse -ErrorAction SilentlyContinue)
            
            if ($files.Count -eq 0) {
                Write-Log "No files found in $($driveInfo.Drive) Recycle Bin" -Level Info
                continue
            }
            
            Write-Log "Found $($files.Count) files in $($driveInfo.Drive)" -Level Info
            $totalFiles += $files.Count
            
            # Create recovery folder on the drive
            $recoveryRoot = "$($driveInfo.Drive)\RecycleBin_Recovery"
            
            if (-not (Test-Path -Path $recoveryRoot)) {
                New-Item -Path $recoveryRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            
            # Process each file
            foreach ($file in $files) {
                try {
                    $fileName = $file.Name
                    $sourceDir = $file.DirectoryName
                    
                    # Use robocopy for the copy operation
                    $robocopyArgs = @(
                        $sourceDir,
                        $recoveryRoot,
                        $fileName,
                        '/NP',  # No progress (no percentage display)
                        '/NS',  # No size
                        '/NC',  # No class
                        '/NFL', # No file list
                        '/NDL', # No directory list
                        '/NJH', # No job header
                        '/NJS'  # No job summary
                    )
                    
                    $output = & robocopy @robocopyArgs 2>&1
                    $exitCode = $LASTEXITCODE
                    
                    # Robocopy exit codes: 0-7 are success, 8+ are errors
                    if ($exitCode -le 7) {
                        Write-Log "Restored: $fileName" -Level Success
                        $successCount++
                    } else {
                        Write-Log "Failed to restore: $fileName (robocopy exit code: $exitCode)" -Level Error
                        $failCount++
                    }
                }
                catch {
                    Write-Log "Error processing file '$fileName': $_" -Level Error
                    $failCount++
                }
            }
        }
        catch {
            Write-Log "Error accessing $($driveInfo.Drive): $_" -Level Error
        }
    }
    
    $duration = ((Get-Date) - $startTime).TotalSeconds
    
    Write-Log "=== Restoration Complete ===" -Level Info
    Write-Log "Total files processed: $totalFiles" -Level Info
    Write-Log "Successfully restored: $successCount" -Level Success
    Write-Log "Failed: $failCount" -Level Warning
    Write-Log "Duration: $([Math]::Round($duration, 2)) seconds" -Level Info
    Write-Log "Recovery folder: \RecycleBin_Recovery on each drive" -Level Info
    
    Write-Output ""
    Write-Output "Restoration complete:"
    Write-Output "  Total: $totalFiles | Success: $successCount | Failed: $failCount"
    Write-Output "  Recovered files are in \RecycleBin_Recovery on each drive"
    
    return [PSCustomObject]@{
        TotalFiles   = $totalFiles
        Success      = $successCount
        Failed       = $failCount
        Duration     = [Math]::Round($duration, 2)
        LogPath      = $using:LogPath
    }
}

# Main execution
try {
    # Show interactive dialog if no command-line parameters provided
    if (-not $NoDialog -and -not $PSBoundParameters.ContainsKey('Drives')) {
        $dialogResult = Show-RestoreDialog
        $Background = $dialogResult.Background
        $LogPath = $dialogResult.LogPath
        $selectedDrives = $dialogResult.Drives
        $enableLogging = $dialogResult.EnableLogging
    } else {
        # Command-line mode
        $enableLogging = [bool]$LogPath
        
        if ([string]::IsNullOrEmpty($LogPath)) {
            $LogPath = Join-Path $env:TEMP "RecycleBinRestore_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        }
        
        if ($Drives -and $Drives.Count -gt 0) {
            $availableDrives = Get-AvailableDrives
            $drivesPattern = $Drives | ForEach-Object { [regex]::Escape("$_`:") } | Join-String -Separator '|'
            $selectedDrives = $availableDrives | Where-Object { $_.Drive -match "^($drivesPattern)$" }
            
            if ($selectedDrives.Count -eq 0) {
                Write-Error "No specified drives found with Recycle Bin items."
                exit 1
            }
        } else {
            $selectedDrives = Get-AvailableDrives
            
            if ($selectedDrives.Count -eq 0) {
                Write-Host "No Recycle Bin items found." -ForegroundColor Yellow
                exit 0
            }
        }
    }
    
    Write-Host ""
    Write-Host "Recycle Bin Restoration (Robocopy)" -ForegroundColor Cyan
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host ""
    
    if ($Background) {
        # Start as background job
        Write-Host "Starting restoration as background job..." -ForegroundColor Green
        if ($enableLogging) {
            Write-Host "Log file: $LogPath" -ForegroundColor Yellow
        }
        Write-Host ""
        
        $job = Start-Job -ScriptBlock $restorationScriptBlock -ArgumentList $selectedDrives, $LogPath, $enableLogging
        
        Write-Host "Background job started (ID: $($job.Id))" -ForegroundColor Green
        Write-Host ""
        
        if ($enableLogging) {
            Write-Host "Monitor progress with:" -ForegroundColor Cyan
            Write-Host "  Get-Content '$LogPath' -Wait" -ForegroundColor White
            Write-Host ""
        }
        
        Write-Host "Check job status with:" -ForegroundColor Cyan
        Write-Host "  Get-Job -Id $($job.Id)" -ForegroundColor White
        Write-Host ""
        Write-Host "Retrieve results with:" -ForegroundColor Cyan
        Write-Host "  Receive-Job -Id $($job.Id) -Wait -AutoRemoveJob" -ForegroundColor White
        Write-Host ""
        
        return $job
    } else {
        # Run in foreground
        Write-Host "Running restoration in foreground..." -ForegroundColor Green
        Write-Host ""
        
        $result = & $restorationScriptBlock $selectedDrives $LogPath $enableLogging
        
        Write-Host ""
        Write-Host "Restoration Summary:" -ForegroundColor Cyan
        Write-Host "  Total files:  $($result.TotalFiles)" -ForegroundColor White
        Write-Host "  Successful:   $($result.Success)" -ForegroundColor Green
        Write-Host "  Failed:       $($result.Failed)" -ForegroundColor Yellow
        Write-Host "  Duration:     $($result.Duration) seconds" -ForegroundColor White
        
        if ($enableLogging) {
            Write-Host "  Log file:     $($result.LogPath)" -ForegroundColor White
        }
        
        Write-Host ""
        Write-Host "Recovered files are in \RecycleBin_Recovery on each drive." -ForegroundColor Yellow
        Write-Host ""
    }
}
catch {
    Write-Error "Fatal error: $_"
    Write-Error $_.ScriptStackTrace
    exit 1
}