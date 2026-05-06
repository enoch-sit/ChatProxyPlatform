# AI Brief: VM Cost and Capacity for 100 Concurrent Students

## Purpose

Use this document when asking an external AI or consultant to estimate the server size and monthly VM cost for running ChatProxy Platform for about 100 students concurrently.

The goal is not just to get a cheap VM suggestion. The goal is to get a realistic recommendation for stable operation, including headroom for databases, storage, spikes, and normal production overhead.

## What This Platform Is

ChatProxy Platform is a multi-service chat system built around Flowise.

Current local deployment model:

- Docker-based deployment on a Windows workstation.
- Student and teacher traffic enters through the Bridge web UI.
- Bridge calls the Flowise Proxy service.
- Flowise Proxy coordinates authentication, credit checks, chat session storage, and calls to Flowise.
- Flowise handles chatflow execution.
- Two MongoDB instances and two PostgreSQL instances are currently used in the local Docker topology.

High-level request path:

1. Student opens the Bridge UI.
2. Bridge sends requests to Flowise Proxy.
3. Flowise Proxy verifies identity and credits with Auth Service and Accounting Service.
4. Flowise Proxy calls Flowise.
5. Flowise executes the chatflow and usually calls external AI providers.
6. The platform stores chat history and usage records.

Important note:

- If Flowise is only orchestrating external AI APIs, VM sizing is mostly about web traffic, orchestration, databases, and I/O.
- If the server must run local LLM inference on the same machine, the estimate changes completely and may require a GPU server. Treat those as separate scenarios.

## Services Included on a Single Server

If deployed as one self-hosted server, the platform currently implies these runtime components:

| Component | Role | Port | Data Store |
| --- | --- | --- | --- |
| Bridge | React UI served by containerized web server | 3082 | none |
| Auth Service | login, JWT, roles, user management | 3000 | MongoDB |
| Accounting Service | credits and usage tracking | 3001 | PostgreSQL |
| Flowise Proxy | FastAPI gateway for chat, sessions, admin, uploads | 8000 | MongoDB |
| Flowise | chatflow builder and execution engine | 3002 | PostgreSQL + local persistent storage |
| MongoDB for Auth | auth database | 27017 | persistent volume |
| MongoDB for Proxy | chat/session database | 27020 -> 27017 in container | persistent volume |
| PostgreSQL for Accounting | accounting database | 5432 | persistent volume |
| PostgreSQL for Flowise | Flowise database | 5433 -> 5432 in container | persistent volume |

Non-production local tooling such as MailHog should not be counted for production sizing.

## Current Declared App Container Reservations

The repo already declares CPU and memory values for the app containers in Terraform. Those values are useful as a floor, not as a final production answer.

| App Service | CPU Units | Approx vCPU | Memory MiB | Approx GiB |
| --- | ---: | ---: | ---: | ---: |
| Auth Service | 256 | 0.25 | 512 | 0.5 |
| Accounting Service | 256 | 0.25 | 512 | 0.5 |
| Flowise Proxy | 512 | 0.5 | 1024 | 1.0 |
| Bridge | 256 | 0.25 | 512 | 0.5 |
| Flowise | 512 | 0.5 | 1024 | 1.0 |
| Total app floor | 1792 | 1.75 | 3584 | 3.5 |

This floor excludes:

- both MongoDB containers
- both PostgreSQL containers
- Docker overhead
- OS overhead
- reverse proxy or TLS termination overhead
- logging and monitoring agents
- backups and snapshot load
- burst headroom for concurrent chat spikes

## Current Platform Facts Relevant to Sizing

- The platform is designed as a multi-service stack, not a single monolith.
- The local workstation guidance in this repo recommends at least 8 GB RAM and 20 GB disk for basic setup, but that is a workstation baseline, not a 100-concurrent-user sizing target.
- A repo note already warns that supporting about 100 students concurrently should trigger load testing and likely evaluation of more scalable hosting.
- Flowise currently runs as a separate service and should be included in the sizing model.
- Current architecture stores chat history, user records, and credit data locally in databases.
- The platform likely depends on external AI model APIs for actual model execution, but that assumption must be confirmed.

## Scenario To Estimate

Primary scenario:

- About 100 students concurrently active.
- Users are chatting through Bridge -> Flowise Proxy -> Flowise.
- Auth and accounting checks are active.
- Chat history is stored.
- Production-like uptime is preferred over demo-only operation.
- Deployment target is a single VM or single dedicated server running Docker containers.

The AI should provide separate answers for these two scenarios:

1. Remote-model scenario: Flowise orchestrates calls to external AI APIs such as OpenAI, Anthropic, Azure OpenAI, or similar.
2. Local-model scenario: the same server must also host the actual inference model locally.

The second scenario may require GPU sizing and should not be mixed into the first.

