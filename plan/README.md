# SmartTok — Architecture Plan

A TikTok-style vertical short-video feed for the web, built in **Jac** (Jaseci stack), where every
video is educational: current events (bias-controlled), engineering, history, science,
linguistics/languages, DIY, and similar.

Two content modes:

1. **Curate** — discover, vet, and *embed* high-quality short-form videos from other platforms.
2. **Generate** — produce original shorts: LLM script → ElevenLabs narration → scenes built from
   public-domain/CC images + templated SVGs, rendered **in the browser** (no server-side video
   encoding in the default path).

## Documents

| # | File | Contents |
|---|------|----------|
| 1 | [01-architecture.md](01-architecture.md) | System overview, Jac stack, components, deployment |
| 2 | [02-data-model.md](02-data-model.md) | Graph schema (nodes/edges/walkers), API surface |
| 3 | [03-feed-and-ux.md](03-feed-and-ux.md) | Feed ranking, player, TikTok-parity UX, anti-brainrot features |
| 4 | [04-curation-mode.md](04-curation-mode.md) | External video discovery, vetting, scoring, legal |
| 5 | [05-generation-mode.md](05-generation-mode.md) | Script → voice → scenes pipeline, fact-checking, bias control |
| 6 | [06-cost-strategy.md](06-cost-strategy.md) | Token / TTS / compute / storage cost minimisation |
| 7 | [07-roadmap.md](07-roadmap.md) | Phased delivery, risks, open questions |

## Key decisions (TL;DR)

- **Full-stack Jac**: `jaclang` + `jac-client` (frontend components in Jac) + `jac serve`
  (walkers auto-exposed as REST endpoints with auth + graph persistence) + `byllm`
  (`by llm()` for scoring, scripting, fact-checking).
- **Graph-native data model**: users, topics, videos, and interactions are nodes/edges; the feed
  is a walker traversing the graph.
- **Curated videos are embedded, never re-hosted** (except PD/CC-licensed media that allows it).
- **Generated videos are "scene manifests", not MP4s**: JSON + one narration MP3 + word timings.
  The browser renders SVG/image scenes synced to audio. Optional MP4 export via ffmpeg for sharing.
- **LLMs never write raw SVG by default**: they fill small JSON params for a library of
  hand-authored SVG templates → ~10–50x fewer output tokens than freeform SVG.
- **Feed optimises for learning, not time-on-app**: quality × interest × diversity, session
  check-ins, recall quizzes, visible sources.

> Note: the Jac ecosystem moves quickly (jac-client / jac-scale / byllm APIs changed through
> 2025). Code snippets in these docs are illustrative; Phase 0 of the roadmap is a spike to pin
> exact versions and syntax.
