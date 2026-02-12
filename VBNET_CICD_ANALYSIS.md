# VB.NET CI/CD Workflow Analysis

This document outlines the steps involved in the VB.NET CI/CD pipeline, detailing the function of each step, where it currently runs, and the operating system requirements. This analysis is intended to help identify opportunities to optimize runner usage (e.g., using Linux runners for deployment orchestration).

## Workflow Step Analysis

| Workflow / Context | Step / Action Name | Function / Purpose | Current Runner | Required OS / Constraints | Key Commands / Tools |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **.github/workflows/vbnet-ci.yml** | **Checkout code** | Checks out the repository source code. | GitHub Runner (Windows) | Any (Git) | `actions/checkout` |
| | **Build with MSBuild** | Composite action to build the application. | GitHub Runner (Windows) | **Windows** (MSBuild req.) | `.github/actions/msbuild-build` |
| *(Inside msbuild-build)* | - Setup MSBuild | Installs/Locates MSBuild tools. | GitHub Runner (Windows) | **Windows** | `microsoft/setup-msbuild` |
| | - Setup NuGet | Installs/Locates NuGet CLI. | GitHub Runner (Windows) | **Windows** | `NuGet/setup-nuget` |
| | - Restore NuGet packages | Restores project dependencies. | GitHub Runner (Windows) | **Windows** | `nuget restore` |
| | - Build with MSBuild | Compiles the solution using MSBuild. | GitHub Runner (Windows) | **Windows** | `msbuild` |
| | - Repackage as clean flat ZIP | Extracts MSDeploy package, isolates web content, and re-zips. | GitHub Runner (Windows) | Any (PowerShell Core) | `Expand-Archive`, `Compress-Archive` |
| | - Upload build artifacts | Uploads the build output for the CD workflow. | GitHub Runner (Windows) | Any | `actions/upload-artifact` |
| **.github/workflows/vbnet-ci.yml** | **Upload deployment package** | Uploads the final deployment artifact. | GitHub Runner (Windows) | Any | `actions/upload-artifact` |
| | **Build summary** | detailed build summary to the GitHub UI. | GitHub Runner (Windows) | Any (PowerShell Core) | `Out-File` |
| | | | | | |
| **.github/workflows/vbnet-cd.yml** | **Checkout code** | Checks out the repository source code. | GitHub Runner (Windows) | Any (Git) | `actions/checkout` |
| | **Load environment config** | Loads environment-specific variables. | GitHub Runner (Windows) | Any | `.github/actions/load-config` |
| | **Azure Login** | Authenticates with Azure. | GitHub Runner (Windows) | Any (Azure CLI) | `azure/login` |
| | **Download deployment package** | Downloads the artifact from the CI run. | GitHub Runner (Windows) | Any | `actions/download-artifact` |
| | **Find deployment package** | Locates the ZIP file within the downloaded artifact. | GitHub Runner (Windows) | Any (PowerShell Core) | `Get-ChildItem` |
| | **Deploy to IIS** | Composite action to orchestrate deployment. | GitHub Runner (Windows) | Any (Azure CLI) | `.github/actions/iis-deploy` |
| *(Inside iis-deploy)* | - Verify VM is running | Checks if the target Azure VM is running. | GitHub Runner (Windows) | Any (Azure CLI) | `az vm show` |
| | - Upload package to blob | Uploads the deployment ZIP to Azure Blob Storage. | GitHub Runner (Windows) | Any (Azure CLI) | `az storage blob upload` |
| | - Deploy to VM via Run Command | Triggers the `vm-deploy.ps1` script on the target VM. | GitHub Runner (Windows) | Any (Azure CLI) | `az vm run-command invoke` |
| | - Cleanup blob storage | Deletes the deployment ZIP from storage. | GitHub Runner (Windows) | Any (Azure CLI) | `az storage blob delete` |
| | - Health check | Verifies the application is accessible after deploy. | GitHub Runner (Windows) | Any (PowerShell Core) | `Invoke-WebRequest` |
| **.github/workflows/vbnet-cd.yml** | **Deployment summary** | Writes deployment details to GitHub UI. | GitHub Runner (Windows) | Any (PowerShell Core) | `Out-File` |
| | | | | | |
| **.github/actions/iis-deploy/vm-deploy.ps1** | **(Entire Script)** | **Executes ON the Target Azure VM.** | **Target VM (Windows Server)** | **Windows Server (IIS)** | **PowerShell 5.1+** |
| | Decode Package URL | Decodes the SAS URL passed from the runner. | Target VM | Windows | `[Convert]::FromBase64String` |
| | Download Package | Downloads the ZIP from Blob Storage. | Target VM | Windows | `Invoke-WebRequest` |
| | Import IIS Module | Loads IIS administration cmdlets. | Target VM | Windows (IIS Enabled) | `Import-Module WebAdministration` |
| | Manage App Pool | Checks state, creates, stops, or starts the App Pool. | Target VM | Windows (IIS) | `Get-WebAppPoolState`, `Stop-WebAppPool` |
| | Backup | Backs up the current deployment. | Target VM | Windows | `Copy-Item` |
| | Clean & Extract | Clears wwwroot and extracts the new package. | Target VM | Windows | `Expand-Archive` |
| | Run Custom Script | Runs an optional app-specific deploy script. | Target VM | Windows | `& $DeployScriptPath` |
| | Update IIS App | Updates or creates the IIS Application. | Target VM | Windows (IIS) | `New-WebApplication` |
| | Rollback Logic | Restores from backup in case of failure. | Target VM | Windows | `Copy-Item` |

## Summary of Findings

1.  **Build Workflow (`vbnet-ci.yml`)**: Requires a **Windows Runner** due to the dependency on `msbuild.exe` and legacy `.NET Framework` tools.
2.  **Deploy Workflow (`vbnet-cd.yml`)**: currently runs on a Windows Runner, but the orchestration steps (Azure Login, Blob Upload, VM Run Command) primarily use the Azure CLI (`az`) and PowerShell Core. These steps **could likely run on a Linux Runner** (`ubuntu-latest`) to save Windows build minutes.
3.  **VM Script (`vm-deploy.ps1`)**: Runs entirely inside the Azure VM. This script **must run on Windows Server** (the target environment), but it is decoupled from the GitHub Runner OS. The runner only triggers it via `az vm run-command`.
