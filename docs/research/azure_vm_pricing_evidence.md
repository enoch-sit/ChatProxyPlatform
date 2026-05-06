# Azure VM Pricing Evidence

Research date: 2026-05-06

## Scope

This note records the evidence used to estimate a single-VM Azure deployment for ChatProxy Platform in `eastus`.

## Source 1: Azure Linux Virtual Machines Pricing Page

URL:

- [Azure Linux Virtual Machines Pricing](https://azure.microsoft.com/en-us/pricing/details/virtual-machines/linux/)

Relevant evidence extracted:

- `D4as v5` shows `4` vCPU and `16 GiB` RAM at `$125.5600/month`.
- `D8as v5` shows `8` vCPU and `32 GiB` RAM at `$251.1200/month`.
- Disk storage is billed separately from virtual machines.

Why it matters:

- The Azure VM price must be separated from managed disk cost.
- The D-as family is a good general-purpose Linux baseline for a single-host container stack.

## Source 2: Azure Retail Pricing Tool

Tool results for `eastus`:

- `Standard_D4as_v5` returned a Linux consumption rate of `$0.172 per hour`
- `Standard_D8as_v5` returned a Linux consumption rate of `$0.344 per hour`

These line up with the monthly figures on the official Azure pricing page:

- `0.172 * 730 = $125.56`
- `0.344 * 730 = $251.12`

Why it matters:

- The pricing tool confirms the monthly numbers and gives a consistent hourly basis for recalculation.

## Source 3: Azure Managed Disks Pricing

Official page:

- [Azure Managed Disks Pricing](https://azure.microsoft.com/en-us/pricing/details/managed-disks/)

Relevant evidence extracted:

- Managed disks are billed separately from VMs.
- Premium SSD and other disk types are priced by provisioned size.
- Incremental snapshots are charged at `$0.05/GB per month` on standard storage.

Azure retail pricing tool results for `eastus`:

| Disk SKU | Size Class | Retail Price |
| --- | --- | ---: |
| P10 LRS | 128 GiB | $19.71 / month |
| P15 LRS | 256 GiB | $38.012142 / month |
| P20 LRS | 512 GiB | $73.22 / month |

Why it matters:

- The disk price is material for a single-VM design that holds four databases and application volumes.
- The retail tool numbers are more precise than the broad pricing-page table extraction, so the final estimate uses the retail tool values.

## Derived Azure Totals Used In Final Estimate

### Budget floor

| VM Shape | Compute | Disk | Base Monthly Total |
| --- | ---: | ---: | ---: |
| D4as v5 + P15 LRS | $125.56 | $38.01 | $163.57 |

### Safer starting point

| VM Shape | Compute | Disk | Base Monthly Total |
| --- | ---: | ---: | ---: |
| D8as v5 + P20 LRS | $251.12 | $73.22 | $324.34 |

Optional snapshot allowance:

| Snapshot Delta | Formula | Monthly Snapshot Cost |
| --- | --- | ---: |
| 50 GiB changed data | `50 * 0.05` | $2.50 |
| 100 GiB changed data | `100 * 0.05` | $5.00 |

## Exclusions

These numbers do not include:

- outbound bandwidth
- public IP pricing
- Azure Monitor / Log Analytics
- backup orchestration beyond raw snapshot storage
- AI model or API token costs
- operational labor

## Working Interpretation

The D4as v5 option is the cheapest credible Azure floor for this research. The D8as v5 option is the more realistic single-VM starting point for a 100-concurrent-user target.