## Unknowns That The AI Must Make Explicit

These values are not well-defined in the repo and should be treated as assumptions unless I fill them in first:

| Question | Current Value |
| --- | --- |
| Average messages per active user per minute | TBD |
| Average concurrent requests actually in-flight at the same instant | TBD |
| Average Flowise workflow complexity per request | TBD |
| Average uploaded file size and upload frequency | TBD |
| Average response size and stream duration | TBD |
| Chat history retention period | TBD |
| Backup frequency | TBD |
| Required uptime target | TBD |
| Whether local LLM inference is required | Assume no unless stated otherwise |
| Whether databases must remain on the same VM | Assume yes for single-VM scenario |

If any of these remain unknown, the AI should state its assumptions clearly before giving a recommendation.

## What I Need From The AI

Please ask the AI for the following deliverables:

1. Feasibility of running this stack on one VM for 100 concurrent students.
2. Recommended minimum VM size for a tight budget.
3. Recommended safer VM size for stable school usage.
4. CPU, RAM, disk, and network requirements.
5. Monthly cost estimate for 24/7 uptime.
6. Main bottlenecks and failure risks on a single server.
7. A point at which I should stop using one VM and split services or move to managed infrastructure.
8. A short load-test plan to verify the recommendation.

Useful comparison outputs:

- a cheapest acceptable option
- a recommended option
- a safer option with growth headroom
- cost deltas if databases move off-box

## Constraints and Preferences

- Prefer Linux VM assumptions unless there is a strong reason to keep Windows Server.
- Assume Docker Compose or equivalent container runtime on one host.
- Exclude AI token or API usage charges from VM pricing unless listed separately.
- Include storage, snapshots, and basic monitoring if they materially affect monthly cost.
- Favor reliability over the absolute cheapest possible machine.

## Suggested Prompt To Paste Into Another AI

```text
You are acting as an infrastructure sizing and cost advisor.

I need you to estimate the VM or dedicated server size and monthly hosting cost for running a self-hosted ChatProxy Platform for about 100 students concurrently.

This is a multi-service Docker deployment, not a single binary app.

Platform topology:
- Bridge UI: React frontend, port 3082
- Auth Service: Node.js, port 3000, MongoDB-backed
- Accounting Service: Node.js, port 3001, PostgreSQL-backed
- Flowise Proxy: Python FastAPI, port 8000, MongoDB-backed
- Flowise: port 3002, PostgreSQL-backed, persistent local storage

Single-server deployment currently implies these data services on the same machine:
- MongoDB for Auth
- MongoDB for Flowise Proxy
- PostgreSQL for Accounting
- PostgreSQL for Flowise

Known current app container reservations from existing infrastructure code:
- Auth Service: 0.25 vCPU, 512 MiB
- Accounting Service: 0.25 vCPU, 512 MiB
- Flowise Proxy: 0.5 vCPU, 1024 MiB
- Bridge: 0.25 vCPU, 512 MiB
- Flowise: 0.5 vCPU, 1024 MiB
- Total app floor only: 1.75 vCPU and 3.5 GiB RAM

Important: that total excludes both MongoDB instances, both PostgreSQL instances, Docker overhead, OS overhead, TLS/reverse proxy overhead, logging, backups, and burst headroom.

Primary workload target:
- around 100 students concurrently active
- production-like school usage, not a short demo
- chat history stored
- auth and accounting checks active on each request path

Please answer separately for two scenarios:
1. Remote-model scenario: Flowise calls external AI APIs, so the server only handles orchestration, storage, and web traffic.
2. Local-model scenario: the same server must also run the AI model locally.

For each scenario, provide:
1. Whether one VM is realistic
2. Recommended minimum VM size
3. Recommended safer VM size
4. CPU, RAM, disk, and bandwidth guidance
5. Monthly cost estimate assuming 24/7 uptime
6. Main bottlenecks and operational risks
7. At what point I should split databases or move to managed infrastructure

Make any missing assumptions explicit.
Do not include LLM token/API costs in the VM cost unless you list them separately.
If you think a single VM is the wrong choice, say so directly and explain the smallest safer alternative.
```

## My Own Notes Before Sending This To AI

Fill these in if known:

- Expected school-hours concurrency pattern: TBD
- Peak requests per minute: TBD
- Largest expected uploads: TBD
- Preferred provider to compare: TBD
- Budget ceiling per month: TBD
- Required uptime target: TBD

## Practical Interpretation

The most important question for the AI is not just "what VM is cheapest?" It is:

"Given this exact multi-container stack and 100 concurrent students, what is the smallest server I can run without turning the platform into an operational bottleneck?"

If the AI answer ignores database overhead, storage growth, or the difference between remote-model orchestration and local-model inference, ask it to revise the estimate.
