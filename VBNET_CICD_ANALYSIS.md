# VB.NET CI/CD Workflow Analysis

This document outlines the steps involved in the VB.NET CI/CD pipeline, detailing the function of each step, where it currently runs, and the operating system requirements. This analysis is intended to help identify opportunities to optimize runner usage (e.g., using Linux runners for deployment orchestration).

## Workflow Step Analysis

| Workflow / Context | Step / Action Name | Function / Purpose | Current Runner | Required OS / Constraints | Key Commands / Tools |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **.github/workflows/vbnet-ci.yml** | **Checkout code** | Checks out the repository source code. | GitHub Runner (Windows) | Any (Git) | `actions/checkout` |
| | **Build with MSBuild** | Composite action to build the application. | GitHub Runner (Windows) | **Windows** (MSBuild req.) | `.github/actions/msbuild-build` |
| *(Inside msbuild-build)* | - Setup MSBuild | Installs/Locates MSBuild tools. | GitHub Runner (Windows) | **Windows** | `microsoft/setup-msbuild@v2` |
| | - Setup NuGet | Installs/Locates NuGet CLI. | GitHub Runner (Windows) | **Windows** | `NuGet/setup-nuget@v2` |
| | - Cache NuGet packages | Caches NuGet packages to speed up builds. | GitHub Runner (Windows) | Any | `actions/cache@v4` |
| | - Restore NuGet packages | Restores project dependencies. | GitHub Runner (Windows) | **Windows** | `nuget restore` |
| | - Build with MSBuild | Compiles the solution using MSBuild. | GitHub Runner (Windows) | **Windows** | `msbuild` |
| | - Repackage as clean flat ZIP | Extracts MSDeploy package, isolates web content, and re-zips. | GitHub Runner (Windows) | Any (PowerShell Core) | `Expand-Archive`, `Compress-Archive` |
| | - Upload build artifacts | Uploads the build output for the CD workflow. | GitHub Runner (Windows) | Any | `actions/upload-artifact@v4` |
| **.github/workflows/vbnet-ci.yml** | **Upload deployment package** | Uploads the final deployment artifact to GitHub Actions. | GitHub Runner (Windows) | Any | `actions/upload-artifact@v4` |
| | **Build summary** | Outputs detailed build summary to the GitHub UI. | GitHub Runner (Windows) | Any (PowerShell Core) | `Out-File` |
| | | | | | |
| **.github/workflows/vbnet-cd.yml** | **Checkout code** | Checks out the repository source code. | GitHub Runner (Windows) | Any (Git) | `actions/checkout@v4` |
| | **Load environment configuration** | Loads environment-specific variables (app-type, VM, IIS config). | GitHub Runner (Windows) | Any | `.github/actions/load-config` |
| | **Azure Login** | Authenticates with Azure using service principal credentials. | GitHub Runner (Windows) | Any (Azure CLI) | `azure/login@v2` |
| | **Download deployment package from CI workflow** | Downloads the artifact from the CI run using custom download action. | GitHub Runner (Windows) | Any | `.github/actions/download-workflow-artifact` |
| | **Find deployment package** | Locates the ZIP file within the downloaded artifact. | GitHub Runner (Windows) | Any (PowerShell Core) | `Get-ChildItem` |
| | **Deploy to IIS** | Composite action to orchestrate deployment via Azure. | GitHub Runner (Windows) | Any (Azure CLI, PowerShell Core) | `.github/actions/iis-deploy` |
| *(Inside iis-deploy)* | - Verify VM is running | Checks if the target Azure VM is running and retrieves public IP. | GitHub Runner (Windows) | Any (Azure CLI) | `az vm show` |
| | - Upload package to blob | Generates SAS URL and uploads the deployment ZIP to Azure Blob Storage (30-min expiry). | GitHub Runner (Windows) | Any (Azure CLI) | `az storage blob upload`, `az storage blob generate-sas` |
| | - Deploy to VM via Run Command | Base64-encodes SAS URL and invokes the `vm-deploy.ps1` script on the target VM via Azure Run Command. | GitHub Runner (Windows) | Any (Azure CLI) | `az vm run-command invoke` |
| | - Cleanup blob storage | Deletes the deployment ZIP from Azure Blob Storage. | GitHub Runner (Windows) | Any (Azure CLI) | `az storage blob delete` |
| | - Health check | Waits 10 seconds, then verifies the application is accessible via Invoke-WebRequest. | GitHub Runner (Windows) | Any (PowerShell Core) | `Invoke-WebRequest` |
| **.github/workflows/vbnet-cd.yml** | **Deployment summary** | Outputs deployment details and status to GitHub UI. | GitHub Runner (Windows) | Any (PowerShell Core) | `Out-File` |
| | | | | | |
| **.github/actions/iis-deploy/vm-deploy.ps1** | **(Entire Script)** | **Executes ON the Target Azure VM via az vm run-command invoke.** | **Target VM (Windows Server)** | **Windows Server (IIS)** | **PowerShell 5.1+** |
| | Decode Package URL | Decodes the base64-encoded SAS URL passed from the action. | Target VM | Windows | `[Convert]::FromBase64String` |
| | Download Package | Downloads the ZIP from Azure Blob Storage via SAS URL. | Target VM | Windows | `Invoke-WebRequest`, `[Net.SecurityProtocolType]::Tls12` |
| | Import IIS Module | Loads IIS administration cmdlets (WebAdministration module). | Target VM | Windows (IIS Enabled) | `Import-Module WebAdministration` |
| | Create/Manage App Pool | Checks state, creates app pool if needed (sets .NET Framework v4.0), stops app pool before deployment. | Target VM | Windows (IIS) | `Get-WebAppPoolState`, `New-WebAppPool`, `Stop-WebAppPool` |
| | Backup | Backs up the current deployment to `C:\Deploy\backups\$AppName`. | Target VM | Windows | `Copy-Item` |
| | Clean & Extract | Clears wwwroot and extracts the clean ZIP package to deployment directory. | Target VM | Windows | `Remove-Item`, `Expand-Archive` |
| | Run Custom Script | Runs an optional app-specific deploy script if it exists on the VM. | Target VM | Windows | `& $DeployScriptPath` |
| | Update IIS App | Removes existing IIS application and creates new one (avoids "path is null" error with spaces in site names). | Target VM | Windows (IIS) | `Get-WebApplication`, `Remove-WebApplication`, `New-WebApplication` |
| | Start App Pool | Starts the application pool after deployment. | Target VM | Windows (IIS) | `Start-WebAppPool` |
| | Rollback Logic | Restores from latest backup in case of failure (only if backup directory exists). | Target VM | Windows | `Copy-Item`, `Get-ChildItem -Directory` |

## Summary of Findings

1.  **Build Workflow (`vbnet-ci.yml`)**: Requires a **Windows Runner** due to the dependency on `msbuild.exe` and legacy `.NET Framework` tools.
2.  **Deploy Workflow (`vbnet-cd.yml`)**: currently runs on a Windows Runner, but the orchestration steps (Azure Login, Blob Upload, VM Run Command) primarily use the Azure CLI (`az`) and PowerShell Core. These steps **could likely run on a Linux Runner** (`ubuntu-latest`) to save Windows build minutes.
3.  **VM Script (`vm-deploy.ps1`)**: Runs entirely inside the Azure VM. This script **must run on Windows Server** (the target environment), but it is decoupled from the GitHub Runner OS. The runner only triggers it via `az vm run-command`.
