# PowerShell deployment script for VB.NET Web Forms application
# This script deploys the application to IIS on Azure Windows VM

param(
    [Parameter(Mandatory=$true)]
    [string]$PackagePath,

    [Parameter(Mandatory=$false)]
    [string]$SiteName = "Default Web Site",

    [Parameter(Mandatory=$false)]
    [string]$AppName = "VBNetApp",

    [Parameter(Mandatory=$false)]
    [string]$AppPoolName = "VBNetAppPool",

    [Parameter(Mandatory=$false)]
    [bool]$CreateBackup = $true,

    [Parameter(Mandatory=$false)]
    [string]$Environment = "Production",

    [Parameter(Mandatory=$false)]
    [hashtable]$ConfigTokens = @{}
)

# Import IIS module
Import-Module WebAdministration -ErrorAction Stop

# Function to write log messages
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

# Function to create backup
function Create-Backup {
    param([string]$SourcePath, [string]$BackupRoot)

    try {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupPath = Join-Path $BackupRoot "backup-$timestamp"

        if (Test-Path $SourcePath) {
            Write-Log "Creating backup at: $backupPath"
            Copy-Item -Path $SourcePath -Destination $backupPath -Recurse -Force
            Write-Log "Backup created successfully"
            return $backupPath
        } else {
            Write-Log "Source path does not exist, skipping backup" "WARN"
            return $null
        }
    } catch {
        Write-Log "Backup failed: $_" "ERROR"
        return $null
    }
}

# Function to stop application pool
function Stop-AppPool {
    param([string]$PoolName)

    try {
        if (Test-Path "IIS:\AppPools\$PoolName") {
            $state = (Get-WebAppPoolState -Name $PoolName).Value
            if ($state -eq "Started") {
                Write-Log "Stopping application pool: $PoolName"
                Stop-WebAppPool -Name $PoolName

                # Wait for app pool to stop
                $timeout = 30
                $elapsed = 0
                while ((Get-WebAppPoolState -Name $PoolName).Value -ne "Stopped" -and $elapsed -lt $timeout) {
                    Start-Sleep -Seconds 1
                    $elapsed++
                }

                if ((Get-WebAppPoolState -Name $PoolName).Value -eq "Stopped") {
                    Write-Log "Application pool stopped successfully"
                } else {
                    Write-Log "Application pool did not stop within timeout" "WARN"
                }
            } else {
                Write-Log "Application pool is already stopped"
            }
        } else {
            Write-Log "Application pool does not exist: $PoolName" "WARN"
        }
    } catch {
        Write-Log "Error stopping application pool: $_" "ERROR"
        throw
    }
}

# Function to start application pool
function Start-AppPool {
    param([string]$PoolName)

    try {
        if (Test-Path "IIS:\AppPools\$PoolName") {
            Write-Log "Starting application pool: $PoolName"
            Start-WebAppPool -Name $PoolName

            # Wait for app pool to start
            $timeout = 30
            $elapsed = 0
            while ((Get-WebAppPoolState -Name $PoolName).Value -ne "Started" -and $elapsed -lt $timeout) {
                Start-Sleep -Seconds 1
                $elapsed++
            }

            if ((Get-WebAppPoolState -Name $PoolName).Value -eq "Started") {
                Write-Log "Application pool started successfully"
            } else {
                Write-Log "Application pool did not start within timeout" "ERROR"
                throw "Application pool failed to start"
            }
        }
    } catch {
        Write-Log "Error starting application pool: $_" "ERROR"
        throw
    }
}

# Function to replace config tokens
function Update-ConfigTokens {
    param([string]$ConfigPath, [hashtable]$Tokens)

    try {
        if (Test-Path $ConfigPath) {
            Write-Log "Updating configuration tokens in: $ConfigPath"
            $content = Get-Content -Path $ConfigPath -Raw

            foreach ($key in $Tokens.Keys) {
                $token = "__$($key.ToUpper())__"
                $value = $Tokens[$key]
                $content = $content -replace [regex]::Escape($token), $value
                Write-Log "Replaced token: $token"
            }

            Set-Content -Path $ConfigPath -Value $content -Force
            Write-Log "Configuration tokens updated successfully"
        } else {
            Write-Log "Config file not found: $ConfigPath" "WARN"
        }
    } catch {
        Write-Log "Error updating config tokens: $_" "ERROR"
        throw
    }
}

