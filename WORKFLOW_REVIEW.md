# GitHub Workflows & Actions Review

## Repository Structure

```
.github/
├── workflows/
│   ├── dotnet-core-ci.yml    # CI for .NET Core → Docker → ACR
│   ├── vbnet-ci.yml          # CI for VB.NET (MSBuild)
│   └── vbnet-cd.yml          # CD for VB.NET → Azure VM
├── actions/
│   ├── dotnet-build/         # Composite: .NET build + cache
│   ├── dotnet-test/          # Composite: .NET test + coverage
│   ├── msbuild-build/        # Composite: MSBuild for .NET Framework
│   └── azure-vm-deploy/      # Composite: Deploy to Azure VM
└── config/
    └── environments.yml      # Environment parameters (dev/staging/prod)
```

---

## 1. MODULARITY

### Strengths

- Good use of composite actions to encapsulate build (`dotnet-build`, `msbuild-build`), test (`dotnet-test`), and deploy (`azure-vm-deploy`) logic as reusable units.
- Clear CI/CD separation for the VB.NET pipeline (`vbnet-ci.yml` → `vbnet-cd.yml`), with the CD workflow triggered by `workflow_run`.
- Environment configuration externalized to `environments.yml`.

### Issues

| # | Severity | Location | Finding |
|---|----------|----------|---------|
| M1 | Medium | `vbnet-cd.yml:60-65` | `environments.yml` is loaded but **never parsed**. The step reads the file as raw text and has a comment "In a real workflow, you would parse YAML." Meanwhile, IIS values are **hardcoded** at lines 114-116 instead of sourced from config. |
| M2 | Medium | `dotnet-core-ci.yml` | This workflow combines CI (build+test) **and** Docker push/ACR in a single workflow. The VB.NET pipelines correctly separate CI from CD, but .NET Core does not follow the same pattern. There is no corresponding `dotnet-core-cd.yml`. |
| M3 | Low | `azure-vm-deploy/action.yml:49-54` | The deploy action **re-fetches** Key Vault secrets (`vm-name`, `vm-resource-group`) that are already passed as inputs by the calling workflow. This mixes secret management responsibility into the deployment action. |
| M4 | Low | `vbnet-ci.yml:49-74` | The `test` job is entirely disabled (`if: false`) and contains only placeholder code. Dead code in workflows adds confusion. |

---

## 2. EXTENSIBILITY

### Strengths

- Composite actions have well-parameterized inputs with sensible defaults (e.g., `dotnet-version: '9.0.x'`, `configuration: 'Release'`).
- `workflow_dispatch` inputs allow manual triggering with environment selection.
- Multi-environment config structure in `environments.yml` is forward-looking.

### Issues

| # | Severity | Location | Finding |
|---|----------|----------|---------|
| E1 | Medium | `vbnet-cd.yml:114-116` | IIS configuration (`iis-site-name`, `iis-app-name`, `iis-app-pool`) is hardcoded rather than sourced from `environments.yml`. The per-environment config file defines `iis-app-name: VBNetApp-Dev` etc., but those values are never used. |
| E2 | Medium | All workflows | No `workflow_call` reusable workflows are defined. Composite actions work for steps, but `workflow_call` would enable reuse of entire job sequences across repositories. |
| E3 | Low | `dotnet-core-ci.yml:33` | `IMAGE_NAME: 'dotnetcore-app'` is hardcoded as a workflow-level env var. If a second .NET Core app is added, the entire workflow must be duplicated. A `workflow_dispatch` input or matrix strategy would be more flexible. |
| E4 | Low | `dotnet-core-ci.yml:88-91` | Version generation is simplistic (`1.0.0-${SHORT_SHA}`). There is no mechanism for actual semantic version bumping, tag-based versioning, or integration with a versioning tool. |
| E5 | Low | All workflows | No matrix strategy for multi-version testing (e.g., testing against multiple .NET versions) or multi-environment parallel deployment. |

---

## 3. SECURITY

### Issues

