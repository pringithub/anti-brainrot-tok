# 03 — Feed, Player & UX

Goal: feel almost exactly like TikTok (instant, full-screen, swipe, autoplay, sound-on) while the
ranking objective is *learning value*, not watch-time.

## 1. TikTok-parity UX

| TikTok feature | Here |
|----------------|------|
| Full-screen vertical swipe, snap scroll | `FeedPager` with CSS `scroll-snap-type: y mandatory`; keyboard ↑/↓, wheel, touch |
| Instant playback | Keep prev/current/next mounted; preload next 2 (iframe `loading="eager"` for next, audio + images prefetched for generated) |
| Tap to pause, double-tap to like | Same |
| Right action rail | Like · Save · Share · **Sources** · **Why this?** · **Not useful** |
| Caption + creator overlay | Title, creator/"Generated", topic chips, license/attribution |
| For You / Following tabs | For You / **Topics I follow** |
| Search / Discover | Topic browser + search over titles/summaries/transcripts |
| Profile | Saved, liked, history, streaks, "things learned" |
| Comments | **Deferred** (moderation cost); later: structured "add a source / correction" notes |

### Embed caveats
- YouTube iframes cannot be controlled as smoothly as native video; use the IFrame Player API (`enablejsapi=1`, `playsinline=1`, `mute` until first user gesture, then unmute) and `postMessage` for play/pause.
- Autoplay-with-sound requires a user gesture; the first tap on the landing screen ("Start learning") unlocks audio for the session.
- Horizontal curated videos are letterboxed with a blurred thumbnail background.

## 2. Candidate generation

Per request, merge candidates from:
1. **Interest walk** — traverse user → followed/high-interest Topics → child topics → live Videos (top-N by quality per topic).
2. **Fresh** — current-events videos from the last 48 h (always a small quota, not personalised beyond language).
3. **Explore** — random high-quality videos from topics the user hasn't seen (≈15–20%).
4. **Spaced repetition** — occasional quiz cards for videos watched 1–7 days ago.

Exclude: already watched (completed) in last 30 days, skipped < 2 s, `NotUseful`, dead/expired.

## 3. Ranking

```
score = quality^α
      × interest(user, topics)
      × freshness(video)            # strong decay for current events, ~none for evergreen
      × novelty(user, topic)        # penalise same topic N times in a row
      × creator_diversity
```

- `quality` (0..1) = blend of the AI score from ingestion and **learning-oriented** engagement: completion rate, saves, quiz correctness, "not useful" rate. Likes weighted low; raw watch-time *not* used directly.
- `interest` = user's `interest_vec` (updated online: completed +, saved ++, skipped quickly −, not useful −−), smoothed so one binge doesn't take over.
- Final list passes an **MMR-style diversity re-rank**: no more than 2 consecutive videos from the same top-level topic.

Start with this hand-tuned formula (transparent, debuggable). Revisit with learned models only if data justifies it.

## 4. Anti-brainrot features (the differentiator)

- **Session check-ins**: after the user's chosen interval (default 15 min or 20 videos) a full-screen card: "You've watched 20 videos on 5 topics. Keep going / Quiz me / Take a break." Never a dark pattern; always dismissible.
- **Daily goal instead of infinite hunger**: user sets minutes/day; progress ring; gentle end-of-goal card.
- **Recall quizzes**: 1-question cards derived from recently watched videos (spaced repetition).
- **Sources visible on every video**; "Why this?" explains ranking in plain words.
- **No vanity metrics front-and-centre**: like counts hidden by default.
- **Topic breadth nudges**: "You've been deep in Military History — here's something from Linguistics."
- **Current events**: labelled with date, "multiple sources" badge, auto-expire.

## 5. Accessibility & performance

- Captions always available (generated: from ElevenLabs timestamps; curated: provider captions).
- Reduced-motion setting disables Ken-Burns/animated transitions.
- Budget: first video playable < 2 s on 4G; feed page payload < 20 KB JSON; generated video total download ~300–700 KB (mp3 + a few compressed images + SVG).
