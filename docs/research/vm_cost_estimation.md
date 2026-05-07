# VM Cost Estimation

Research date: 2026-05-06

## Executive Summary

For a single-VM deployment of ChatProxy Platform in the remote-model scenario, the lowest credible production-like starting point is not the app resource floor from the repo. The app floor is only about `1.75 vCPU / 3.5 GiB RAM`, and that excludes the two MongoDB containers, two PostgreSQL containers, Docker overhead, OS overhead, logging, and headroom.

Using public pricing evidence from AWS and Azure, the practical cost ranges are:

| Tier | AWS Base Monthly | Azure Base Monthly | Notes |
| --- | ---: | ---: | --- |
| Budget floor | $146.62 | $163.57 | 4 vCPU, 16 GiB RAM, 256 GiB SSD |
| Safer starting point | $293.25 | $324.34 | 8 vCPU, 32 GiB RAM, 512 GiB SSD |

My recommendation for a `100 concurrent students` target is to start planning around the safer tier, not the budget floor.

## Scope and Assumptions

This estimate assumes:

- single Linux VM
- Docker-based deployment
- one host running the application services plus local databases
- remote-model usage, where Flowise calls external AI APIs
- no local GPU inference
- on-demand pricing only
- region comparison: AWS `us-east-1`, Azure `eastus`

Important clarification:

- this single-VM assumption is a hypothetical consolidation cost model
- it is not the same as the current AWS Terraform deployment in this repo
- the current AWS IaC deploys Flowise and Flowise Proxy as ECS Fargate services, not as one EC2 VM each
- the current Terraform CPU and memory reservations appear to be demo-only sizing, not a production target for `100 concurrent students`
- for the production VM interpretation in this document, the intended shape is `2` Linux VMs with Flowise on its own VM
- for simplicity, that two-VM production interpretation is priced here as `2x` the selected single-VM shape

This estimate excludes:

- outbound bandwidth charges
- public IP charges
- monitoring and logging add-ons
- AI API or token spend in the base VM estimate, covered separately in the AI token addendum below
- backup tooling beyond raw snapshot storage
- labor and operations

## Why These VM Sizes Were Chosen

The repo’s declared application reservations add up to roughly:

- `1.75 vCPU`
- `3.5 GiB RAM`

That reservation floor should be treated as a demo footprint only, not as evidence that the full platform can support `100 concurrent students` at that size.

That number is too low to use directly for a single production-style VM because it excludes:

- MongoDB for auth
- MongoDB for chat history and sessions
- PostgreSQL for accounting
- PostgreSQL for Flowise
- OS and Docker overhead
- performance headroom for concurrent chat spikes

So the pricing research compared two practical sizes:

### Budget floor comparison

- `4 vCPU`
- `16 GiB RAM`
- `256 GiB SSD`

### Safer starting point comparison

- `8 vCPU`
- `32 GiB RAM`
- `512 GiB SSD`

## AWS Estimate

### AWS evidence used

- EC2 on-demand pricing page confirms compute is billed separately from storage and Linux is billed per second.
- EBS pricing page confirms gp3 storage pricing is separate and includes baseline `3,000 IOPS` and `125 MB/s`.
- Targeted web evidence plus Vantage instance pages gave exact instance-level hourly prices.

### AWS instance candidates

| Instance | vCPU | RAM | Hourly | Monthly Compute |
| --- | ---: | ---: | ---: | ---: |
| m6a.xlarge | 4 | 16 GiB | $0.1728 | $126.14 |
| m6a.2xlarge | 8 | 32 GiB | $0.3456 | $252.29 |
| m7i.xlarge | 4 | 16 GiB | $0.2016 | $147.17 |
| m7i.2xlarge | 8 | 32 GiB | $0.4032 | $294.34 |

### AWS storage assumptions

Using gp3 at `$0.08 / GB-month`:

| Disk Size | Monthly Disk Cost |
| --- | ---: |
| 256 GiB | $20.48 |
| 512 GiB | $40.96 |

### AWS base totals

