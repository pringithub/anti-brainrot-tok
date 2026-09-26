# 06 — Cost Strategy

Costs to control: LLM tokens, ElevenLabs characters, YouTube API quota, compute, storage/egress.
Verify all provider prices at build time; figures below are for relative sizing only.

## 1. Per-generated-video budget (target)

| Step | Size | Notes |
|------|------|-------|
| Retrieval | 0 LLM tokens | Plain HTTP; trim source text to ~3–5k input tokens total |
| Script + scene params | ~4–6k input, ~600–900 output tokens | Cheap model; templates referenced by name, not by full SVG |
| Fact-check | ~4k input, ~300 output | Cheap model for evergreen; stronger model only for current events |
| Image resolution | 0 LLM tokens | LLM already produced queries inside the script |
| TTS | ~800–1,100 characters | ≈ 150 words; the dominant marginal cost |
| Rendering | 0 server compute | Browser renders the manifest |
| Storage | ~0.3–0.7 MB | mp3 @ 64 kbps ≈ 0.5 MB/min + webp images |

**Why this is cheap**: freeform SVG per scene would be ~800–2,000 output tokens × ~10 scenes; template params are ~50 tokens × 10. Server-side MP4 encoding would add CPU minutes and ~5–15 MB storage/egress per video; manifests avoid both.

## 2. Levers

### LLM
- Default to the cheapest capable model in byllm; route to a stronger model by rule (current events fact-check, repeated validation failures).
- Structured outputs (typed `obj`s) → no retries for parse failures.
- Prompt caching: keep the static part (taxonomy, template catalog, rubric) as a stable prefix to benefit from provider prompt caching.
- Batch curation scoring; cache by transcript hash; never re-score rejected ids.
- Creator trust lets high-trust channels skip full scoring.

### ElevenLabs
- Strict narration length cap (validated before TTS).
- Content-hash cache; regenerate only changed sentences (split TTS per sentence and concatenate if edits are frequent — trade-off: prosody across sentences; evaluate).
- Use the cheaper Flash/Turbo model tier for bulk.
- Monthly character budget enforced by the generation pipeline (`PipelineRun.stats.tts_chars`); job pauses when budget reached.

### YouTube quota (10k units/day default)
- Channel upload playlists (1 unit) over `search.list` (100 units).
- `videos.list` batched 50 ids per call.
- ETags / `If-None-Match` for unchanged playlists.

### Storage / delivery
- Cloudflare R2 (no egress fees) + CDN caching, immutable content-hash URLs with long `Cache-Control`.
- Images resized to 1080px long edge, webp/avif.
- Curated videos cost nothing to serve (embedded).

### Compute
- API is thin (graph queries); workers are cron-driven batches — can run on the same small VM initially.

## 3. Budget guardrails (implemented in code)

- `config.budget.monthly_usd`, `config.budget.tts_chars`, `config.budget.llm_tokens` checked at the start of each job.
- Every external call records usage → aggregated per `PipelineRun` → admin dashboard.
- Kill switch env var to pause generation.
