# This script runs ON the target VM via az vm run-command invoke.
# Config variables ($PackageUrlBase64, $AppPoolName, $SiteName, $AppName,
# $DeployScriptPath, $Environment) are prepended by the action before execution.

$ErrorActionPreference = 'Stop'

try {
    # Decode the base64-encoded URL
    $PackageUrl = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($PackageUrlBase64))
    Write-Host "Package URL decoded successfully"

    # Create deploy directory
    $deployDir = 'C:\Deploy'
    if (-not (Test-Path $deployDir)) {
        New-Item -Path $deployDir -ItemType Directory -Force | Out-Null
    }

    # Download the package
    $packagePath = Join-Path $deployDir 'VBNetApp.zip'
    Write-Host "Downloading package from Azure Blob Storage..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $PackageUrl -OutFile $packagePath -UseBasicParsing
    Write-Host "Package downloaded to: $packagePath"

    # Import IIS module
    Import-Module WebAdministration -ErrorAction Stop

    # Define paths
    $wwwRoot = "C:\inetpub\wwwroot\$AppName"
    $backupDir = "C:\Deploy\backups\$AppName"

    Write-Host "Site: $SiteName | App: $AppName | Pool: $AppPoolName"
    Write-Host "Web root: $wwwRoot"

    # Create app pool if it doesn't exist
    $existingPool = Get-WebAppPoolState -Name $AppPoolName -ErrorAction SilentlyContinue
    if (-not $existingPool) {
        Write-Host "Creating application pool: $AppPoolName"
        New-WebAppPool -Name $AppPoolName
        Set-ItemProperty -Path "IIS:\AppPools\$AppPoolName" -Name managedRuntimeVersion -Value "v4.0"
    }

    # Stop app pool if running
    $poolState = (Get-WebAppPoolState -Name $AppPoolName -ErrorAction SilentlyContinue).Value
    if ($poolState -eq "Started") {
        Write-Host "Stopping application pool..."
        Stop-WebAppPool -Name $AppPoolName
        Start-Sleep -Seconds 5
    }

    # Create backup of current deployment
    if (Test-Path $wwwRoot) {
        if (-not (Test-Path $backupDir)) {
            New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
        }
        $backupName = "backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        $backupPath = Join-Path $backupDir $backupName
        Write-Host "Creating backup: $backupPath"
        Copy-Item -Path $wwwRoot -Destination $backupPath -Recurse -Force
    }

    # Create or clean deployment directory
    if (-not (Test-Path $wwwRoot)) {
        New-Item -Path $wwwRoot -ItemType Directory -Force | Out-Null
    } else {
        Remove-Item -Path "$wwwRoot\*" -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Extract clean ZIP directly to wwwRoot (flat structure, no nested MSDeploy paths)
    Write-Host "Extracting deployment package to: $wwwRoot"
    Expand-Archive -Path $packagePath -DestinationPath $wwwRoot -Force

    # List deployed files for verification
    Write-Host "Deployed files:"
    Get-ChildItem -Path $wwwRoot -Recurse -File | Select-Object -First 20 | ForEach-Object { Write-Host "  $($_.Name)" }

    # Run custom deploy script if it exists on the VM
    if ($DeployScriptPath -and (Test-Path $DeployScriptPath)) {
        Write-Host "Running custom deploy script: $DeployScriptPath"
        & $DeployScriptPath -AppName $AppName -AppPoolName $AppPoolName -SiteName $SiteName -Environment $Environment -WebRoot $wwwRoot
    }

    # Create/update IIS application
    # Use Get-WebApplication instead of Test-Path on IIS: paths (unreliable with spaces in site names).
    # Use Remove + New instead of Set-ItemProperty (IIS provider throws "path is null" on sites with spaces).
    $existingApp = Get-WebApplication -Name $AppName -Site $SiteName -ErrorAction SilentlyContinue
    if ($existingApp) {
        Write-Host "Removing existing IIS application for update..."
        Remove-WebApplication -Name $AppName -Site $SiteName
    }
    Write-Host "Creating IIS application: $AppName on site $SiteName"
    New-WebApplication -Name $AppName -Site $SiteName -PhysicalPath $wwwRoot -ApplicationPool $AppPoolName

    # Start app pool
    Write-Host "Starting application pool..."
    Start-WebAppPool -Name $AppPoolName

    # Cleanup downloaded package
    Remove-Item -Path $packagePath -Force -ErrorAction SilentlyContinue

    Write-Host "Deployment Completed Successfully!"
} catch {
    # Switch to SilentlyContinue BEFORE Write-Error so it doesn't re-throw
    # under $ErrorActionPreference='Stop' and skip the rollback.
    $ErrorActionPreference = 'SilentlyContinue'
    Write-Host "ERROR: Deployment failed: $_"

    # Attempt rollback from backup
    if ($wwwRoot -and (Test-Path "C:\Deploy\backups\$AppName")) {
        $latestBackup = Get-ChildItem -Path "C:\Deploy\backups\$AppName" -Directory |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latestBackup) {
            Write-Host "Rolling back to: $($latestBackup.FullName)"
            if (Test-Path $wwwRoot) {
                Remove-Item -Path "$wwwRoot\*" -Recurse -Force
            }
            Copy-Item -Path "$($latestBackup.FullName)\*" -Destination $wwwRoot -Recurse -Force
            # Restore IIS application if it was removed during failed update
            $existingApp = Get-WebApplication -Name $AppName -Site $SiteName -ErrorAction SilentlyContinue
            if (-not $existingApp -and $AppName -and $SiteName) {
                New-WebApplication -Name $AppName -Site $SiteName -PhysicalPath $wwwRoot -ApplicationPool $AppPoolName
            }
            Start-WebAppPool -Name $AppPoolName
            Write-Host "Rollback completed"
        }
    }

    exit 1
}