| Tier | Shape | Base Monthly Total |
| --- | --- | ---: |
| Budget floor | m6a.xlarge + 256 GiB gp3 | $146.62 |
| Safer starting point | m6a.2xlarge + 512 GiB gp3 | $293.25 |

### AWS interpretation

- `m6a` is the cost-efficient AWS baseline for this use case.
- `m7i` is valid if you want newer Intel hardware, but it raises cost without changing the memory ratio.
- The `m6a.xlarge` tier is a thin floor, not a comfortable 100-concurrent-student target.

## Azure Estimate

### Azure evidence used

- The official Linux VM pricing page lists `D4as v5` at `$125.56/month` and `D8as v5` at `$251.12/month`.
- The Azure retail pricing tool confirmed the same shapes at `0.172/hour` and `0.344/hour` in `eastus`.
- The Azure retail pricing tool provided managed disk pricing for `P15 LRS` and `P20 LRS`.

### Azure VM candidates

| VM | vCPU | RAM | Hourly | Monthly Compute |
| --- | ---: | ---: | ---: | ---: |
| D4as v5 | 4 | 16 GiB | $0.172 | $125.56 |
| D8as v5 | 8 | 32 GiB | $0.344 | $251.12 |

### Azure storage assumptions

| Disk SKU | Size Class | Monthly Disk Cost |
| --- | --- | ---: |
| P15 LRS | 256 GiB | $38.01 |
| P20 LRS | 512 GiB | $73.22 |

### Azure base totals

| Tier | Shape | Base Monthly Total |
| --- | --- | ---: |
| Budget floor | D4as v5 + P15 LRS | $163.57 |
| Safer starting point | D8as v5 + P20 LRS | $324.34 |

### Azure interpretation

- Azure is slightly more expensive than AWS in this single-VM comparison.
- The `D4as v5` tier is the cheapest credible Azure floor.
- The `D8as v5` tier is the more realistic place to start if the target really is about `100 concurrent students`.

## Provider Comparison

### Budget floor

| Provider | Compute + Disk |
| --- | ---: |
| AWS m6a.xlarge + 256 GiB gp3 | $146.62 |
| Azure D4as v5 + 256 GiB premium disk | $163.57 |

Difference:

- AWS is about `$16.95/month` cheaper at the budget floor.

### Safer starting point

| Provider | Compute + Disk |
| --- | ---: |
| AWS m6a.2xlarge + 512 GiB gp3 | $293.25 |
| Azure D8as v5 + 512 GiB premium disk | $324.34 |

Difference:

- AWS is about `$31.09/month` cheaper at the safer tier.

## Recommendation

### If the goal is the cheapest acceptable pilot

Use one of these:

- AWS: `m6a.xlarge + 256 GiB gp3` at about `$146.62/month`
- Azure: `D4as v5 + P15 LRS` at about `$163.57/month`

Risk:

- this is likely too thin for a stable `100 concurrent students` target once the four databases, Docker overhead, and peak bursts are factored in

### If the goal is a serious single-VM starting point

Use one of these:

- AWS: `m6a.2xlarge + 512 GiB gp3` at about `$293.25/month`
- Azure: `D8as v5 + P20 LRS` at about `$324.34/month`

This is the tier I would use as the planning baseline for a single-host deployment intended to support about `100 concurrent students`.

## HKD Addendum For Logged Usage And Images

Using the live rate captured on 2026-05-06 from Xe:

- `1 USD = 7.8352 HKD`

### Long-session logging model used here

To estimate the impact of logging all student usage and images, this addendum assumes:

- `100` concurrent students
- `1` chatflow per student session
- long conversation session
- remote-model usage, so the VM is not doing local GPU inference
- session payload dominated by stored images, not by text logs

Reasonable storage profiles per session are:

| Session Profile | Approximate Logged Data Per Session |
| --- | ---: |
| text and usage only | 2 MB |
| long session with 5 images | 10 MB |
| long session with 10 images | 18 MB |
| long session with 10 heavier images | 24 MB |

### Storage growth implied by that model

If each of the same `100` students runs one long session per day, that is about `3,000 sessions/month`:

