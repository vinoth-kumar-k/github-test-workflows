# .NET Core AKS CI/CD - Gaps, Issues, and Recommended Updates

## 1. Critical Security Gaps

### 1.1. Missing Container Image Scanning [HIGH PRIORITY]
**Issue:** No vulnerability scanning of Docker images before pushing to ACR.
- Docker images are built and pushed without scanning for CVEs
- Vulnerable base images or dependencies could be deployed to production

**Recommendation:**
- Integrate Trivy or ACR scanning: Add scanning step post Docker build
- Example:
  ```yaml
  - name: Scan image with Trivy
    uses: aquasecurity/trivy-action@master
    with:
      image-ref: ${{ steps.build-push.outputs.image }}
      format: 'sarif'
      output: 'trivy-results.sarif'
  ```
- Enable ACR content trust policies
- Block deployment of images with HIGH/CRITICAL vulnerabilities

### 1.2. Missing Secrets Rotation Strategy [MEDIUM PRIORITY]
**Issue:** No documented secrets rotation policy for GitHub Secrets and Azure Credentials.
- Service Principal credentials stored in GitHub Secrets may not rotate automatically
- No audit trail of credential usage

**Recommendation:**
- Implement Service Principal credential rotation schedule (90-180 days)
- Use Azure Managed Identity for GitHub Actions (Azure/login with OIDC)
- Document rotation procedures in CLAUDE.md

### 1.3. Insufficient Kubernetes RBAC Documentation [MEDIUM PRIORITY]
**Issue:** kubelogin configuration uses Service Principal but no mention of RBAC roles granted.
- Unclear what permissions the Service Principal has in AKS
- Risk of excessive permissions

**Recommendation:**
- Document required RBAC roles:
  ```yaml
  - deployments.create
  - deployments.update
  - services.get
  - namespaces.get
  ```
- Implement least privilege principle in RBAC policies
- Create separate Service Principals per environment

---

## 2. Architectural Gaps

### 2.1. No Staging/Production Deployment Implementation [HIGH PRIORITY]
**Issue:** CD workflow only shows Dev deployment implementation; staging and prod jobs missing.
- Incomplete pipeline for multi-environment deployments
- Cannot demonstrate full production readiness

**Recommendation:**
- Extend `dotnet-core-cd.yml` with staging and prod jobs:
  ```yaml
  deploy-staging:
    if: >
      (github.event_name == 'workflow_run' && github.event.workflow_run.conclusion == 'success' && github.event.workflow_run.head_branch == 'develop') ||
      (github.event_name == 'workflow_dispatch')
    environment: staging
    # Similar structure to dev

  deploy-prod:
    needs: deploy-staging
    if: github.event.workflow_run.head_branch == 'main'
    environment: prod
    # Similar structure to staging
  ```
- Implement approval gates for prod deployments using GitHub Environments

### 2.2. Missing Automated Rollback Strategy [HIGH PRIORITY]
**Issue:** No rollback mechanism if deployment fails or health checks fail.
- Failed deployments leave system in inconsistent state
- No quick recovery option

**Recommendation:**
- Implement automated rollback on health check failure:
  ```yaml
  - name: Rollback on failure
    if: failure()
    run: |
      kubectl rollout undo deployment/dotnetcoreapp -n "$NAMESPACE"
      kubectl rollout status deployment/dotnetcoreapp -n "$NAMESPACE" --timeout=300s
  ```
- Store previous working image tag for quick rollback
- Document manual rollback procedures

### 2.3. Missing Canary/Blue-Green Deployment Pattern [MEDIUM PRIORITY]
**Issue:** Direct deployment without gradual rollout strategy.
- All traffic switches at once, risk of widespread outages
- No A/B testing capability

**Recommendation:**
- Implement canary deployment using Flagger:
  ```yaml
  - name: Deploy canary
    run: |
      kubectl apply -f k8s/canary-manifest.yaml -n "$NAMESPACE"
      # Progressive traffic shift over 10 minutes
  ```
- Or implement blue-green with service selector switching

### 2.4. Missing Pipeline Observability and Metrics [MEDIUM PRIORITY]
**Issue:** No centralized logging or monitoring of CI/CD pipeline execution.
- Cannot track pipeline performance trends
- Difficult to identify bottlenecks

**Recommendation:**
- Add Prometheus metrics export
- Implement pipeline duration tracking
- Add artifact size reporting
- Example:
  ```yaml
  - name: Report metrics
    run: |
      echo "build_duration_seconds=$BUILD_DURATION" >> metrics.txt
      echo "artifact_size_bytes=$ARTIFACT_SIZE" >> metrics.txt
  ```

---

## 3. Code Quality and Testing Gaps

### 3.1. No Code Coverage Thresholds [MEDIUM PRIORITY]
**Issue:** Code coverage collected but no enforcement of minimum thresholds.
- Coverage data not validated or reported
- No gate preventing coverage regression

