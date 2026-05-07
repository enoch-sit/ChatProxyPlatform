# VM Cost Research Plan

## Goal

Estimate the monthly cost of a single-VM deployment for ChatProxy Platform on AWS and Azure for the remote-model scenario:

- about 100 concurrent students
- single Linux VM
- Docker-based deployment
- no local GPU inference
- persistent disk attached to the VM

## Why This Needs a Plan

The repo only gives an application floor, not a production-ready single-VM size. The declared app reservations in Terraform add up to about:

- 1.75 vCPU
- 3.5 GiB RAM

That floor excludes MongoDB, PostgreSQL, Docker overhead, OS overhead, log growth, and safety headroom. For that reason, the research compares VM sizes above the app floor rather than trying to price the floor directly.

## Sizing Assumptions Used for Cost Research

### Budget floor

- 4 vCPU
- 16 GiB RAM
- 256 GiB SSD

Purpose:

- cheapest non-burstable general-purpose VM shape that is still plausibly usable for a pilot or a thin production trial

### Safer starting point

- 8 vCPU
- 32 GiB RAM
- 512 GiB SSD

Purpose:

- more realistic starting point for a single-VM deployment that aims to support about 100 concurrent students without immediately running into RAM and database headroom issues

## Region and Purchase Assumptions

- AWS region: `us-east-1`
- Azure region: `eastus`
- Purchase model: on-demand / pay-as-you-go
- OS: Linux
- Availability target: single VM only, no high availability

## Pricing Method

### Monthly compute

Use:

`hourly_rate * 730`

because both AWS and Azure publish hourly compute rates and the Azure monthly numbers align with a 730-hour month.

### Monthly storage

Add the published managed disk or block storage monthly price for the assumed disk size.

### Optional backup allowance

If snapshot costs are needed, add:

`changed_snapshot_gb * snapshot_rate_per_gb_month`

This research keeps snapshots separate from the base VM total because snapshot growth depends on retention and write volume.

## Evidence Collection Order

1. Use repo files to confirm the app topology and current resource floor.
2. Use vendor pricing pages and pricing APIs where available.
3. Use targeted web search when vendor pages do not expose instance-level numbers cleanly through static fetch.
4. Record source URLs and extracted evidence in provider-specific notes.
5. Produce one final comparison document.

## Output Rules

The final estimate should:

- show both AWS and Azure
- show both the budget floor and the safer starting point
- separate base VM cost from excluded items
- clearly state that outbound bandwidth, public IP charges, and AI API/token costs are excluded unless explicitly priced
- clearly state that local LLM inference would require a different estimate

## Files Created For This Research

- `docs/research/aws_vm_pricing_evidence.md`
- `docs/research/azure_vm_pricing_evidence.md`
- `docs/research/vm_cost_estimation.md`
