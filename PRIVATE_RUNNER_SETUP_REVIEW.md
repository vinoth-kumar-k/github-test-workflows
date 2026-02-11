# Review of Private Runner Setup Guide

**Reference Document:** `docs/private-runner-setup.md`
**Review Date:** 2024-05-21

## 1. Executive Summary
The document provides a clear and concise guide for setting up private runners for Azure-connected workflows. It correctly identifies the two primary patterns: **Self-Hosted Runners on Azure VMs** and **GitHub-Hosted Runners with VNet Injection**.

**Verdict:** The document is **suitable as a reference** for implementation, provided the optimizations and security notes below are addressed.

## 2. Strengths
- **Clear Options:** Distinctly separates "Self-Hosted" (control/cost) vs. "GitHub-Hosted" (convenience/enterprise).
- **Network Requirements:** Explicitly lists the required outbound connectivity, which is the most common blocker in private setups.
- **Verification Steps:** Includes practical commands (`pwsh --version`, `msbuild -version`) to validate the environment.

## 3. Optimizations and Improvements

### 3.1. Runner Version Management (Self-Hosted)
**Current:**
The script hardcodes the runner version: `actions-runner-win-x64-2.321.0.zip`.

**Issue:**
This link will become outdated quickly. Using an old runner version may miss security patches or features.

**Recommendation:**
Update the script to fetch the latest version dynamically using the GitHub API, or instruct the user to check the "Add Runner" UI in GitHub for the latest download link.
```powershell
# Example of dynamic fetch (optional optimization)
$latest = Invoke-RestMethod -Uri "https://api.github.com/repos/actions/runner/releases/latest"
$url = $latest.assets | Where-Object { $_.name -like "*win-x64*.zip" } | Select-Object -ExpandProperty browser_download_url
```

### 3.2. Token Security and Lifecycle
**Current:**
`.\config.cmd --url ... --token YOUR_TOKEN`

**Issue:**
The token generated in the "Add Runner" UI is time-limited (expires in ~1 hour).

**Recommendation:**
Add a note clarifying that `YOUR_TOKEN` is a temporary registration token found in the GitHub UI, not a Personal Access Token (PAT).

### 3.3. Tooling Installation Clarity
**Current:**
States that `microsoft/setup-msbuild` "simply add them to PATH".

**Optimization:**
This is a critical point. Ensure the "Prerequisites" section emphasizes that **Visual Studio Build Tools** must be installed *before* the runner service starts. If the runner service starts before the tools are installed, it might not pick up the environment variables (though `setup-msbuild` usually handles looking up the registry).

### 3.4. Network Connectivity for Artifacts
**Current:**
Lists `*.blob.core.windows.net` as a requirement.

**Optimization:**
Explicitly link this requirement to the **`iis-deploy` action**.
*   **Context:** The `iis-deploy` action uploads the deployment ZIP to Azure Blob Storage to bypass VM Run Command script size limits.
*   **Requirement:** The runner *must* have network access to the storage account defined in `.github/config/environments.yml`. If using Private Endpoints for storage, ensure the runner's VNet has the correct DNS resolution.

### 3.5. Workflow Configuration Alignment
**Current:**
Suggests updating workflows to `runs-on: [self-hosted, windows, vbnet]`.

**Optimization:**
Note that the current `vbnet-ci.yml` and `vbnet-cd.yml` use `windows-latest` (GitHub-hosted public runners).
- If the goal is to secure the entire pipeline, **both** CI and CD workflows should be updated.
- If only CD needs private access (to reach the VM), then only `vbnet-cd.yml` needs the self-hosted runner.
- **Clarification:** The `iis-deploy` action uses `az vm run-command`, which works over the Azure Control Plane (public HTTPS). Technically, **a private runner is NOT required** for `iis-deploy` to work, unless the Azure VM ignores Run Commands or the Storage Account is firewalled to reject public traffic. This distinction is crucial:
    - **Scenario A (Public Runner OK):** VM allows Run Command, Storage Account allows public access (with SAS).
    - **Scenario B (Private Runner Required):** Storage Account has "Selected Networks" or Private Endpoint only.

## 4. Missing Components
- **Service Restart:** The guide doesn't mention that if you modify the system `PATH` (e.g., installing new tools), you may need to restart the runner service (`.\svc.cmd stop; .\svc.cmd start`) for it to pick up changes.
- **Scaling:** For Option A (Self-Hosted), there is no mention of auto-scaling. It implies a single static VM. For production, this is a single point of failure.

## 5. Summary of Recommended Edits

| Section | Change | Priority |
| :--- | :--- | :--- |
| **Setup Steps** | Replace hardcoded URL with "Copy URL from GitHub UI" or dynamic script. | High |
| **Prerequisites** | Add "Restart runner service after installing tools". | Medium |
| **Network** | Explain *why* Blob Storage access is needed (deployment artifacts). | Medium |
| **Context** | Clarify that `iis-deploy` via Run Command typically works from Public Runners unless Storage/API is firewalled. | High |