**Recommendation:**
- Add coverage threshold check in dotnet-test action:
  ```yaml
  - name: Check coverage threshold
    run: |
      COVERAGE=$(grep -oP 'line-rate="\K[0-9.]+' TestResults/*/coverage.cobertura.xml | head -1)
      if (( $(echo "$COVERAGE < 0.80" | bc -l) )); then
        echo "Coverage $COVERAGE below threshold 0.80"
        exit 1
      fi
  ```
- Publish coverage reports to pull requests
- Track coverage trends over time

### 3.2. Missing SAST/Linting Integration [MEDIUM PRIORITY]
**Issue:** No Static Application Security Testing (SAST) or code linting.
- Security vulnerabilities not detected before merge
- Code style inconsistencies

**Recommendation:**
- Integrate SonarQube or CodeQL:
  ```yaml
  - name: Run CodeQL analysis
    uses: github/codeql-action/analyze@v2
  ```
- Add Roslyn analyzers to build:
  ```xml
  <PropertyGroup>
    <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
  </PropertyGroup>
  ```

### 3.3. Missing Integration/E2E Test Coverage [MEDIUM PRIORITY]
**Issue:** Only unit tests run; no integration or E2E tests.
- Cannot verify end-to-end functionality
- Integration issues detected in production

**Recommendation:**
- Add integration test job in CI:
  ```yaml
  integration-tests:
    needs: build-and-test
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
    steps:
      - name: Run integration tests
        run: dotnet test --filter "Category=Integration"
  ```

---

## 4. Docker and Container Best Practices

### 4.1. Missing Docker Build Caching Optimization [MEDIUM PRIORITY]
**Issue:** Current Dockerfile doesn't leverage Docker layer caching effectively.
- No multi-stage build in Dockerfile itself
- Build artifacts copied all at once

**Recommendation:**
- Implement multi-stage build within Dockerfile:
  ```dockerfile
  FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
  WORKDIR /src
  COPY ["src/DotNetCoreApp.csproj", "."]
  RUN dotnet restore "DotNetCoreApp.csproj"
  COPY . .
  RUN dotnet build -c Release -o /app/build

  FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS runtime
  WORKDIR /app
  COPY --from=build /app/build .
  # User, port, health check...
  ```
- Benefits: Smaller layer sizes, better cache utilization
- Note: This requires CI workflow adjustment (remove separate publish step)

### 4.2. Missing Container Security Scanning [MEDIUM PRIORITY]
**Issue:** No validation of container runtime security (seccomp, AppArmor).
- Containers may not have security profiles
- Kernel syscall exploits possible

**Recommendation:**
- Add seccomp profile:
  ```yaml
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  ```
- Document in Kubernetes manifests
- Validate in pipeline

### 4.3. Missing Resource Limits in Dockerfile [LOW PRIORITY]
**Issue:** Container doesn't specify recommended resource limits.
- Uncontrolled memory/CPU usage possible
- Kubernetes requires limits for proper scheduling

**Recommendation:**
- Document in deployment manifests rather than Dockerfile:
  ```yaml
  resources:
    requests:
      memory: "256Mi"
      cpu: "250m"
    limits:
      memory: "512Mi"
      cpu: "500m"
  ```

---

## 5. Configuration and Environment Management

### 5.1. Missing Secret Management Integration [MEDIUM PRIORITY]
**Issue:** No integration with Azure Key Vault for runtime secrets.
- Secrets hardcoded or stored in environments.yml
- No audit trail of secret access

**Recommendation:**
- Integrate Azure Key Vault:
  ```yaml
  - name: Load secrets from Key Vault
    uses: Azure/get-keyvault-secrets@v1
    with:
      keyvault: ${{ steps.config.outputs.key-vault-name }}
      secrets: 'app-db-password,api-key'
  ```
- Mount secrets as Kubernetes volumes

### 5.2. Configuration File Validation Missing [LOW PRIORITY]
**Issue:** `environments.yml` not validated against schema.
- Invalid configurations caught at runtime
- No IDE support or documentation

**Recommendation:**
- Add JSON schema validation in load-config action:
  ```python
  import jsonschema
  schema = {
    "type": "object",
    "properties": {
      "acr-name": {"type": "string"},
      "aks-cluster": {"type": "string"},
      "namespace": {"type": "string"}
    },
    "required": ["acr-name", "aks-cluster", "namespace"]
  }
  jsonschema.validate(config, schema)
  ```

### 5.3. Missing Configuration Documentation [LOW PRIORITY]
**Issue:** No documentation of required configuration keys.
- Unclear what values must be in environments.yml
- New environments fail due to missing keys

**Recommendation:**
- Create `CONFIG_SCHEMA.md` documenting all required/optional keys
- Add inline YAML comments

---

## 6. Operational and Maintenance Issues