# Main deployment logic
try {
    Write-Log "========== Starting Deployment =========="
    Write-Log "Package Path: $PackagePath"
    Write-Log "Site Name: $SiteName"
    Write-Log "App Name: $AppName"
    Write-Log "App Pool Name: $AppPoolName"
    Write-Log "Environment: $Environment"

    # Verify package exists
    if (-not (Test-Path $PackagePath)) {
        throw "Deployment package not found: $PackagePath"
    }

    # Define paths
    $deployPath = "C:\inetpub\wwwroot\$AppName"
    $backupRoot = "C:\Backups\$AppName"

    # Create backup directory if it doesn't exist
    if (-not (Test-Path $backupRoot)) {
        New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null
    }

    # Create application pool if it doesn't exist
    if (-not (Test-Path "IIS:\AppPools\$AppPoolName")) {
        Write-Log "Creating application pool: $AppPoolName"
        New-WebAppPool -Name $AppPoolName
        Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name managedRuntimeVersion -Value "v4.0"
        Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name enable32BitAppOnWin64 -Value $false
    }

    # Stop application pool
    Stop-AppPool -PoolName $AppPoolName

    # Create backup
    if ($CreateBackup) {
        $backupPath = Create-Backup -SourcePath $deployPath -BackupRoot $backupRoot
    }

    # Create deployment directory if it doesn't exist
    if (-not (Test-Path $deployPath)) {
        Write-Log "Creating deployment directory: $deployPath"
        New-Item -Path $deployPath -ItemType Directory -Force | Out-Null
    }

    # Extract deployment package
    Write-Log "Extracting deployment package..."
    if ($PackagePath.EndsWith(".zip")) {
        Expand-Archive -Path $PackagePath -DestinationPath $deployPath -Force
        Write-Log "Package extracted successfully"
    } else {
        # If not a zip, assume it's a directory and copy files
        Copy-Item -Path "$PackagePath\*" -Destination $deployPath -Recurse -Force
        Write-Log "Files copied successfully"
    }

    # Update Web.config with tokens
    $webConfigPath = Join-Path $deployPath "Web.config"
    if ($ConfigTokens.Count -gt 0) {
        Update-ConfigTokens -ConfigPath $webConfigPath -Tokens $ConfigTokens
    }

    # Set environment-specific values
    $envTokens = @{
        "ENVIRONMENT" = $Environment
        "CUSTOM_ERRORS_MODE" = if ($Environment -eq "Production") { "RemoteOnly" } else { "Off" }
        "HTTP_ERRORS_MODE" = if ($Environment -eq "Production") { "DetailedLocalOnly" } else { "Detailed" }
    }
    Update-ConfigTokens -ConfigPath $webConfigPath -Tokens $envTokens

    # Create or update IIS application
    $appPath = "IIS:\Sites\$SiteName\$AppName"
    if (-not (Test-Path $appPath)) {
        Write-Log "Creating IIS application: $AppName"
        New-WebApplication -Name $AppName -Site $SiteName -PhysicalPath $deployPath -ApplicationPool $AppPoolName
    } else {
        Write-Log "Updating existing IIS application: $AppName"
        Set-ItemProperty $appPath -Name physicalPath -Value $deployPath
        Set-ItemProperty $appPath -Name applicationPool -Value $AppPoolName
    }

    # Start application pool
    Start-AppPool -PoolName $AppPoolName

    # Verify deployment
    Write-Log "Verifying deployment..."
    $site = Get-Website -Name $SiteName
    if ($site) {
        Write-Log "Site is running: $($site.State)"
    }

    Write-Log "========== Deployment Completed Successfully =========="
    exit 0

} catch {
    Write-Log "========== Deployment Failed ==========" "ERROR"
    Write-Log "Error: $_" "ERROR"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" "ERROR"

    # Attempt rollback if backup exists
    if ($backupPath -and (Test-Path $backupPath)) {
        Write-Log "Attempting rollback from backup: $backupPath" "WARN"
        try {
            Stop-AppPool -PoolName $AppPoolName
            Remove-Item -Path $deployPath -Recurse -Force -ErrorAction SilentlyContinue
            Copy-Item -Path "$backupPath\*" -Destination $deployPath -Recurse -Force
            Start-AppPool -PoolName $AppPoolName
            Write-Log "Rollback completed" "WARN"
        } catch {
            Write-Log "Rollback failed: $_" "ERROR"
        }
    }

    exit 1
}
