# 07 — Roadmap, Risks, Open Questions

## Phase 0 — Spike (validate Jac stack)
- Install `jaclang`, `jac-client`, `byllm`; pin versions in `jac.toml`/`requirements`.
- Hello-world: a `cl` component calling a walker via `jac serve`; confirm auth, persistence, shared catalog node access across users.
- Confirm byllm typed outputs with the chosen cheap model.
- Prototype `ScenePlayer` with a hand-written manifest + one ElevenLabs with-timestamps call.
- **Exit criteria**: vertical swipe between 3 hard-coded videos (1 YouTube embed, 2 manifests) served from Jac.

## Phase 1 — MVP feed with curated content
- Data model (nodes/edges), taxonomy seed, guest users, onboarding.
- Curation pipeline for YouTube allowlisted channels (≈50 seed channels) + scoring.
- Feed walker with ranking v1, like/save/skip/not-useful, sources sheet.
- Admin review queue.
- Deploy small prod.

## Phase 2 — Generation mode (evergreen)
- SVG template library (≈10 templates) + schemas.
- Image search service with license filtering + attribution.
- Script → fact-check → TTS → manifest pipeline; budget guardrails.
- Mix generated videos into feed (quota, then let quality decide).

## Phase 3 — Anti-brainrot layer
- Session check-ins, daily goal, recall quizzes (spaced repetition), "why this?".
- Profile: history, saved, "things learned", streaks.

## Phase 4 — Current events
- News clustering (RSS + GDELT), multi-outlet balancing, stricter fact-check, mandatory review, auto-expiry.

## Phase 5 — Growth / polish
- Search, TikTok/Vimeo/Commons sources, multilingual (ElevenLabs multilingual voices; linguistics content), MP4 export/share, PWA install, correction notes instead of comments.

## Risks

| Risk | Mitigation |
|------|------------|
| Jac ecosystem immaturity / API churn (jac-client especially) | Phase 0 spike; isolate frontend in `client/`; fallback: keep Jac backend and write the client in plain React/TS calling the same walker endpoints |
| YouTube embed UX is less smooth than native video | Preload, poster images, IFrame API control; increase share of generated/native content over time |
| AI factual errors in generated content | Retrieval-only citations, claim check pass, human review for current events, user "report" + fast unpublish |
| Perceived bias in current events | Multi-outlet sourcing, attributed claims, transparency sheet, review |
| Licensing mistakes on images | Strict license allowlist, store license + author + source URL, attribution always rendered |
| Provider ToS changes / quota | Adapter per provider, allowlist approach, graceful degradation |
| Cold-start content volume | Seed channel allowlist; batch-generate evergreen backlog before launch |
| Cost overrun | Budget guardrails + kill switch (see 06) |

## Open questions (need your input)

1. **LLM provider** preference (OpenAI / Anthropic / Google / local)? Affects byllm config and cost.
2. **Accounts**: guest-first with optional sign-up OK? Any social login needed?
3. **Deployment target**: single VM, Fly/Render, Kubernetes, or Jac's own scaling tooling?
4. **Human review**: will you (or someone) review current-events videos, or should they be fully automated with stricter thresholds?
5. **Languages**: English-only v1, or multilingual from the start (relevant for the linguistics category)?
6. **Monetisation / public launch** vs personal use? Changes ToS/licensing strictness and moderation needs.
7. **ElevenLabs plan tier** (sets the monthly character budget and concurrency).
