# Multi-Cloud Governed Data Plane — Reference Architecture

**Nadis Data Infrastructure LLC** · A public, buildable reference implementation of the
architecture described in our response to the **NOAA OCIO Multi-Cloud Enterprise Data
Infrastructure Services** RFI/Sources Sought Notice.

> IaC is written in **OpenTofu** (Terraform-compatible, MPL 2.0, Linux Foundation) — a
> deliberate choice for multi-cloud, vendor-neutral, federal-procurement-friendly tooling.

> This repository is an **unclassified, generic reference**. It contains no NOAA data, no government
> credentials, and no production configuration. It exists to demonstrate capability: governed
> multi-cloud Infrastructure as Code, a security-gated CI/CD pipeline, and an MCP data-access gateway.

## What this demonstrates (mapped to the RFI)

| RFI requirement | Where it lives here |
|---|---|
| IaC platform template, multi-cloud | `terraform/` — modular landing zone (data plane / sci-dev / public) |
| FISMA-High data plane vs. FISMA-Moderate sci-dev separation | `terraform/modules/data-plane`, `terraform/modules/sci-dev` |
| ICAM, CMK encryption, no public buckets, MFA conditions | `terraform/modules/*` + policy guardrails |
| Automated CI/CD with security checks + SBOM | `.github/workflows/security.yml` (Checkov, Snyk IaC, tfsec, SBOM) |
| MCP server for AI agent data discovery (no raw keys) | `mcp-server/` |
| Secure public data access (NODD-style) | `terraform/modules/public-access` |

## Layout

```
terraform/
  modules/
    data-plane/        # FISMA-High: CMK-encrypted storage, strict ICAM, audit logging
    sci-dev/           # FISMA-Moderate: virtual workspaces, governed read-through access
    public-access/     # read-only public open-data layer (NODD pattern)
  main.tf              # composes the modules into a landing zone
  variables.tf
mcp-server/            # Python MCP gateway: exposes catalog/metadata tools, never raw creds
.github/workflows/
  security.yml         # Checkov + Snyk IaC + tfsec + SBOM; fails build on High/Critical
```

## Quick start

```bash
# Validate the IaC locally (no cloud account needed)
cd terraform && terraform init -backend=false && terraform validate

# Run the security gate the same way CI does
pip install checkov && checkov -d terraform --quiet

# Try the MCP server
cd mcp-server && pip install -r requirements.txt && python server.py
```

## Status

Reference / demonstration quality. Production deployment would target AWS GovCloud and Azure
Government on FedRAMP Moderate services, with control mappings to NIST SP 800-53.
