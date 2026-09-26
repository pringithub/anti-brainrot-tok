"""Bottom sheets and full-screen cards: sources/why, session check-in, onboarding."""

sv import from ..services.catalog { VideoView, TopicView, ProfileView }

def _is_http(u: str) -> bool {
    return u.startswith("https://") or u.startswith("http://");
}

def:pub SourcesSheet(
    video: VideoView, onClose: Callable[[], None], onReport: Callable[[str, str], None]
) -> JsxElement {
    has reported: bool = False;

    def close(e: MouseEvent) {
        onClose();
    }

    def stop(e: MouseEvent) {
        e.stopPropagation();
    }

    def report(reason: str) {
        reported = True;
        onReport(video.id, reason);
    }

    return <div className="sheet-backdrop" onClick={close}>
        <div className="sheet" onClick={stop}>
            <div className="sheet-handle"/>
            <h3>{video.title}</h3>
            {video.summary and <p className="sheet-summary">{video.summary}</p>}
            <div className="sheet-meta">
                <span>{video.topic_emoji + " " + video.topic_name}</span>
                <span>{"@" + video.creator_name}</span>
                {video.published_at and <span>{video.published_at[:10]}</span>}
            </div>
            {video.why and <p className="sheet-why"><strong>Why you're seeing this: </strong>{video.why}</p>}
            <p className="sheet-why">
                <strong>Quality check: </strong>
                {str(int(video.quality * 100)) + "/100 · " + (video.scored_by or "unscored")}
                {video.score_reason and (" · " + video.score_reason)}
            </p>
            {len(video.citations) > 0 and <div className="sheet-block">
                <h4>Sources</h4>
                <ul>
                    {for (i, u) in enumerate(video.citations) {
                        if _is_http(u) {
                            <li key={"c" + str(i)}><a href={u} target="_blank" rel="noopener noreferrer">{u.replace("https://", "")}</a></li>
                        }
                    }}
                </ul>
            </div>}
            {len(video.attributions) > 0 and <div className="sheet-block">
                <h4>Image credits</h4>
                <ul>{for (i, a) in enumerate(video.attributions) { <li key={"a" + str(i)} className="small">{a}</li> }}</ul>
            </div>}
            {video.source_url and _is_http(video.source_url) and <p>
                <a href={video.source_url} target="_blank" rel="noopener noreferrer">{"Watch on " + (video.provider or "source") + " ↗"}</a>
            </p>}
            <div className="sheet-actions">
                {reported and <span className="small">Thanks — flagged for review.</span>}
                {not reported and <>
                    <button className="pill ghost" onClick={lambda e: MouseEvent { report("inaccurate"); }}>Report inaccurate</button>
                    <button className="pill ghost" onClick={lambda e: MouseEvent { report("biased"); }}>Report biased</button>
                    <button className="pill ghost" onClick={lambda e: MouseEvent { report("broken"); }}>Broken</button>
                </>}
            </div>
        </div>
    </div>;
}

def:pub CheckinCard(
    minutes: float, videos: int, topics: int, goalReached: bool,
    onContinue: Callable[[], None], onBreak: Callable[[], None]
) -> JsxElement {
    return <div className="overlay">
        <div className="checkin">
            <div className="checkin-emoji">{"🎯" if goalReached else "🧠"}</div>
            <h2>{"Daily goal reached!" if goalReached else "Quick check-in"}</h2>
            <p>{"You've watched " + str(videos) + " videos across " + str(topics) + " topics in " + str(int(minutes)) + " minutes."}</p>
            <p className="small">Still learning, or just scrolling? Either answer is fine.</p>
            <div className="checkin-actions">
                <button className="pill" onClick={lambda e: MouseEvent { onContinue(); }}>Keep learning</button>
                <button className="pill ghost" onClick={lambda e: MouseEvent { onBreak(); }}>Take a break</button>
            </div>
        </div>
    </div>;
}

def:pub BreakScreen(onResume: Callable[[], None]) -> JsxElement {
    return <div className="overlay">
        <div className="checkin">
            <div className="checkin-emoji">🌿</div>
            <h2>Nice. Go do something with it.</h2>
            <p className="small">Tell someone one thing you learned today — it's the best way to remember it.</p>
            <button className="pill ghost" onClick={lambda e: MouseEvent { onResume(); }}>I'm back</button>
        </div>
    </div>;
}

def:pub Onboarding(
    topics: list[TopicView], onDone: Callable[[list[str], int, int], None]
) -> JsxElement {
    has picked: list[str] = [],
        goal: int = 20,
        every: int = 15;

    def toggle(slug: str) {
        if slug in picked {
            picked = [s for s in picked if s != slug];
        } else {
            picked = picked + [slug];
        }
    }

    def finish(e: MouseEvent) {
        onDone(picked, goal, every);
    }

    return <div className="overlay onboarding">
        <div className="onb">
            <h1>Scroll smarter.</h1>
            <p>Short videos, but only ones worth your time. Pick what you're curious about.</p>
            <div className="topic-grid">
                {for t in topics {
                    <button
                        key={t.slug}
                        className={"topic-chip on" if t.slug in picked else "topic-chip"}
                        onClick={lambda e: MouseEvent { toggle(t.slug); }}
                    >
                        <span className="topic-emoji">{t.emoji}</span>
                        <span>{t.name}</span>
                    </button>
                }}
            </div>
            <label className="onb-row">Daily goal
                <select value={str(goal)} onChange={lambda e: ChangeEvent { goal = int(e.target.value); }}>
                    <option value="10">10 min</option>
                    <option value="20">20 min</option>
                    <option value="30">30 min</option>
                    <option value="45">45 min</option>
                </select>
            </label>
            <label className="onb-row">Check in with me every
                <select value={str(every)} onChange={lambda e: ChangeEvent { every = int(e.target.value); }}>
                    <option value="10">10 min</option>
                    <option value="15">15 min</option>
                    <option value="25">25 min</option>
                    <option value="40">40 min</option>
                </select>
            </label>
            <button className="pill big" onClick={finish} disabled={len(picked) == 0}>
                {"Start learning" if len(picked) > 0 else "Pick at least one topic"}
            </button>
        </div>
    </div>;
}

def:pub TopicsPage(
    topics: list[TopicView], onWatch: Callable[[str], None], onFollow: Callable[[str, bool], None]
) -> JsxElement {
    return <div className="page-scroll">
        <h2 className="page-title">Topics</h2>
        <div className="topic-list">
            {for t in topics {
                <div key={t.slug} className="topic-card">
                    <div className="topic-head">
                        <span className="topic-emoji big">{t.emoji}</span>
                        <div>
                            <div className="topic-name">{t.name}</div>
                            <div className="small">{str(t.count) + " videos"}</div>
                        </div>
                    </div>
                    <p className="small">{t.description}</p>
                    <div className="topic-actions">
                        <button className="pill" onClick={lambda e: MouseEvent { onWatch(t.slug); }}>Watch</button>
                        <button
                            className={"pill ghost on" if t.followed else "pill ghost"}
                            onClick={lambda e: MouseEvent { onFollow(t.slug, not t.followed); }}
                        >{"Following" if t.followed else "Follow"}</button>
                    </div>
                </div>
            }}
        </div>
    </div>;
}

def:pub ProfilePage(profile: ProfileView | None, topics: list[TopicView]) -> JsxElement {
    if profile is None {
        return <div className="page-scroll"><p>Loading…</p></div>;
    }
    goal_pct = min(100, int(100.0 * profile.today_minutes / max(1, profile.daily_goal_min)));
    names = {t.slug: t.emoji + " " + t.name for t in topics};
    acc = int(100.0 * profile.quiz_correct / profile.quiz_total) if profile.quiz_total > 0 else 0;
    return <div className="page-scroll">
        <h2 className="page-title">You</h2>
        <div className="goal-ring" style={{"background": "conic-gradient(var(--accent) " + str(goal_pct) + "%, var(--panel2) 0)"}}>
            <div className="goal-inner">
                <div className="goal-num">{str(profile.today_minutes)}</div>
                <div className="small">{"of " + str(profile.daily_goal_min) + " min today"}</div>
            </div>
        </div>
        <div className="stats">
            <div className="stat"><b>{str(profile.streak_days)}</b><span>day streak</span></div>
            <div className="stat"><b>{str(profile.videos_watched)}</b><span>videos</span></div>
            <div className="stat"><b>{str(profile.minutes_watched)}</b><span>minutes</span></div>
            <div className="stat"><b>{str(acc) + "%"}</b><span>{"recall (" + str(profile.quiz_total) + ")"}</span></div>
        </div>
        {len(profile.top_topics) > 0 and <div className="sheet-block">
            <h4>You've been learning about</h4>
            <ul>{for s in profile.top_topics { <li key={s}>{names[s] or s}</li> }}</ul>
        </div>}
        <p className="small">{"Check-ins every " + str(profile.checkin_every) + " minutes."}</p>
    </div>;
}