### 6.1. Artifact Retention Policy Mismatch [MEDIUM PRIORITY]
**Issue:** Different artifacts have different retention (1 day for build, 30 days for tests/coverage).
- Inconsistent retention policy
- Unclear reasoning

**Recommendation:**
- Define clear retention strategy:
  - Build artifacts: 1 day (intermediate, not needed after docker push)
  - Test results: 30 days (for historical analysis)
  - Coverage reports: 90 days (for trend analysis)
  - Document in workflow comments

### 6.2. Missing CI Pipeline Notifications [LOW PRIORITY]
**Issue:** No Slack/Teams notifications for pipeline failures.
- Teams unaware of pipeline failures
- Delays in incident response

**Recommendation:**
- Add notification action:
  ```yaml
  - name: Notify on failure
    if: failure()
    uses: slack-notify-action@v1
    with:
      webhook_url: ${{ secrets.SLACK_WEBHOOK }}
      message: "CI pipeline failed on ${{ github.ref }}"
  ```

### 6.3. Missing Deployment Verification [MEDIUM PRIORITY]
**Issue:** Pipeline doesn't verify application health post-deployment.
- Application might be running but not responding
- No validation of actual deployment success

**Recommendation:**
- Add post-deployment verification:
  ```yaml
  - name: Verify application health
    run: |
      for i in {1..30}; do
        if curl -f http://<service-url>/health; then
          echo "Application is healthy"
          exit 0
        fi
        sleep 10
      done
      echo "Application health check failed"
      exit 1
  ```

---

## 7. VB.NET Workflow Conflicts [MEDIUM PRIORITY]

### 7.1. Unnecessary VB.NET Configuration [SCOPE ISSUE]
**Issue:** `environments.yml` contains VB.NET configuration, not needed for modern .NET POC.
- Adds complexity to configuration
- Increases attack surface

**Recommendation:**
- Remove VB.NET sections from `environments.yml`:
  ```yaml
  dev:
    key-vault-name: kv-dev
    dotnet-core:  # Keep only dotnet-core
      acr-name: ...
  ```
- Mark load-config action as "dotnet-core only" in documentation
- Plan separate VB.NET pipeline when needed

---

## 8. Missing Extensibility Features

### 8.1. No Webhook Integration for External Tools [LOW PRIORITY]
**Issue:** Pipeline doesn't integrate with external deployment/alerting tools.
- Manual synchronization needed
- No GitOps support

**Recommendation:**
- Add webhook output for external tools:
  ```yaml
  - name: Call deployment webhook
    run: |
      curl -X POST ${{ secrets.DEPLOYMENT_WEBHOOK }} \
        -H "Content-Type: application/json" \
        -d '{"image":"${{ steps.image.outputs.full-image }}"}'
  ```

### 8.2. No Custom Action Documentation [LOW PRIORITY]
**Issue:** Custom actions lack detailed documentation.
- Difficult for new team members to understand
- No usage examples

**Recommendation:**
- Add README.md to each action directory:
  ```
  .github/actions/dotnet-build/README.md
  .github/actions/dotnet-test/README.md
  .github/actions/dotnet-publish/README.md
  ```

---

## 9. Priority Implementation Roadmap

### Phase 1 (Critical - Week 1-2)
- [ ] Add container image scanning (Trivy)
- [ ] Implement staging and prod deployment jobs
- [ ] Add automated rollback mechanism
- [ ] Document RBAC requirements

### Phase 2 (High - Week 3-4)
- [ ] Implement Service Principal credential rotation strategy
- [ ] Add code coverage threshold enforcement
- [ ] Integrate SAST (CodeQL/SonarQube)
- [ ] Implement canary or blue-green deployment

### Phase 3 (Medium - Week 5-6)
- [ ] Add Azure Key Vault integration
- [ ] Implement multi-stage Docker build
- [ ] Add post-deployment health verification
- [ ] Remove VB.NET configuration

### Phase 4 (Low - Week 7+)
- [ ] Add Slack notifications
- [ ] Document custom actions with examples
- [ ] Add webhook integration
- [ ] Implement pipeline metrics/monitoring

---

## 10. Summary of Unnecessary Components (To Remove)

1. **VB.NET configuration in environments.yml** - Not needed for modern .NET POC
2. **VB.NET workflows** - Out of scope for this design
3. **Redundant artifact uploads** - Consider consolidating
4. **Manual environment selection in CI workflow_dispatch** - Use branch-based automatic routing instead

---

## 11. Recommendations for Reusability and Extensibility

### 11.1 Template Design
- Create action templates for common patterns
- Support multiple runtime versions (SDK version as parameter)
- Enable multiple deployment targets (not just AKS)

### 11.2 Configuration Flexibility
- Support config inheritance for environment parity
- Allow action overrides per environment
- Enable optional features (e.g., enable/disable scanning)

### 11.3 Documentation
- Maintain WORKFLOWS.md for architecture overview
- Keep ACTION_EXAMPLES.md for custom action usage
- Document all environment variables and secrets required

