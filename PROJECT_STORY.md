# SmartTok: The Project Story

## Inspiration

I'd open TikTok for five minutes and look up an hour later, and I couldn't remember a single thing I'd watched. The problem wasn't the format. Short, vertical, swipeable video is one of the best attention hooks ever designed. The problem was what the format was tuned to deliver.

So I wondered what would happen if that same hook were pointed at something worth remembering. There are already great short explainers out there on engineering, history, science, linguistics and DIY, and there is current events coverage that doesn't try to make you angry. It's just scattered across creators and buried under everything else. I wanted a feed that holds only that, and that can make its own videos when the good content runs out.

## What it does

- **A TikTok-style feed with only educational content.** It covers 8 topics: unbiased current events, engineering, history, science, linguistics, DIY and more. You can swipe, double-tap to like, save, and flag something as "not useful".
- **Curation mode.** It pulls Shorts from 58 hand-verified YouTube channels, scores them for quality and ranks them for each user. Right now there are about 480 live videos.
- **Generation mode.** A research agent reads Wikipedia, writes a script, checks its own claims and revises the script. The video is then built from ElevenLabs narration with word-level timestamps and public-domain Wikimedia images or generated SVGs. I chose that pipeline because it was the cheapest option in both tokens and money.
- **Features that fight brainrot.**
  - A daily goal and periodic check-ins ("still learning, or just scrolling?").
  - Quiz cards between videos.
  - An explore slot and a diversity pass, so the feed never collapses into one topic.

## How I built it

The whole thing is written in **[Jac](https://www.jaseci.org/)**, a language built on top of Python that treats graphs and AI as first-class features. Frontend, backend and agents all live in one language and one project.

- **Data as a graph.**
  - The nodes are `Topic`, `Video`, `Creator`, `Profile` and `Job`.
  - Engagement is a typed edge, `Profile --Engaged--> Video`, which carries views, watch time, likes, saves and quiz results. The engagement history *is* the graph.
- **Feed ranking as a walker.** `LoadFeed` starts at the user's root, walks into their topics, scores each video it visits, and ranks the results on the way out. Ranking takes into account explore slots, diversity and whether you've already seen a video.
- **Agents with `by llm`.** Jac's byLLM turns a typed function signature into an LLM call.
  - The research agent (`research_and_write`) gets `search_wikipedia` and `read_article` as tools. A separate `llm_check_claims` / `revise_script` loop runs up to two revision rounds before anything is published.
  - A planner walker (`PlanCatalog`) looks at gaps in the catalog and adds generation and curation jobs to a queue.
  - When no API key is set, everything falls back to heuristics.
- **Frontend in Jac too.** jac-client compiles `.cl.jac` components to React: the app shell, feed pager, video cards, scene player and quiz cards. The backend is called through RPC stubs that are generated automatically from `def:pub` endpoints and walkers.
- **Sources that need no API keys.** YouTube's public RSS feeds (the `UUSH…` playlist lists Shorts only) and the Wikimedia Commons search API.
- **Tooling.**
  - An admin CLI written in Jac.
  - MockLLM-based agent tests.
  - QA in a headless browser with `jac browse` at a 390×844 phone viewport.

## Challenges

- **YouTube iframes swallow swipes.** An embedded player eats every touch event, so you couldn't swipe past a video. I tried overlays and shields, but they broke playback controls. The final fix was a framed layout: the video sits in a box and you swipe on the frame around it. There is also an explicit **Next** button, so both the YouTube UI and the SmartTok UI stay interactive.
- **Permissions in a shared graph.**
  - Anonymous public endpoints run as `root.shared`, so all catalog writes had to go through them.
  - Catalog nodes needed explicit `grant(..., ConnectPerm)` before users could attach their own `Engaged` edges to shared videos.
  - Working out who owns what took a lot of reading warnings.
- **A young language means undocumented edges.** Several bugs only showed up at runtime:
  - The client shim has no `str.join`.
  - Constructing a server-side `obj` on the client silently turns into an RPC call, which then 404s.
  - Effects must `return;`, not `return None;`.
  - Falsy RPC results arrive as `None`.
  - `default` is a reserved word.
- **A byLLM bug across modules.** A tool-less `by llm` function that returns a type imported from another module failed at runtime. The fix was to define the function in the same module as its return type. I also found that MockLLM with tools uses up one extra scripted output, which made the first agent tests fail for confusing reasons.
- **Dev environment friction.**
  - Stale Vite processes kept shifting ports.
  - The Vite proxy crashed when serving static SVGs.
  - `jac check .` walked into the virtualenv.
  - Behind a corporate proxy, nothing could be installed until the proxy was configured.
- **Keeping generated content honest.** An LLM writing educational scripts is only as good as its fact-checking. That's why the research agent has to cite the articles it actually read, and why a separate check-and-revise pass runs before publishing. The three seed videos were fact-checked by hand.

## What I learned

- **Graph-first thinking makes recommendation logic much simpler.** When engagement is an edge, "what has this person seen, liked or struggled with" becomes a walk, not a join.
- **Typed LLM functions are a better abstraction than prompt strings.** Declaring the output type and letting the runtime handle the prompt kept the agent code small and testable. The heuristic fallbacks meant the app never *depended* on a model being available.
- **Design for the platform you embed.** You don't own a third-party player's input handling. Designing around it worked better than fighting it.
- **Cheap generation is a design choice.** Narration with word timestamps plus still images or SVGs gets most of the value of a "video" for a tiny fraction of the cost of real video generation.
- **Verify, don't assume.** Many hours were saved by checking behavior in a real headless browser at phone size instead of trusting that the code looked right.

## What's next

- **More agents:**
  - A curator agent that discovers new channels.
  - A balance agent that keeps news coverage politically even.
  - A tutor agent that turns saved videos into spaced-repetition review.
- **Scoring from transcripts** instead of titles and descriptions.
- **Budget guardrails** for LLM and TTS spend.
- **Search.**
- **Public deployment.**