| Profile | Monthly New Storage |
| --- | ---: |
| text and usage only | 5.9 GB |
| long session with 5 images | 29.3 GB |
| long session with 10 images | 52.7 GB |
| long session with 10 heavier images | 70.3 GB |

If the platform instead sees about `15,000 sessions/month` through repeated daily session waves:

| Profile | Monthly New Storage |
| --- | ---: |
| text and usage only | 29.3 GB |
| long session with 5 images | 146.5 GB |
| long session with 10 images | 263.7 GB |
| long session with 10 heavier images | 351.6 GB |

Working interpretation:

- if images stay on the VM disk, `512 GiB` is no longer the comfortable default
- `1 TiB` is the safer single-VM disk size for long-conversation retention with image logging
- if images are moved to object storage instead of the VM disk, the earlier `512 GiB` estimate remains more viable

### Recommended single-VM cost in HKD

For the image-logging scenario, the safer planning baseline is `8 vCPU / 32 GiB RAM / 1 TiB SSD`.

| Provider | Shape | USD / Month | HKD / Month |
| --- | --- | ---: | ---: |
| AWS | m6a.2xlarge + 1 TiB gp3 | $334.21 | HK$2,618.60 |
| Azure | D8as v5 + P30 LRS | $386.29 | HK$3,026.66 |

These are the numbers I would use for a first-pass budget when you want to keep full usage logs and images on the same VM.

### Higher-headroom option in HKD

If you expect heavier image upload traffic, higher retention on-box, or noticeably more simultaneous processing overhead, move up one compute tier:

| Provider | Shape | USD / Month | HKD / Month |
| --- | --- | ---: | ---: |
| AWS | m6a.4xlarge + 1 TiB gp3 | $586.50 | HK$4,595.31 |
| Azure | D16as v5 + P30 LRS | $637.41 | HK$4,994.23 |

### Two-year total cost in HKD

If you keep the VM running continuously for `24` months at the same on-demand pricing level, the two-year infrastructure totals are:

| Plan | Provider | USD / 24 Months | HKD / 24 Months |
| --- | --- | ---: | ---: |
| Recommended single-VM baseline | AWS | $8,021.04 | HK$62,846.45 |
| Recommended single-VM baseline | Azure | $9,270.96 | HK$72,639.83 |
| Higher-headroom single VM | AWS | $14,076.00 | HK$110,288.28 |
| Higher-headroom single VM | Azure | $15,297.84 | HK$119,861.64 |

### If production means two Linux VMs with a separate Flowise VM

If your production rule is to run `2` Linux VMs, with one dedicated to Flowise and one for the rest of the platform, then the infrastructure numbers above can be approximated as `2x` the selected single-VM shape.

Using the same recommended and higher-headroom shapes:

| Plan | Provider | USD / Month | HKD / Month | USD / 24 Months | HKD / 24 Months |
| --- | --- | ---: | ---: | ---: | ---: |
| Recommended production baseline | AWS | $668.42 | HK$5,237.20 | $16,042.08 | HK$125,692.90 |
| Recommended production baseline | Azure | $772.58 | HK$6,053.32 | $18,541.92 | HK$145,279.66 |
| Higher-headroom production | AWS | $1,173.00 | HK$9,190.62 | $28,152.00 | HK$220,576.56 |
| Higher-headroom production | Azure | $1,274.82 | HK$9,988.46 | $30,595.68 | HK$239,723.28 |

This is the right way to read the estimate if you want a separate Flowise VM but are still using a simple two-host multiplier rather than sizing the Flowise VM independently.

### Approximate infrastructure cost per long session

If `100` students each run one long session per day, that is about `3,000 sessions/month`.

Using the recommended `8 vCPU / 32 GiB / 1 TiB` plan:

| Provider | HKD / Month | Approximate HKD / Session |
| --- | ---: | ---: |
| AWS | HK$2,618.60 | HK$0.87 |
| Azure | HK$3,026.66 | HK$1.01 |

Important:

- this is only the VM infrastructure cost per session
- it does not include model API or token cost
- it does not include outbound bandwidth, monitoring, or object storage if you later move images off the VM

