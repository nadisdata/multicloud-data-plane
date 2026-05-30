"""
MCP data-access gateway (reference implementation).

Demonstrates the security model in our NOAA RFI response: AI agents talk to
this gateway over the Model Context Protocol (JSON-RPC). The gateway exposes
*discovery* tools over a data catalog — schemas, metadata, dataset listings —
and NEVER returns storage credentials, connection strings, or raw bulk data.
Actual data access happens behind the gateway via a governed, audited role.

This keeps secrets inside the boundary and gives the agent only what it needs
to discover and plan a workflow.

Run:  pip install -r requirements.txt && python server.py
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field

from mcp.server.fastmcp import FastMCP

mcp = FastMCP("noaa-ref-data-plane")


# ---------------------------------------------------------------------------
# Mock catalog. In production this is backed by the federated data catalog
# (e.g., Glue/Unity/DataHub) sitting in the FISMA-High data plane. The agent
# sees metadata only; it never sees the underlying location credentials.
# ---------------------------------------------------------------------------
@dataclass
class Dataset:
    dataset_id: str
    title: str
    domain: str           # weather | ocean | space
    classification: str   # public | fisma-moderate | fisma-high
    schema: dict = field(default_factory=dict)


CATALOG: dict[str, Dataset] = {
    "goes-abi-l2": Dataset(
        dataset_id="goes-abi-l2",
        title="GOES-R ABI Level-2 Cloud & Moisture Imagery",
        domain="weather",
        classification="public",
        schema={"time": "datetime64", "lat": "float32", "lon": "float32", "cmi": "float32"},
    ),
    "argo-floats": Dataset(
        dataset_id="argo-floats",
        title="Argo Global Ocean Temperature/Salinity Profiles",
        domain="ocean",
        classification="public",
        schema={"profile_id": "string", "pressure": "float32", "temp": "float32", "psal": "float32"},
    ),
    "internal-model-run": Dataset(
        dataset_id="internal-model-run",
        title="Pre-release Numerical Model Output (restricted)",
        domain="weather",
        classification="fisma-high",
        schema={"run_id": "string", "valid_time": "datetime64", "field": "string"},
    ),
}


@mcp.tool()
def list_datasets(domain: str | None = None) -> str:
    """List datasets in the catalog. Optionally filter by domain
    (weather, ocean, space). Returns metadata only — never data or credentials."""
    items = [
        {
            "dataset_id": d.dataset_id,
            "title": d.title,
            "domain": d.domain,
            "classification": d.classification,
        }
        for d in CATALOG.values()
        if domain is None or d.domain == domain
    ]
    return json.dumps(items, indent=2)


@mcp.tool()
def get_schema(dataset_id: str) -> str:
    """Return the schema (field names and types) for a dataset so an agent can
    plan a query or workflow. Returns schema only — never a storage location
    or credential."""
    ds = CATALOG.get(dataset_id)
    if ds is None:
        return json.dumps({"error": f"unknown dataset_id: {dataset_id}"})
    return json.dumps({"dataset_id": ds.dataset_id, "schema": ds.schema}, indent=2)


@mcp.tool()
def request_access_plan(dataset_id: str, purpose: str) -> str:
    """Describe HOW an agent would obtain governed access to a dataset, without
    granting it. For restricted data this returns the policy gate that a human/
    automated approver must clear — demonstrating governed access, not a bypass."""
    ds = CATALOG.get(dataset_id)
    if ds is None:
        return json.dumps({"error": f"unknown dataset_id: {dataset_id}"})

    if ds.classification == "public":
        plan = {
            "dataset_id": dataset_id,
            "access": "public-read via open-data endpoint",
            "credentials_required": False,
            "note": "Served from the public access layer (NODD pattern).",
        }
    else:
        plan = {
            "dataset_id": dataset_id,
            "access": "governed read-through via cross-account role assumption",
            "credentials_required": True,
            "credentials_returned_here": False,  # the gateway never hands these out
            "policy_gate": [
                "caller identity verified (ICAM)",
                "phishing-resistant MFA present and recent",
                "purpose logged for audit",
                "least-privilege, time-bound STS session issued behind the gateway",
            ],
            "purpose_recorded": purpose,
        }
    return json.dumps(plan, indent=2)


if __name__ == "__main__":
    mcp.run()