| # | Severity | Location | Finding |
|---|----------|----------|---------|
| S1 | **High** | Multiple files | **Script injection via unsanitized expression interpolation.** `${{ }}` expressions are used directly in `run:` blocks across almost every file. If an input value contains shell metacharacters, it will be interpreted as code. Affected locations include: `dotnet-build/action.yml:46,52` (`inputs.project-path`, `inputs.configuration`), `dotnet-test/action.yml:41-50` (`inputs.test-path`, `inputs.verbosity`), `msbuild-build/action.yml:61` (`inputs.solution-path`), and `azure-vm-deploy/action.yml` (multiple inputs). **Fix:** Pass all `${{ }}` values via intermediate environment variables (e.g., `env.PROJECT_PATH`) rather than interpolating directly into `run:` scripts. |
| S2 | **High** | `dotnet-test/action.yml:54` | **`eval` usage.** The test command is built as a string and executed with `eval $TEST_COMMAND`. If any part of the inputs (`test-path`, `configuration`, `verbosity`) contains malicious content, it will be executed. **Fix:** Avoid `eval` entirely; call `dotnet test` directly with conditional flags. |
| S3 | **High** | `dotnet-core-ci.yml:80-83`, `azure-vm-deploy/action.yml:49-54`, `vbnet-cd.yml:74-77` | **Deprecated action `Azure/get-keyvault-secrets@v1`**. This action has been deprecated since 2023. It may not receive security patches. **Fix:** Use `az keyvault secret show` via Azure CLI after `azure/login`. |
| S4 | Medium | `dotnet-core-ci.yml:76`, `vbnet-cd.yml:70` | **Legacy Azure authentication.** `secrets.AZURE_CREDENTIALS` passes an entire service principal JSON blob. The recommended approach is **OIDC federated identity** using `client-id`, `tenant-id`, and `subscription-id` with `azure/login@v2`'s OIDC support. This eliminates long-lived credential secrets. |
| S5 | Medium | All workflows | **No `permissions` blocks defined.** None of the 3 workflows restrict `GITHUB_TOKEN` permissions. By default, the token may have `write` access to all scopes. **Fix:** Add explicit `permissions:` with least-privilege scopes (e.g., `contents: read`, `packages: write`). |
| S6 | Medium | All workflows | **Actions referenced by mutable version tags** (`@v4`, `@v2`, `@v5`, `@v3`, `@v1`). A compromised tag could inject malicious code. **Fix:** Pin third-party actions to full commit SHAs (e.g., `actions/checkout@<sha>`), using Dependabot or Renovate to keep them updated. |
| S7 | Medium | `azure-vm-deploy/action.yml:155-183` | **Secrets interpolated into inline script strings.** Connection strings and API keys from Key Vault are embedded in the wrapper PowerShell script (`$configTokens`). If the script fails or is logged, these values may appear in workflow logs. |
| S8 | Medium | `azure-vm-deploy/action.yml:74` | **HTTP-only application URL.** The constructed URL uses `http://` not `https://`, meaning the health check runs over an unencrypted connection and the deployment summary links to an insecure endpoint. |
| S9 | Low | `dotnet-core-ci.yml:89` | **Minor injection surface.** `${{ github.sha }}` is interpolated in a `run:` block. While a SHA is not user-controlled in the same way as a branch name, using `env:` is still best practice. |

---

## 4. EFFICIENCY

### Strengths

- NuGet package caching in both `dotnet-build` and `msbuild-build` actions.
- Docker layer caching via GitHub Actions cache (`cache-from: type=gha`).
- Path filters prevent unnecessary workflow runs on unrelated changes.
- `--no-restore` flag avoids double-restoring in build step.
- MSBuild `/maxcpucount` for parallel compilation.

### Issues

| # | Severity | Location | Finding |
|---|----------|----------|---------|
| EF1 | Medium | All workflows | **No `concurrency` groups.** Multiple pushes can trigger simultaneous workflow runs for the same branch/environment. Parallel deployments to the same environment can cause conflicts. **Fix:** Add `concurrency: { group: "${{ github.workflow }}-${{ github.ref }}", cancel-in-progress: true }` for CI, and environment-based groups for CD. |
| EF2 | Medium | All workflows | **No `timeout-minutes` on jobs.** A hung Azure CLI call or stuck Docker build will consume runner minutes indefinitely. **Fix:** Set explicit timeouts on every job (e.g., `timeout-minutes: 30`). |
| EF3 | Low | `vbnet-cd.yml:29` | **Unnecessary `windows-latest` runner for CD.** The deploy job only uses Azure CLI and PowerShell (both available on Ubuntu). Running on `windows-latest` is slower to provision and more expensive. |
| EF4 | Low | `vbnet-ci.yml:82-83` | **Unnecessary `checkout` in `package` job.** The package job downloads the artifact and doesn't need the full repo checkout. |
| EF5 | Low | `azure-vm-deploy/action.yml:49-54` | **Duplicate Key Vault fetch.** The action fetches `vm-name` and `vm-resource-group` from Key Vault even though the calling workflow (`vbnet-cd.yml:74-77`) already fetched and passed these values as inputs. This doubles the Key Vault API calls. |
| EF6 | Low | `vbnet-ci.yml:111` | **90-day artifact retention** for deployment packages is excessive. Default 30 days or shorter is typically sufficient for deployment artifacts that are consumed immediately by the CD pipeline. |
| EF7 | Low | `azure-vm-deploy/action.yml:157-159` | **Base64 encoding entire deployment package inline.** The zip file is base64-encoded and embedded in a PowerShell script string. This roughly doubles the data size and will fail for packages exceeding Azure VM Run Command limits (~96KB script size). Azure Blob Storage upload + SAS token download would be more robust. |

---

## Summary

| Category | Critical/High | Medium | Low |
|----------|--------------|--------|-----|
| **Modularity** | 0 | 2 | 2 |
| **Extensibility** | 0 | 2 | 3 |
| **Security** | 3 (S1, S2, S3) | 5 (S4-S8) | 1 |
| **Efficiency** | 0 | 2 | 5 |

## Top Priority Recommendations

1. **S1/S2** - Fix script injection risks by using environment variables instead of direct `${{ }}` interpolation in `run:` blocks, and remove `eval` usage in `dotnet-test`.
2. **S3** - Replace deprecated `Azure/get-keyvault-secrets@v1` with Azure CLI `az keyvault secret show` commands.
3. **S5/S6** - Add `permissions` blocks to all workflows and pin third-party actions to SHA digests.
4. **EF1/EF2** - Add concurrency groups and job timeouts to all workflows.
5. **M1/E1** - Actually parse and use `environments.yml` for environment-specific values, or remove the dead config loading step.
