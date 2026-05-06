# AI Token Pricing Evidence

Research date: 2026-05-06

## Scope

This note records the public pricing evidence used to estimate token spend for a long Flowise session with:

- two AI agents
- MCP tools
- RAG context injection
- long system prompt
- no KV cache

The token estimate in the main document is a text-token estimate. It does not include provider-specific image token billing for multimodal inference.

## Azure OpenAI GPT-5

Source:

- [Azure OpenAI pricing](https://azure.microsoft.com/en-us/pricing/details/cognitive-services/openai-service/)

Relevant evidence extracted:

- `GPT-5 2025-08-07 Global` lists `Input: $1.25` and `Output: $10` per `1M` tokens.
- `GPT-5 chat Global` also lists `Input: $1.25` and `Output: $10` per `1M` tokens.

Pricing used in the estimate:

- input: `$1.25 / 1M tokens`
- output: `$10 / 1M tokens`

## AWS Bedrock Amazon Nova

Source:

- [Amazon Bedrock pricing](https://aws.amazon.com/bedrock/pricing/)

Important note:

- The Bedrock pricing page is interactive. Static fetch did not expose the Amazon Nova rows cleanly.
- The pricing row below was extracted from the live browser-rendered Bedrock pricing table.

Relevant evidence extracted from the live page:

- under `Amazon Nova`
- under `Pricing for Understanding Models`
- `Global Cross-region Inference`
- `Region: US East (Ohio)`
- `Standard Tier`
- `Amazon Nova 2 Lite` lists `Price per 1M input tokens: $0.30`
- `Amazon Nova 2 Lite` lists `Price per 1M output tokens: $2.50`

Pricing used in the estimate:

- input: `$0.30 / 1M tokens`
- output: `$2.50 / 1M tokens`

Why this caveat matters:

- This estimate uses the current publicly readable `Amazon Nova 2 Lite` row.
- That is likely not a like-for-like frontier-model comparison against GPT-5 or Claude Sonnet 4.
- The purpose here is cost planning using the current public Nova row that could be verified.

## xAI Grok

Source:

- [xAI API overview](https://x.ai/api)

Relevant evidence extracted:

- `grok-4.3` lists `Text Input $1.25` and `Output $2.50`
- page states `All prices are per million tokens or as stated`

Pricing used in the estimate:

- input: `$1.25 / 1M tokens`
- output: `$2.50 / 1M tokens`

## OpenRouter Claude

Source:

- [OpenRouter Claude Sonnet 4](https://openrouter.ai/anthropic/claude-sonnet-4)

Relevant evidence extracted:

- page header lists `Claude Sonnet 4`
- lists `1,000,000 context`
- lists `$3/M input tokens`
- lists `$15/M output tokens`
- provider pricing section shows `Input Price <=200K $3, >200K $6 / M tokens`
- provider pricing section shows `Output Price <=200K $15, >200K $22.50 / M tokens`

Pricing used in the estimate:

- input: `$3 / 1M tokens`
- output: `$15 / 1M tokens`

Why the base tier was used:

- The long-session estimate is aggregated over many model calls in a session.
- Individual calls are assumed to stay below `200K` tokens each, so the lower per-request tier remains the planning baseline.

## FX Conversion

Source:

- [XE USD to HKD](https://www.xe.com/currencyconverter/convert/?Amount=1&From=USD&To=HKD)

Relevant evidence extracted:

- `1 USD = 7.8352 HKD` on 2026-05-06

Pricing used in the estimate:

- `1 USD = 7.8352 HKD`