## AI Token Cost Addendum

This section estimates text-token consumption and API spend for a single long Flowise session using:

- two AI agents
- MCP tools
- RAG
- long system prompt
- no KV cache

This is a text-token estimate only. It does not include provider-specific image token billing if uploaded images are sent directly into a multimodal model.

### Session token model used here

Assumed session shape:

- `12` user turns in one long session
- `2` model calls per turn because the chatflow uses two AI agents
- long system prompt and agent instructions repeated on every call because there is no KV cache
- one RAG injection and one MCP tool result injection per turn

Token budget:

| Component | Formula | Input Tokens |
| --- | --- | ---: |
| system prompt and agent instructions | `24 calls * 3,000` | 72,000 |
| MCP tool schemas and tool instructions | `24 calls * 1,500` | 36,000 |
| current user turn passed into both agents | `24 calls * 250` | 6,000 |
| RAG context injected once per turn | `12 * 2,400` | 28,800 |
| MCP tool result payload injected once per turn | `12 * 1,200` | 14,400 |
| cumulative replayed history with no KV cache | planning estimate | 198,000 |
| total input | n/a | 355,200 |

Output budget:

| Component | Formula | Output Tokens |
| --- | --- | ---: |
| combined output from the two agents | `12 turns * 1,400` | 16,800 |
| total output | n/a | 16,800 |

Working planning estimate per long session:

- input: `355,200` tokens
- output: `16,800` tokens
- total metered text tokens: `372,000`

### Model pricing used

| Model option | Input / 1M tokens | Output / 1M tokens | Pricing source used |
| --- | ---: | ---: | --- |
| Azure OpenAI GPT-5 Global | $1.25 | $10.00 | official Azure OpenAI pricing page |
| AWS Bedrock Amazon Nova 2 Lite | $0.30 | $2.50 | official Bedrock pricing page, live browser-rendered table |
| xAI Grok 4.3 | $1.25 | $2.50 | official xAI API pricing page |
| OpenRouter Claude Sonnet 4 | $3.00 | $15.00 | OpenRouter model page |

### Estimated token cost per long session

Using `1 USD = 7.8352 HKD`:

| Model option | USD / Session | HKD / Session |
| --- | ---: | ---: |
| Azure OpenAI GPT-5 | $0.6120 | HK$4.80 |
| AWS Bedrock Amazon Nova 2 Lite | $0.1486 | HK$1.16 |
| xAI Grok 4.3 | $0.4860 | HK$3.81 |
| OpenRouter Claude Sonnet 4 | $1.3176 | HK$10.32 |

### Estimated token cost for 100 simultaneous long sessions

If `100` students are concurrently in one long session each, the aggregate token volume is roughly:

- input: `35.52M` tokens
- output: `1.68M` tokens

Estimated API spend for that wave of `100` long sessions:

| Model option | USD / 100 sessions | HKD / 100 sessions |
| --- | ---: | ---: |
| Azure OpenAI GPT-5 | $61.20 | HK$479.51 |
| AWS Bedrock Amazon Nova 2 Lite | $14.86 | HK$116.42 |
| xAI Grok 4.3 | $48.60 | HK$380.79 |
| OpenRouter Claude Sonnet 4 | $131.76 | HK$1,032.36 |

### Estimated monthly token cost at 3,000 long sessions

If `100` students each complete about one long session per day, that is about `3,000` sessions per month.

| Model option | USD / Month | HKD / Month |
| --- | ---: | ---: |
| Azure OpenAI GPT-5 | $1,836.00 | HK$14,385.43 |
| AWS Bedrock Amazon Nova 2 Lite | $445.68 | HK$3,491.99 |
| xAI Grok 4.3 | $1,458.00 | HK$11,423.72 |
| OpenRouter Claude Sonnet 4 | $3,952.80 | HK$30,970.98 |

### Estimated two-year token cost at 3,000 long sessions per month

At the same `3,000 sessions/month` level over `24` months:

