# GitHub Actions CI/CD Workflows for .NET Applications - POC

This repository demonstrates production-ready CI/CD workflows for both modern and legacy .NET applications using GitHub Actions, Azure services, and industry best practices.

## Overview

This POC implements two distinct CI/CD pipelines:

1. **.NET Core (C#) CI for AKS** - Modern ASP.NET Core Web API with Docker containerization
2. **VB.NET CI/CD for Azure Windows VM** - Legacy ASP.NET Web Forms with IIS deployment

## Architecture Highlights

✅ **Reusable Composite Actions** - 4 custom actions for common tasks
✅ **Azure Key Vault Integration** - Centralized secret management
✅ **Azure VM Run Command** - Secure deployment without WinRM
✅ **Docker Multi-Stage Builds** - Optimized container images
✅ **Environment Parameterization** - YAML-based configuration
✅ **GitHub Environments** - Approval gates for production deployments

## Repository Structure

See [docs/architecture/overview.md](docs/architecture/overview.md) for detailed architecture information.

## Quick Start

### Prerequisites

**Azure Resources:** ACR, Azure Windows VM with IIS, Azure Key Vault, Service Principal
**GitHub Secrets:** `AZURE_CREDENTIALS`, `KEY_VAULT_NAME`
**Key Vault Secrets:** ACR credentials, VM details, application secrets

### Workflow Triggers

- **.NET Core CI:** Push to main/develop (path: `src/DotNetCoreApp/**`)
- **VB.NET CI:** Push to main/develop (path: `src/VBNetApp/**`)
- **VB.NET CD:** After successful CI or manual dispatch

## Key Features

### .NET Core CI (Task 1)
- ASP.NET Core 9.0 Web API with Docker
- Runs tests with code coverage
- Pushes to Azure Container Registry
- Uses standard docker/build-push-action@v5

### VB.NET CI/CD (Task 2)
- VB.NET Web Forms (.NET Framework 4.8)
- MSBuild on Windows runner
- Deploys via **Azure VM Run Command** (no WinRM!)
- Tokenized Web.config with Key Vault integration

## Documentation

- [Architecture Overview](docs/architecture/overview.md)
- [Workflows Architecture with Diagrams](docs/architecture/workflows-architecture.md)

## Security

- Minimal GitHub Secrets (only 2 required)
- Azure Key Vault for all sensitive data
- Azure VM Run Command (no network ports, no WinRM)
- Least privilege service principals

---

**POC for GitHub Actions CI/CD Architecture - 2026**