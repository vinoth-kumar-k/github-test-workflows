# CI/CD Pipeline Design Document

## Modern .NET Core & Legacy VB.NET Workflows

| Field            | Value                                      |
|------------------|--------------------------------------------|
| **Document Version** | 1.0                                    |
| **Last Updated**     | 2026-02-11                             |
| **Status**           | Active                                 |
| **Scope**            | GitHub Actions CI/CD for two application stacks |

---

## Table of Contents

1. [Overview](#1-overview)
2. [System Context](#2-system-context)
3. [Application Profiles](#3-application-profiles)
4. [Pipeline Architecture](#4-pipeline-architecture)
5. [Modern .NET Core Pipeline](#5-modern-net-core-pipeline)
6. [Legacy VB.NET Pipeline](#6-legacy-vbnet-pipeline)
7. [Shared Components](#7-shared-components)
8. [Infrastructure Design](#8-infrastructure-design)
9. [Security Design](#9-security-design)
10. [Environment Strategy](#10-environment-strategy)
11. [Artifact Management](#11-artifact-management)
12. [Comparison Matrix](#12-comparison-matrix)
13. [Failure Handling & Rollback](#13-failure-handling--rollback)
14. [Known Limitations & Future Considerations](#14-known-limitations--future-considerations)

---

## 1. Overview

### 1.1 Purpose

This document describes the design of two parallel CI/CD pipelines implemented via GitHub Actions. The pipelines serve two fundamentally different application stacks that share a single repository:

- **Modern .NET Core 9.0 Web API** -- containerized with Docker, deployed to Azure Kubernetes Service (AKS).
- **Legacy VB.NET ASP.NET Web Forms (.NET Framework 4.8)** -- built with MSBuild, packaged as a Web Deploy zip, deployed to IIS on an Azure Windows VM.

Both pipelines follow a CI/CD separation pattern where the CI workflow produces a deployable artifact and the CD workflow consumes it, triggered automatically via `workflow_run` or manually via `workflow_dispatch`.

### 1.2 Design Goals

| Goal | Approach |
|------|----------|
| Separation of concerns | Distinct CI and CD workflow files per application |
| Reusability | Shared composite GitHub Actions under `.github/actions/` |
| Environment parity | Centralized YAML config (`environments.yml`) drives per-environment values |
| Secure secrets handling | Azure Key Vault as the single source of truth; only `AZURE_CREDENTIALS` stored in GitHub |
| Minimal runner cost | Linux runners for .NET Core; Windows runners only where MSBuild is required |
| Zero open ports for VM deploy | Azure VM Run Command replaces WinRM |

---

## 2. System Context

```
+-------------------+          +--------------------+
|   Developer       |          | GitHub Repository  |
|  (push / PR)      +--------->| (main / develop)   |
+-------------------+          +---------+----------+
                                         |
                        +----------------+----------------+
                        |                                 |
              +---------v----------+          +-----------v--------+
              | .NET Core CI       |          | VB.NET CI          |
              | (ubuntu-latest)    |          | (windows-latest)   |
              +---------+----------+          +-----------+--------+
                        |                                 |
              +---------v----------+          +-----------v--------+
              | .NET Core CD       |          | VB.NET CD          |
              | (ubuntu-latest)    |          | (windows-latest)   |
              +---------+----------+          +-----------+--------+
                        |                                 |
              +---------v----------+          +-----------v--------+
              | Azure Kubernetes   |          | Azure Windows VM   |
              | Service (AKS)      |          | + IIS              |
              +--------------------+          +--------------------+
```

---

## 3. Application Profiles

### 3.1 Modern .NET Core Application

| Attribute | Value |
|-----------|-------|
| **Project** | `src/DotNetCoreApp/DotNetCoreApp.sln` |
| **Framework** | .NET 9.0 |
| **Type** | ASP.NET Core Web API |
| **Build tool** | `dotnet` CLI |
| **Test project** | `src/DotNetCoreApp/DotNetCoreApp.Tests/DotNetCoreApp.Tests.csproj` |
| **Container base** | `mcr.microsoft.com/dotnet/aspnet:9.0` |
| **Runtime port** | 8080 (non-privileged) |
| **Dependencies** | `Microsoft.AspNetCore.OpenApi` v9.0.8 |

### 3.2 Legacy VB.NET Application

| Attribute | Value |
|-----------|-------|
| **Project** | `src/VBNetApp/VBNetApp.sln` |
| **Framework** | .NET Framework 4.8 |
| **Type** | ASP.NET Web Forms |
| **Build tool** | MSBuild (via `microsoft/setup-msbuild@v2`) |
| **Language** | Visual Basic .NET |
| **Output** | Web Deploy package (.zip) |
| **Runtime** | IIS with .NET CLR v4.0, 64-bit app pool |
| **Page** | `Default.aspx` (Web Forms) |

---

## 4. Pipeline Architecture

### 4.1 High-Level Flow

Both pipelines follow the same structural pattern:

```
Trigger --> CI Workflow --> Artifact --> CD Workflow --> Target Environment
```

However, the implementation details diverge significantly due to the different technology stacks.

### 4.2 Trigger Design

Both CI workflows share the same trigger configuration:

| Trigger | Condition | Behavior |
|---------|-----------|----------|
| `push` | Branches `main`, `develop`, `master` with path filters | Runs full CI; CD triggered automatically on `main`/`master` |
| `pull_request` | Target `main` or `master` with path filters | CI only (build + test), no CD |
| `workflow_dispatch` | Manual | CI with optional environment selection (.NET Core) or default run (VB.NET) |

**Path filters** scope each workflow to its own source directory:
- .NET Core: `src/DotNetCoreApp/**`, related workflow/action files
- VB.NET: `src/VBNetApp/**`, related workflow/action files

CD workflows trigger on:

| Trigger | Condition |
|---------|-----------|
| `workflow_run` | Corresponding CI workflow completes successfully on `main`/`master` |
| `workflow_dispatch` | Manual with optional override (image tag for .NET Core, run ID for VB.NET) |

### 4.3 Job Dependency Graph

**.NET Core CI:**
```
build-and-test  ──>  build-and-push-to-acr
   (required)         (conditional: push or dispatch only)
```

**.NET Core CD:**
```
deploy-dev
   (standalone, with environment gate)
```

**VB.NET CI:**
```
build  ──>  test (disabled)  ──>  package
              (if: false)         (creates deployment artifact)
```

**VB.NET CD:**
```
deploy-dev
   (standalone, with environment gate)
```

---

## 5. Modern .NET Core Pipeline

### 5.1 CI Workflow (`dotnet-core-ci.yml`)

**Runner:** `ubuntu-latest`

**Environment variables:**
```yaml
DOTNET_VERSION: '9.0.x'
PROJECT_PATH: 'src/DotNetCoreApp/DotNetCoreApp.sln'
TEST_PATH: 'src/DotNetCoreApp/DotNetCoreApp.Tests/DotNetCoreApp.Tests.csproj'
DOCKER_BUILD_CONTEXT: 'src/DotNetCoreApp'
DOCKERFILE_PATH: 'src/DotNetCoreApp/DotNetCoreApp/Dockerfile'
IMAGE_NAME: 'dotnetcore-app'
```

#### Job 1: Build and Test

| Step | Action / Command | Purpose |
|------|-----------------|---------|
| Checkout | `actions/checkout@v4` | Clone repository |
| Build | `dotnet-build` composite action | Restore NuGet, build Release |
| Test | `dotnet-test` composite action | Run xUnit tests, collect XPlat Code Coverage |

The `dotnet-build` action:
1. Sets up .NET SDK via `actions/setup-dotnet@v4`
2. Caches NuGet packages keyed on `runner.os` + hash of `*.csproj` / `*.vbproj` files
3. Runs `dotnet restore` then `dotnet build --configuration Release --no-restore`

The `dotnet-test` action:
1. Runs `dotnet test` with TRX logger and optional XPlat Code Coverage
2. Uploads test results (`.trx`) and coverage reports (`coverage.cobertura.xml`) as artifacts with 30-day retention

#### Job 2: Build and Push to ACR

Conditional on: `github.event_name == 'push' || github.event_name == 'workflow_dispatch'`

| Step | Action / Command | Purpose |
|------|-----------------|---------|
| Determine environment | Shell script | Resolves target environment from dispatch input or defaults to `dev` |
| Load config | `load-config` composite action | Reads `environments.yml` for ACR name, AKS cluster, etc. |
| Azure Login | `azure/login@v2` | Authenticates with `AZURE_CREDENTIALS` service principal |
| Generate Version | Shell script | Creates `1.0.0-<short-sha>` semantic version |
| Setup Docker Buildx | `docker/setup-buildx-action@v3` | Enables multi-platform / advanced builds |
| ACR Login | `az acr login` | Authenticates Docker to Azure Container Registry |
| Extract metadata | `docker/metadata-action@v5` | Generates tags: `latest` (default branch), `ref/branch`, `branch-sha`, semver |
| Build and push | `docker/build-push-action@v5` | Multi-stage Docker build with GitHub Actions cache (`type=gha`) |
| Output summary | Shell script | Writes image tags, digest, and version to `GITHUB_STEP_SUMMARY` |

**Docker image tagging strategy:**
```
latest                       (only on default branch)
<branch>                     (branch name)
<branch>-<short-sha>        (branch + commit)
1.0.0-<short-sha>           (semantic version)
```

**Outputs propagated to CD:**
- `image-tag` -- full tag list
- `image-digest` -- content-addressable digest
- `image-version` -- semantic version string

### 5.2 CD Workflow (`dotnet-core-cd.yml`)

**Runner:** `ubuntu-latest`

| Step | Action / Command | Purpose |
|------|-----------------|---------|
| Checkout | `actions/checkout@v4` | Required for composite action access |
| Load config | `load-config` composite action | Reads AKS cluster name, namespace, ACR, resource group |
| Determine image tag | Shell script | Uses dispatch input override or constructs `<branch>-<short-sha>` |
| Azure Login | `azure/login@v2` | Authenticates service principal |
| Set AKS context | `azure/aks-set-context@v4` | Configures kubectl for the target cluster |
| Setup kubelogin | `azure/use-kubelogin@v1` | Installs kubelogin for AAD-integrated clusters |
| Convert kubeconfig | `kubelogin convert-kubeconfig -l spn` | Converts kubeconfig to use service principal authentication |
| Deploy manifests | `envsubst` + `kubectl apply` | Substitutes `${IMAGE}`, `${NAMESPACE}`, `${ENVIRONMENT}` in K8s manifests |
| Wait for rollout | `kubectl rollout status` | Waits up to 300s for deployment completion |
| Summary | `kubectl get pods/svc` | Outputs pod and service status to step summary |

**Kubernetes manifests:**

The deployment (`k8s/dotnetcoreapp/deployment.yaml`) specifies:
- 2 replicas with `RollingUpdate` strategy (`maxSurge: 1`, `maxUnavailable: 0`)
- Resource requests: 128Mi memory, 100m CPU
- Resource limits: 256Mi memory, 250m CPU
- Startup probe: `/health` (5s delay, 5s interval, 10 retries)
- Liveness probe: `/health/live` (15s delay, 20s interval, 3 retries)
- Readiness probe: `/health/ready` (5s delay, 10s interval, 3 retries)

The service (`k8s/dotnetcoreapp/service.yaml`) exposes a `ClusterIP` service mapping port 80 to container port 8080.

### 5.3 Dockerfile Design

The Dockerfile uses a three-stage multi-stage build:

| Stage | Base Image | Purpose |
|-------|-----------|---------|
| **build** | `dotnet/sdk:9.0` | Restore and build |
| **publish** | Inherits from build | Publish with `UseAppHost=false` |
| **runtime** | `dotnet/aspnet:9.0` | Minimal runtime image |

Security measures in the runtime stage:
- Non-root user `appuser` (UID/GID 1000)
- Non-privileged port 8080
- File ownership set to `appuser`
- Built-in `HEALTHCHECK` instruction for container orchestrators

---

## 6. Legacy VB.NET Pipeline

### 6.1 CI Workflow (`vbnet-ci.yml`)

**Runner:** `windows-latest` (required for MSBuild and .NET Framework)

**Environment variables:**
```yaml
SOLUTION_PATH: 'src/VBNetApp/VBNetApp.sln'
BUILD_CONFIGURATION: 'Release'
BUILD_PLATFORM: 'Any CPU'
```

#### Job 1: Build

| Step | Action / Command | Purpose |
|------|-----------------|---------|
| Checkout | `actions/checkout@v4` | Clone repository |
| Build with MSBuild | `msbuild-build` composite action | NuGet restore, MSBuild, Web Deploy package creation |
| Display artifacts | PowerShell | Lists generated artifacts for verification |

The `msbuild-build` action:
1. Sets up MSBuild via `microsoft/setup-msbuild@v2`
2. Sets up NuGet via `NuGet/setup-nuget@v2`
3. Caches NuGet packages keyed on `runner.os` + hash of `*.config` / `*.sln` files
4. Runs `nuget restore`
5. Runs MSBuild with:
   - `/maxcpucount` for parallel compilation
   - `/verbosity:minimal`
   - `/p:DeployOnBuild=true` + `/p:WebPublishMethod=Package` + `/p:PackageAsSingleFile=true` to create a Web Deploy `.zip`
6. Uploads build output and `.zip` package with 30-day retention

#### Job 2: Test (Disabled)

A placeholder job with `if: false` exists for future VSTest integration. It would:
1. Set up MSBuild and VSTest
2. Download build artifacts
3. Execute tests

#### Job 3: Package

| Step | Action / Command | Purpose |
|------|-----------------|---------|
| Download artifacts | `actions/download-artifact@v4` | Retrieves build output from Job 1 |
| Prepare package | PowerShell | Locates `.zip` and validates existence / size |
| Upload package | `actions/upload-artifact@v4` | Stores as `deployment-package-<sha>` with 90-day retention |
| Summary | PowerShell | Writes configuration, platform, and commit to step summary |

### 6.2 CD Workflow (`vbnet-cd.yml`)

**Runner:** `windows-latest`

This is the most complex workflow in the system. It orchestrates a multi-step deployment to an Azure Windows VM running IIS, using Azure Blob Storage as a transfer mechanism and Azure VM Run Command for remote execution.

#### Deployment Steps (Sequential)

| # | Step | Purpose |
|---|------|---------|
| 1 | **Load config** | Read VM name, resource group, storage account, IIS settings from `environments.yml` |
| 2 | **Azure Login** | Authenticate with `AZURE_CREDENTIALS` |
| 3 | **Download artifact** | Retrieve deployment `.zip` from the CI workflow using `dawidd6/action-download-artifact@v3` (cross-workflow artifact download) |
| 4 | **Find package** | PowerShell script searches `./deployment-artifacts` for `.zip` files |
| 5 | **Verify VM** | Queries VM power state via `az vm show -d`; extracts public IP; constructs app URL; fails if VM is not running |
| 6 | **Upload to Blob Storage** | Retrieves storage account key, generates unique blob name with timestamp, creates container if needed, uploads `.zip`, verifies blob exists, generates SAS URL (30-minute expiry), base64-encodes URL for safe parameter passing |
| 7 | **Deploy to VM** | Creates inline PowerShell deployment script and executes it on the VM via `az vm run-command invoke` |
| 8 | **Cleanup blob** | Deletes the uploaded package from blob storage (runs `always()`) |
| 9 | **Health check** | HTTP GET to application URL after 10-second delay |
| 10 | **Summary** | Writes VM, resource group, app name, URL, and status to step summary |

#### VM Deployment Script (Step 7 Detail)

The inline script executed on the VM performs:

1. **Decode** base64-encoded SAS URL
2. **Download** package from Azure Blob Storage via `Invoke-WebRequest`
3. **Import** IIS `WebAdministration` module
4. **Create app pool** if it doesn't exist (CLR v4.0)
5. **Stop app pool** if running (with 3-second grace period)
6. **Clean or create** the `wwwroot\<AppName>` directory
7. **Extract** zip to temporary location
8. **Locate web content** by searching for `web.config` in the extracted tree (handles nested MSDeploy structure)
9. **Copy** content to deployment directory
10. **Create or update** IIS application under the default web site
11. **Start** app pool
12. **Verify** by listing deployed files

#### Standalone Deployment Script (`deploy.ps1`)

A more comprehensive PowerShell script exists at `src/VBNetApp/deployment/deploy.ps1` for use with the `azure-vm-deploy` composite action. It adds:

- **Parameterized inputs**: `PackagePath`, `SiteName`, `AppName`, `AppPoolName`, `CreateBackup`, `Environment`, `ConfigTokens`
- **Timestamped logging** with severity levels (INFO, WARN, ERROR)
- **Backup creation** before deployment with timestamped directory
- **App pool management** with 30-second timeout on stop/start operations
- **Web.config token replacement** using `__TOKEN__` pattern (e.g., `__CONNECTION_STRING__`, `__ENVIRONMENT__`)
- **Environment-specific config**: automatically sets `CUSTOM_ERRORS_MODE` and `HTTP_ERRORS_MODE` based on environment
- **Automatic rollback** from backup on deployment failure

---

## 7. Shared Components

### 7.1 Composite Actions

Five reusable composite actions live under `.github/actions/`:

| Action | Used By | Runner | Purpose |
|--------|---------|--------|---------|
| `dotnet-build` | .NET Core CI | Linux | Build with `dotnet` CLI, NuGet caching |
| `dotnet-test` | .NET Core CI | Linux | Test execution with optional coverage |
| `msbuild-build` | VB.NET CI | Windows | MSBuild with Web Deploy packaging |
| `load-config` | All CI/CD workflows | Any | Parse `environments.yml` via Python + PyYAML |
| `azure-vm-deploy` | VB.NET CD (alternative) | Windows | Full VM deployment with Key Vault, backup, health check |

### 7.2 Environment Configuration (`environments.yml`)

A single YAML file at `.github/config/environments.yml` provides all environment-specific parameters. The `load-config` action parses it using a Python script and outputs values to `$GITHUB_OUTPUT`.

**Structure:**
```yaml
<environment>:            # dev / staging / prod
  key-vault-name: <name>  # Shared across app types
  dotnet-core:            # .NET Core specific
    acr-name: <fqdn>
    aks-cluster: <name>
    resource-group: <name>
    namespace: <k8s-ns>
    image-tag-suffix: <suffix>
  vbnet:                  # VB.NET specific
    vm-name: <name>
    resource-group: <name>
    storage-account: <name>
    storage-container: <name>
    iis-site: <name>
    iis-app-name: <name>
    iis-app-pool: <name>
```

**Current environment status:**
- `dev`: Fully configured with real Azure resource names
- `staging`: Placeholder values
- `prod`: Placeholder values

---

## 8. Infrastructure Design

### 8.1 .NET Core Infrastructure (AKS)

The .NET Core application targets a pre-existing AKS cluster. Infrastructure provisioning for AKS is not in scope of this repository.

**Azure resources consumed:**
- Azure Container Registry (`akssandboxacr.azurecr.io`)
- AKS cluster (`aks-sandbox-cluster`) in resource group `rg-vinoth`
- Kubernetes namespace `dev`

### 8.2 VB.NET Infrastructure (Terraform)

The VB.NET VM infrastructure is codified in Terraform under `terraform/vbnet-vm/`.

**Terraform configuration:**
- Required Terraform version: `>= 1.0`
- Provider: `azurerm ~> 3.0`
- Uses an existing resource group (`rg-vinoth`)

**Resources provisioned:**

| Resource | Name | Details |
|----------|------|---------|
| Virtual Network | `vnet-vbnet` | Address space `10.1.0.0/16` |
| Subnet | `snet-vbnet` | Prefix `10.1.1.0/24` |
| NSG | `nsg-vm-vbnet-dev` | Rules: RDP (3389), HTTP (80), HTTPS (443) |
| Public IP | `pip-vm-vbnet-dev` | Static, Standard SKU |
| Network Interface | `nic-vm-vbnet-dev` | Dynamic private IP + public IP |
| Windows VM | `vm-vbnet-dev` | Windows Server 2022 Datacenter Azure Edition, `Standard_B2s_v2` |
| Storage Account | `stvbnetdeploy` | Standard LRS, TLS 1.2, 7-day soft delete |
| Storage Container | `deployments` | Private access |

**VM configuration:**
- OS disk: StandardSSD_LRS, 127 GB
- Boot diagnostics enabled
- System-assigned managed identity (for VM Run Command)
- Custom Script Extension installs: IIS, ASP.NET 4.5, Management Console, Scripting Tools
- Creates `C:\Deploy` and `C:\Backups` directories

**Terraform outputs** include a `github_actions_config` object with values that map directly to `environments.yml` entries, bridging infrastructure provisioning to CI/CD configuration.

---

## 9. Security Design

### 9.1 Secrets Management

```
GitHub Secrets                Azure Key Vault
+---------------------+      +--------------------------+
| AZURE_CREDENTIALS   |----->| Service Principal auth   |
| (single JSON blob)  |      |                          |
+---------------------+      | kv-dev / kv-staging /    |
                              | kv-prod                  |
                              |   - connection-strings   |
                              |   - api-keys             |
                              |   - ACR credentials      |
                              +--------------------------+
```

**Principle:** Only one secret (`AZURE_CREDENTIALS`) is stored in GitHub. All application secrets are fetched from Azure Key Vault at runtime, reducing the GitHub secret surface area and centralizing rotation.

### 9.2 Authentication Methods

| Component | Auth Method |
|-----------|------------|
| Azure CLI | Service principal via `AZURE_CREDENTIALS` JSON |
| ACR | `az acr login` (token-based, via Azure CLI session) |
| AKS | Service principal via `kubelogin` (SP-to-AAD) |
| Blob Storage | Storage account key retrieved at runtime |
| VM Run Command | Azure CLI session (Azure-native, no VM credentials needed) |

### 9.3 Container Security

- Non-root user execution (`appuser`, UID 1000)
- Non-privileged port (8080)
- `UseAppHost=false` -- no self-contained executable, reducing image size

### 9.4 Network Security

- NSG rules restrict RDP to `allowed_rdp_ips` (configurable, defaults to `*` -- should be restricted in production)
- HTTP/HTTPS open for IIS application access
- VM Run Command requires no open inbound ports (uses Azure control plane)
- AKS service uses `ClusterIP` (not externally exposed by default)

---

## 10. Environment Strategy

### 10.1 Environment Definitions

| Environment | .NET Core Target | VB.NET Target | Approval |
|-------------|-----------------|---------------|----------|
| `dev` | AKS namespace `dev` | VM `vm-vbnet-dev` / IIS `VBNetApp-Dev` | None (auto-deploy) |
| `staging` | AKS namespace `staging` | VM `vm-staging` / IIS `VBNetApp-Staging` | 1 reviewer |
| `prod` | AKS namespace `production` | VM `vm-prod` / IIS `VBNetApp` | 2 reviewers + wait timer |

### 10.2 GitHub Environments

CD workflows use the `environment: dev` property, which enables:
- Environment protection rules (approval gates)
- Environment-scoped secrets (if needed)
- Deployment history tracking in the GitHub UI

### 10.3 Configuration Flow

```
environments.yml  -->  load-config action  -->  $GITHUB_OUTPUT  -->  workflow steps
```

The `load-config` action uses Python with PyYAML to parse the config file. It outputs both environment-level values (e.g., `key-vault-name`) and app-type-specific values (e.g., `acr-name` or `vm-name`).

---

## 11. Artifact Management

### 11.1 .NET Core Artifacts

| Artifact | Storage | Retention | Format |
|----------|---------|-----------|--------|
| Test results | GitHub Artifacts | 30 days | `.trx` (TRX format) |
| Coverage reports | GitHub Artifacts | 30 days | `coverage.cobertura.xml` |
| Docker image | Azure Container Registry | ACR policy | Multi-tagged OCI image |

**Docker image tags generated per build:**
- `latest` (default branch only)
- `<branch>` (branch name)
- `<branch>-<short-sha>` (branch + 7-char commit hash)
- `1.0.0-<short-sha>` (semantic version)

**Docker cache:** GitHub Actions cache (`type=gha,mode=max`) for layer reuse.

### 11.2 VB.NET Artifacts

| Artifact | Storage | Retention | Format |
|----------|---------|-----------|--------|
| Build output | GitHub Artifacts | 30 days | Binaries (bin/Release) |
| Deployment package | GitHub Artifacts | 90 days | Web Deploy `.zip` |
| Staging blob | Azure Blob Storage | ~30 minutes (cleaned up) | `.zip` |

**Artifact naming:** `deployment-package-<full-sha>` for unique identification.

**Cross-workflow artifact transfer:** Uses `dawidd6/action-download-artifact@v3` to download artifacts from the CI workflow run into the CD workflow.

---

## 12. Comparison Matrix

| Dimension | .NET Core Pipeline | VB.NET Pipeline |
|-----------|--------------------|-----------------|
| **CI Runner** | `ubuntu-latest` | `windows-latest` |
| **CD Runner** | `ubuntu-latest` | `windows-latest` |
| **Build Tool** | `dotnet` CLI | MSBuild |
| **Package Format** | Docker image (OCI) | Web Deploy `.zip` |
| **Artifact Registry** | Azure Container Registry | GitHub Artifacts + Azure Blob (transient) |
| **Deploy Target** | AKS (Kubernetes) | Azure Windows VM (IIS) |
| **Deploy Mechanism** | `kubectl apply` with `envsubst` | Azure VM Run Command + PowerShell |
| **Scaling** | Horizontal (K8s replicas) | Vertical (VM resize) |
| **Health Checks** | K8s probes (startup, liveness, readiness) | HTTP GET after delay |
| **Rollback** | K8s rollout undo | PowerShell backup restore |
| **Test Framework** | xUnit / dotnet test | VSTest (placeholder) |
| **Code Coverage** | XPlat Code Coverage (Cobertura) | Not implemented |
| **Secret Injection** | K8s env vars / secrets | Web.config token replacement |
| **TLS/HTTPS** | Ingress controller (external) | Not configured (HTTP only) |
| **Caching** | NuGet + Docker layers (GHA cache) | NuGet packages |
| **CI Workflow File** | `dotnet-core-ci.yml` (162 lines) | `vbnet-ci.yml` (127 lines) |
| **CD Workflow File** | `dotnet-core-cd.yml` (123 lines) | `vbnet-cd.yml` (441 lines) |

---

## 13. Failure Handling & Rollback

### 13.1 .NET Core

| Failure Point | Behavior |
|---------------|----------|
| Build failure | CI job fails, no image pushed, CD not triggered |
| Test failure | CI job fails, no image pushed, CD not triggered |
| Docker push failure | CI job fails, CD not triggered |
| K8s deployment failure | `kubectl rollout status` times out (300s); deployment stays in previous state due to `maxUnavailable: 0` |
| Manual rollback | `kubectl rollout undo deployment/dotnetcoreapp` (not automated) |

The `RollingUpdate` strategy with `maxUnavailable: 0` ensures at least the current number of pods remain available during any deployment. If new pods fail health checks, the old pods continue serving traffic.

### 13.2 VB.NET

| Failure Point | Behavior |
|---------------|----------|
| Build failure | CI job fails, no artifact uploaded, CD not triggered |
| Package not found | CD skips deployment steps (conditional `if` guards) |
| VM not running | CD fails at VM check step |
| Blob upload failure | CD fails with error |
| VM deployment failure | `deploy.ps1` catches exception, attempts rollback from backup, exits with code 1 |
| Health check failure | Warning only (non-blocking); application may still be starting |
| Blob cleanup | Runs `always()` regardless of deployment outcome |

The standalone `deploy.ps1` script provides automatic rollback:
1. Before deployment, creates a timestamped backup in `C:\Backups\<AppName>\`
2. On failure, stops the app pool, restores from backup, and restarts
3. If rollback itself fails, logs the error (manual intervention required)

---

## 14. Known Limitations & Future Considerations

### 14.1 Current Limitations

| Area | Limitation |
|------|-----------|
| **VB.NET testing** | Test job is disabled (`if: false`); no automated tests run |
| **Staging/prod environments** | Configuration uses placeholder values; not deployable |
| **HTTPS for VB.NET** | IIS health checks use HTTP only; no TLS certificate provisioning |
| **Concurrency control** | No `concurrency` groups defined; parallel runs could conflict |
| **Job timeouts** | No explicit `timeout-minutes` set on jobs |
| **GITHUB_TOKEN permissions** | No explicit `permissions` block; defaults to broad access |
| **Action pinning** | Actions referenced by tag (`@v4`) rather than SHA; vulnerable to tag mutation |
| **RDP access** | NSG allows RDP from `*` by default; should be restricted |
| **Single-VM deployment** | No load balancing or blue-green for VB.NET |
| **Image versioning** | Semantic version is static `1.0.0-<sha>` with no auto-increment |

### 14.2 Future Considerations

| Area | Consideration |
|------|--------------|
| **Reusable workflows** | Convert CI workflows to `workflow_call` for cross-repo reuse |
| **Matrix builds** | Support multiple .NET versions or target frameworks |
| **Integration tests** | Add post-deployment integration/smoke tests |
| **Blue-green deployment** | Use deployment slots or dual VMs for VB.NET zero-downtime deploys |
| **HTTPS everywhere** | Provision TLS certificates for the IIS VM; configure HTTPS redirect |
| **Monitoring integration** | Add Application Insights or Prometheus metrics collection |
| **Approval gates** | Implement staging and production approval workflows |
| **Cost optimization** | Use VM auto-shutdown schedules for non-production VMs |
| **Multi-region** | Extend AKS deployment to multiple regions with traffic manager |

---

## Appendix A: File Inventory

```
.github/
├── actions/
│   ├── azure-vm-deploy/action.yml     (282 lines)
│   ├── dotnet-build/action.yml        (63 lines)
│   ├── dotnet-test/action.yml         (82 lines)
│   ├── load-config/action.yml         (108 lines)
│   └── msbuild-build/action.yml       (120 lines)
├── config/
│   └── environments.yml               (50 lines)
└── workflows/
    ├── dotnet-core-cd.yml             (123 lines)
    ├── dotnet-core-ci.yml             (162 lines)
    ├── vbnet-cd.yml                   (441 lines)
    └── vbnet-ci.yml                   (127 lines)

src/
├── DotNetCoreApp/
│   ├── DotNetCoreApp.sln
│   ├── DotNetCoreApp/
│   │   ├── DotNetCoreApp.csproj       (net9.0)
│   │   └── Dockerfile                 (50 lines, 3-stage)
│   └── DotNetCoreApp.Tests/
│       └── DotNetCoreApp.Tests.csproj
└── VBNetApp/
    ├── VBNetApp.sln
    ├── VBNetApp/
    │   └── VBNetApp.vbproj            (.NET Framework 4.8)
    └── deployment/
        └── deploy.ps1                 (268 lines)

k8s/dotnetcoreapp/
├── deployment.yaml                    (62 lines)
└── service.yaml                       (17 lines)

terraform/vbnet-vm/
├── main.tf                            (201 lines)
├── variables.tf                       (82 lines)
└── outputs.tf                         (69 lines)
```

## Appendix B: GitHub Actions Dependencies

| Action | Version | Used In |
|--------|---------|---------|
| `actions/checkout` | v4 | All workflows |
| `actions/cache` | v4 | dotnet-build, msbuild-build |
| `actions/upload-artifact` | v4 | dotnet-test, msbuild-build, vbnet-ci |
| `actions/download-artifact` | v4 | vbnet-ci |
| `actions/setup-dotnet` | v4 | dotnet-build |
| `azure/login` | v2 | All CD workflows, .NET Core CI |
| `azure/aks-set-context` | v4 | .NET Core CD |
| `azure/use-kubelogin` | v1 | .NET Core CD |
| `docker/setup-buildx-action` | v3 | .NET Core CI |
| `docker/metadata-action` | v5 | .NET Core CI |
| `docker/build-push-action` | v5 | .NET Core CI |
| `microsoft/setup-msbuild` | v2 | msbuild-build |
| `NuGet/setup-nuget` | v2 | msbuild-build |
| `dawidd6/action-download-artifact` | v3 | VB.NET CD |