| Model option | USD / 24 Months | HKD / 24 Months |
| --- | ---: | ---: |
| Azure OpenAI GPT-5 | $44,064.00 | HK$345,250.25 |
| AWS Bedrock Amazon Nova 2 Lite | $10,696.32 | HK$83,807.81 |
| xAI Grok 4.3 | $34,992.00 | HK$274,169.32 |
| OpenRouter Claude Sonnet 4 | $94,867.20 | HK$743,303.49 |

### Combined VM and token total at 3,000 long sessions per month

This combines the recommended single-VM baseline with the token estimate above.

Pairing assumption:

- Azure GPT-5 is paired with the Azure recommended VM baseline.
- AWS Nova 2 Lite is paired with the AWS recommended VM baseline.
- xAI Grok 4.3 and OpenRouter Claude Sonnet 4 are paired with the AWS recommended VM baseline as the lower-cost neutral host.

| Model path | USD / Month Total | HKD / Month Total | USD / 24 Months Total | HKD / 24 Months Total |
| --- | ---: | ---: | ---: | ---: |
| Azure GPT-5 + Azure VM | $2,222.29 | HK$17,412.09 | $53,334.96 | HK$417,890.08 |
| AWS Nova 2 Lite + AWS VM | $779.89 | HK$6,110.59 | $18,717.36 | HK$146,654.26 |
| xAI Grok 4.3 + AWS VM | $1,792.21 | HK$14,042.32 | $43,013.04 | HK$337,015.77 |
| OpenRouter Claude Sonnet 4 + AWS VM | $4,287.01 | HK$33,589.58 | $102,888.24 | HK$806,149.94 |

### Combined production total with a separate Flowise VM

If production means `2` Linux VMs with one dedicated to Flowise, while token demand stays the same, the combined totals become:

| Model path | USD / Month Total | HKD / Month Total | USD / 24 Months Total | HKD / 24 Months Total |
| --- | ---: | ---: | ---: | ---: |
| Azure GPT-5 + Azure production infra | $2,608.58 | HK$20,438.75 | $62,605.92 | HK$490,529.91 |
| AWS Nova 2 Lite + AWS production infra | $1,114.10 | HK$8,729.19 | $26,738.40 | HK$209,500.71 |
| xAI Grok 4.3 + AWS production infra | $2,126.42 | HK$16,660.92 | $51,034.08 | HK$399,862.22 |
| OpenRouter Claude Sonnet 4 + AWS production infra | $4,621.22 | HK$36,207.18 | $110,909.28 | HK$869,996.39 |

If you prefer to host the Grok or OpenRouter path on Azure instead of AWS, add:

- `HK$408.06 / month`
- `HK$9,793.38 / 24 months`

### Interpretation

- With no KV cache, replayed history dominates input token cost.
- For this session shape, token spend is likely to exceed VM spend for GPT-5, Grok, and Claude.
- Nova is much cheaper in this estimate, but the verifiable AWS Bedrock row available in research was `Amazon Nova 2 Lite`, which is not a like-for-like frontier-model comparison with GPT-5 or Claude Sonnet 4.
- If you later enable prompt caching, shorten the system prompt, reduce RAG chunk size, or collapse the two-agent pattern into one model call on some turns, token spend can fall materially.

## Caveats

### Local inference is not included

If the same VM must run a local LLM instead of calling remote model APIs, these numbers stop being relevant. That becomes a GPU sizing problem.

### Bandwidth is excluded

- AWS includes the first `100 GB` of internet egress per month across services, but higher usage will add cost.
- Azure bandwidth was not priced in this pass because traffic volume is unknown.

### Single-VM architecture risk remains

Even at `8 vCPU / 32 GiB`, a single VM is still one failure domain. If the platform becomes important enough that downtime is costly, the next step should be splitting the databases off-box or moving toward managed services rather than only scaling up the VM.

## Research Trail

Supporting notes:

- `docs/research/vm_cost_research_plan.md`
- `docs/research/aws_vm_pricing_evidence.md`
- `docs/research/azure_vm_pricing_evidence.md`
- `docs/research/ai_token_pricing_evidence.md`
