# Private Runner Setup Guide

This guide documents two approaches for running GitHub Actions on a runner with private Azure VNet access. Both approaches result in a runner that can access internal resources (IIS deployment VMs, Azure Blob Storage) via private networking.

## Option A: Self-Hosted Runner on Azure VM

**Best for:** Any GitHub plan (Free, Team, Enterprise). Full control over the runner environment.

### Prerequisites

- Azure Windows VM (Server 2019/2022) on the same VNet/subnet as IIS deployment VMs
- Visual Studio Build Tools 2022 with `.NET Framework 4.8 targeting pack` and `Web development build tools` workloads
- PowerShell 7+ (`pwsh`) installed and on PATH (all workflow scripts use `shell: pwsh`)
- NuGet CLI, Azure CLI installed and on PATH

### Setup Steps

1. GitHub repo → Settings → Actions → Runners → "New self-hosted runner" → Windows / x64
2. On the Azure VM (PowerShell as Admin):

```powershell
mkdir C:\actions-runner && cd C:\actions-runner
Invoke-WebRequest -Uri https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-win-x64-2.321.0.zip -OutFile actions-runner.zip
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory("$PWD\actions-runner.zip", "$PWD")

# Configure with labels matching the workflow runs-on
.\config.cmd --url https://github.com/OWNER/REPO --token YOUR_TOKEN --name vbnet-runner-01 --labels self-hosted,windows,vbnet --work _work

# Install as Windows service
.\svc.cmd install
.\svc.cmd start
```

### Verify

```powershell
Get-Service actions.runner.*
pwsh --version
msbuild -version
nuget help
az version
```

> **Note:** Since tools (MSBuild, NuGet, .NET Framework 4.8) are pre-installed on the VM, the `microsoft/setup-msbuild@v2` and `NuGet/setup-nuget@v2` actions in workflows simply add them to PATH (idempotent).

---

## Option B: GitHub-Hosted Runner with Azure Private Networking

**Best for:** GitHub Enterprise Cloud. Zero runner maintenance — GitHub manages the VM lifecycle.

### Prerequisites

- GitHub Enterprise Cloud subscription
- Azure subscription with a VNet/subnet configured for runner networking
- Network Security Group (NSG) allowing outbound HTTPS to GitHub

### Setup Steps

1. GitHub org → Settings → Actions → Runner groups → Create runner group
2. Select "GitHub-hosted runners" with Azure private networking
3. Configure:
   - **Azure subscription:** Select your subscription
   - **VNet/Subnet:** Choose the subnet with access to IIS deployment VMs
   - **Runner image:** `windows-latest`
   - **Runner group name:** `vbnet-private`
4. In workflows, use:

```yaml
runs-on:
  group: vbnet-private
  labels: [windows-latest]
```

> **Note:** Runners are ephemeral — every job gets a fresh VM. The `microsoft/setup-msbuild@v2` and `NuGet/setup-nuget@v2` steps are essential (tools not pre-installed).

---

## Network Requirements (Both Options)

| Direction | Targets |
|-----------|---------|
| **Outbound** | HTTPS to `github.com`, `*.actions.githubusercontent.com`, `*.blob.core.windows.net` |
| **Inbound** | None required (runner polls GitHub) |
| **Internal** | Access to Azure APIs for blob storage and VM Run Command |

---

## Workflow `runs-on` Configuration

The workflows use `runs-on: [self-hosted, windows, vbnet]` by default (Option A).

For Option B, update to:

```yaml
runs-on:
  group: vbnet-private
  labels: [windows-latest]
```
