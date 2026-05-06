# AWS VM Pricing Evidence

Research date: 2026-05-06

## Scope

This note records the evidence used to estimate a single-VM AWS deployment for ChatProxy Platform in `us-east-1`.

## Source 1: AWS EC2 On-Demand Pricing

URL:

- [AWS EC2 On-Demand Pricing](https://aws.amazon.com/ec2/pricing/on-demand/)

Relevant evidence extracted:

- On-Demand instances are billed by the hour or second with no long-term commitment.
- Linux instances are billed per second with a 60-second minimum.
- Amazon EBS is priced separately from EC2 compute.
- AWS customers receive 100 GB of free data transfer out to the internet each month aggregated across services and regions.

Why it matters:

- The VM price must be split into compute and storage.
- Any final estimate that ignores storage is incomplete.
- Outbound transfer above the free tier is workload-dependent and should be excluded unless traffic is measured.

## Source 2: AWS EBS Pricing

URL:

- [AWS EBS Pricing](https://aws.amazon.com/ebs/pricing/)

Relevant evidence extracted:

- gp3 storage is charged by provisioned GB per month.
- gp3 includes a baseline of 3,000 IOPS and 125 MB/s throughput.
- AWS pricing examples use a region charging `$0.08 per GB-month` for gp3 storage.
- Snapshot storage is charged separately based on stored data.

Supporting web search evidence:

- Bing search for `AWS EBS gp3 us-east-1 price per GB-month` returned a summary tied back to the AWS EBS pricing page stating `approximately $0.08 per GB per month`.

Why it matters:

- gp3 is a reasonable baseline SSD choice for a single Docker host.
- The baseline IOPS and throughput are already included, so the simple estimate only needs GB-month pricing unless the disk is deliberately over-provisioned.

## Source 3: Exact EC2 Instance Evidence

The AWS EC2 pricing page did not expose the exact instance rows cleanly via static fetch, so instance-specific pricing was confirmed with targeted web lookup and the Vantage EC2 instances reference pages.

### m6a.xlarge

URL:

- [Vantage m6a.xlarge](https://instances.vantage.sh/aws/ec2/m6a.xlarge)

Extracted evidence:

- `4 vCPUs`
- `16 GiB` memory
- on-demand price starts at `$0.1728 per hour`

Derived monthly compute:

- `0.1728 * 730 = $126.14`

### m6a.2xlarge

URL:

- [Vantage m6a.2xlarge](https://instances.vantage.sh/aws/ec2/m6a.2xlarge)

Extracted evidence:

- `8 vCPUs`
- `32 GiB` memory
- on-demand price starts at `$0.3456 per hour`

Derived monthly compute:

- `0.3456 * 730 = $252.29`

### m7i.xlarge

URL:

- [Vantage m7i.xlarge](https://instances.vantage.sh/aws/ec2/m7i.xlarge)

Extracted evidence:

- `4 vCPUs`
- `16 GiB` memory
- on-demand price starts at `$0.2016 per hour`

Derived monthly compute:

- `0.2016 * 730 = $147.17`

### m7i.2xlarge

URL:

- [Vantage m7i.2xlarge](https://instances.vantage.sh/aws/ec2/m7i.2xlarge)

Extracted evidence:

- `8 vCPUs`
- `32 GiB` memory
- on-demand price starts at `$0.4032 per hour`

Derived monthly compute:

- `0.4032 * 730 = $294.34`

## Storage Cost Assumptions Used

Using gp3 at `$0.08 per GB-month`:

| Disk Size | Formula | Monthly Storage |
| --- | --- | ---: |
| 256 GiB | `256 * 0.08` | $20.48 |
| 512 GiB | `512 * 0.08` | $40.96 |

Optional snapshot allowance:

| Snapshot Delta | Formula | Monthly Snapshot Cost |
| --- | --- | ---: |
| 50 GiB changed data | `50 * 0.05` | $2.50 |
| 100 GiB changed data | `100 * 0.05` | $5.00 |

## Derived AWS Totals Used In Final Estimate

### Budget floor

| VM Shape | Compute | Disk | Base Monthly Total |
| --- | ---: | ---: | ---: |
| m6a.xlarge + 256 GiB gp3 | $126.14 | $20.48 | $146.62 |
| m7i.xlarge + 256 GiB gp3 | $147.17 | $20.48 | $167.65 |

### Safer starting point

| VM Shape | Compute | Disk | Base Monthly Total |
| --- | ---: | ---: | ---: |
| m6a.2xlarge + 512 GiB gp3 | $252.29 | $40.96 | $293.25 |
| m7i.2xlarge + 512 GiB gp3 | $294.34 | $40.96 | $335.30 |

## Exclusions

These numbers do not include:

- public IPv4 charges
- outbound data transfer above the AWS free monthly allowance
- CloudWatch logs and monitoring
- backup orchestration beyond raw snapshot storage
- AI model or API token costs
- operational labor

## Working Interpretation

For cost-performance, `m6a` is the better AWS baseline for this research. `m7i` is a valid current-generation alternative, but it costs more without changing the memory ratio.
