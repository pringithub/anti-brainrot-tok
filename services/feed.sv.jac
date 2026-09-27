"""Feed ranking (LoadFeed walker) and per-user interaction endpoints.

Per-user state is a Profile node under the caller's root plus one Engaged edge
per video the user touched (Profile -[Engaged]-> Video in the shared catalog).
"""

import re;
import math;
import random;
import from datetime { datetime, timezone, timedelta }
import from services.catalog {
    Topic, Video, InTopic, Profile, Engaged, Signal, Job, VideoView, QuizView, FeedItem, TopicView,
    ProfileView, RequestResult, all_topics, videos_of, topic_by_slug, video_by_id, signal_log,
    to_view, now_iso, today_str, job_queue, jobs
}

glob MAX_LIMIT: int = 12;
glob EXPLORE_SHARE: float = 0.18;
glob MAX_PENDING_REQUESTS: int = 3;
glob TTS_PREFS: set[str] = {"browser", "google", "elevenlabs"};
glob GENERATED_TOPIC_SLUG: str = "generated";

# ---------------------------------------------------------------- helpers

def _profile_or_none() -> Profile | None {
    profs = [root -->[?:Profile]];
    return profs[0] if profs else None;
}

def _ensure_profile() -> Profile {
    prof = _profile_or_none();
    if prof is not None {
        return prof;
    }
    return (root ++> Profile())[0];
}

def _engagements(prof: Profile | None) -> dict[str, Engaged] {
    if prof is None {
        return {};
    }
    return {e.video_id: e for e in [edge prof ->:Engaged:->]};
}

"""Get or create the caller's Engaged edge to a catalog video."""
def _engage(prof: Profile, v: Video) -> Engaged {
    vid = jid(v);
    for e in [edge prof ->:Engaged:-> v] {
        return e;
    }
    prof +>:Engaged(video_id=vid, topic=v.topic):+> v;
    return [edge prof ->:Engaged:-> v][0];
}

def _bump_interest(prof: Profile, topic: str, delta: float) {
    cur = prof.interests.get(topic, 0.0);
    updated = dict(prof.interests);
    updated[topic] = max(-1.0, min(2.5, cur * 0.98 + delta));
    prof.interests = updated;
}

def _signal(video_id: str, kind: str, note: str = "") {
    log = signal_log();
    if log is None {
        return;
    }
    sig = (log ++> Signal(video_id=video_id, kind=kind, at=now_iso(), note=note[:200]))[0];
    grant(sig, level=ReadPerm);
}

def _age_days(iso: str) -> float {
    if not iso {
        return 30.0;
    }
    try {
        dt = datetime.fromisoformat(iso.replace("Z", "+00:00"));
    } except ValueError {
        return 30.0;
    }
    if dt.tzinfo is None {
        dt = dt.replace(tzinfo=timezone.utc);
    }
    return max(0.0, (datetime.now(timezone.utc) - dt).total_seconds() / 86400.0);
}

def _profile_view(prof: Profile) -> ProfileView {
    interests = prof.interests;
    ranked = sorted(
        [k for k in interests.keys() if interests[k] > 0.0],
        key=lambda k: str : interests[k], reverse=True
    );
    return ProfileView(
        onboarded=prof.onboarded,
        followed=prof.followed,
        daily_goal_min=prof.daily_goal_min,
        checkin_every=prof.checkin_every,
        videos_watched=prof.videos_watched,
        minutes_watched=int(prof.seconds_watched / 6.0) / 10.0,
        today_minutes=int(prof.today_seconds / 6.0) / 10.0 if prof.day == today_str() else 0.0,
        today_videos=prof.today_videos if prof.day == today_str() else 0,
        streak_days=prof.streak_days,
        quiz_correct=prof.quiz_correct,
        quiz_total=prof.quiz_total,
        top_topics=ranked[:3],
        tts_pref=prof.tts_pref
    );
}

def _roll_day(prof: Profile) {
    today = today_str();
    if prof.day == today {
        return;
    }
    yesterday = (datetime.now(timezone.utc) - timedelta(days=1)).strftime("%Y-%m-%d");
    prof.streak_days = prof.streak_days + 1 if prof.day == yesterday else 1;
    prof.day = today;
    prof.today_seconds = 0.0;
    prof.today_videos = 0;
}

obj Scored {
    has video: Video,
        score: float,
        explore: bool = False;
}

def _why(v: Video, t: Topic, prof: Profile | None, explore: bool) -> str {
    if t.is_current_events {
        return "Fresh from " + t.name + " — reviewed for balance";
    }
    if explore {
        return "Exploring something new: " + t.name;
    }
    if prof is not None and v.topic in prof.followed {
        return "Because you follow " + t.name;
    }
    if prof is not None and prof.interests.get(v.topic, 0.0) > 0.4 {
        return "You've been learning about " + t.name;
    }
    return "High-quality pick in " + t.name;
}

"""Greedy re-rank: avoid 3 same-topic in a row and back-to-back same creator."""
def _diversify(items: list[Scored]) -> list[Scored] {
    pool = list(items);
    out: list[Scored] = [];
    while pool {
        pick = 0;
        for (i, s) in enumerate(pool) {
            same_topic = len(out) >= 2 and out[-1].video.topic == s.video.topic and out[-2].video.topic == s.video.topic;
            same_creator = len(out) >= 1 and out[-1].video.creator_id == s.video.creator_id;
            if not same_topic and not same_creator {
                pick = i;
                break;
            }
        }
        out.append(pool.pop(pick));
    }
    return out;
}

def _quiz_for(engaged: dict[str, Engaged], exclude: set[str]) -> QuizView | None {
    pending = [
        e for e in engaged.values()
        if e.completed and not e.quiz_answered and ("quiz:" + e.video_id) not in exclude
    ];
    pending = sorted(pending, key=lambda e: Engaged : e.last_at);
    for e in pending {
        v = video_by_id(e.video_id);
        if v is not None and v.quiz_answer >= 0 and len(v.quiz_choices) > 1 {
            return QuizView(
                video_id=jid(v), video_title=v.title, question=v.quiz_question,
                choices=v.quiz_choices, answer_idx=v.quiz_answer, explanation=v.quiz_explanation
            );
        }
    }
    return None;
}

# ------------------------------------------------------------ feed walker

"""Ranked feed page. Walks caller root -> shared Topic nodes -> Video nodes,
scoring each video on arrival, then ranks and reports once on exit.
mode: foryou | following | topic. `exclude` = item ids already shown."""
walker:pub LoadFeed {
    has mode: str = "foryou",
        topic: str = "",
        exclude: list[str] = [],
        limit: int = 8,
        reports: list[list[FeedItem]] = [];

    has profile: Profile | None = None,
        engaged: dict[str, Engaged] = {},
        weights: dict[str, float] = {},
        excluded: set[str] = set(),
        scored: list[Scored] = [],
        now: str = "";

    can start with Root entry {
        # Internal fields are reset so a caller can't pre-seed them in the request body.
        self.limit = max(1, min(self.limit, MAX_LIMIT));
        self.excluded = set(self.exclude[:500]);
        self.profile = _profile_or_none();
        self.engaged = _engagements(self.profile);
        self.weights = {};
        self.scored = [];
        self.now = now_iso();
        visit [root.shared -->[?:Topic]];
    }

    can weigh_topic with Topic entry {
        prof = self.profile;
        followed = prof.followed if prof is not None else [];
        if self.mode == "topic" and here.slug != self.topic {
            skip;
        }
        if self.mode == "following" and followed and here.slug not in followed {
            skip;
        }
        # "generated" mode spans every topic; score_video narrows it to kind=="generated".
        w = prof.interests.get(here.slug, 0.0) if prof is not None else 0.0;
        self.weights[here.slug] = max(0.3, min(2.5, 1.0 + w)) + (0.5 if here.slug in followed else 0.0);
        visit [here ->:InTopic:->];
    }

    can score_video with Video entry {
        if here.status != "live" or (here.expires_at and here.expires_at < self.now) {
            skip;
        }
        if self.mode == "generated" and here.kind != "generated" {
            skip;
        }
        vid = jid(here);
        if vid in self.excluded {
            skip;
        }
        e = self.engaged.get(vid);
        if e is not None and (e.not_useful or e.completed or e.views >= 2 or e.skipped) {
            skip;
        }
        age = _age_days(here.published_at or here.added_at);
        is_news = here.topic == "current-events";
        fresh = math.exp(-age / 2.0) if is_news else 1.0 + 0.15 * math.exp(-age / 14.0);
        s = (max(0.05, here.quality) ** 1.5) * self.weights.get(here.topic, 1.0) * fresh;
        s *= random.uniform(0.8, 1.2) * (1.05 if here.kind == "generated" else 1.0);
        self.scored.append(Scored(video=here, score=s));
    }

    can rank with Root exit {
        prof = self.profile;
        limit = self.limit;
        scored = sorted(self.scored, key=lambda s: Scored : s.score, reverse=True);
        # Reserve a share of slots for low-interest topics so the feed stays broad.
        n_explore = int(limit * EXPLORE_SHARE + 0.5) if prof is not None and self.mode == "foryou" else 0;
        picked = scored[:max(0, limit - n_explore)];
        ids = {jid(s.video) for s in picked};
        rest = [
            s for s in scored[limit:]
            if jid(s.video) not in ids and (prof is None or prof.interests.get(s.video.topic, 0.0) < 0.3)
        ];
        random.shuffle(rest);
        for s in rest[:n_explore] {
            s.explore = True;
            picked.append(s);
            ids.add(jid(s.video));
        }
        for s in scored {
            if len(picked) >= limit {
                break;
            }
            if jid(s.video) not in ids {
                picked.append(s);
                ids.add(jid(s.video));
            }
        }
        items: list[FeedItem] = [];
        for s in _diversify(picked) {
            t = topic_by_slug(s.video.topic);
            why = _why(s.video, t, prof, s.explore) if t is not None else "";
            items.append(FeedItem(kind="video", video=to_view(s.video, self.engaged.get(jid(s.video)), why)));
        }
        quiz = _quiz_for(self.engaged, self.excluded) if prof is not None else None;
        if quiz is not None and len(items) >= 3 {
            items.insert(3, FeedItem(kind="quiz", quiz=quiz));
        }
        report items;
    }
}

# ------------------------------------------------------------- public reads

def:pub list_topics() -> list[TopicView] {
    prof = _profile_or_none();
    followed = prof.followed if prof is not None else [];
    topics = [
        TopicView(
            slug=t.slug, name=t.name, emoji=t.emoji, description=t.description,
            count=len([v for v in videos_of(t) if v.status == "live"]),
            followed=(t.slug in followed), is_current_events=t.is_current_events
        )
        for t in all_topics()
    ];
    generated_count = sum(
        len([v for v in videos_of(t) if v.status == "live" and v.kind == "generated"])
        for t in all_topics()
    );
    topics.append(TopicView(
        slug=GENERATED_TOPIC_SLUG, name="Generated", emoji="✨",
        description="SmartTok's own AI-narrated explainers, fact-checked against the sources they cite.",
        count=generated_count, is_current_events=True, is_virtual=True
    ));
    return topics;
}

def:pub get_video(video_id: str) -> FeedItem | None {
    v = video_by_id(video_id);
    if v is None or v.status != "live" {
        return None;
    }
    view = to_view(v, _engagements(_profile_or_none()).get(video_id), "Shared with you");
    return FeedItem(kind="video", video=view);
}

# ------------------------------------------------------- authenticated writes

def:priv get_profile() -> ProfileView {
    prof = _ensure_profile();
    _roll_day(prof);
    return _profile_view(prof);
}

def:priv set_tts_pref(pref: str) -> ProfileView {
    prof = _ensure_profile();
    if pref in TTS_PREFS {
        prof.tts_pref = pref;
    }
    return _profile_view(prof);
}

def:priv save_onboarding(topic_slugs: list[str], daily_goal_min: int, checkin_every: int) -> ProfileView {
    prof = _ensure_profile();
    valid = [t.slug for t in all_topics()];
    chosen = [t for t in topic_slugs if t in valid][:8];
    prof.followed = chosen;
    seeded = dict(prof.interests);
    for t in chosen {
        seeded[t] = max(seeded.get(t, 0.0), 0.8);
    }
    prof.interests = seeded;
    prof.daily_goal_min = max(5, min(daily_goal_min, 240));
    prof.checkin_every = max(5, min(checkin_every, 120));
    prof.onboarded = True;
    return _profile_view(prof);
}

def:priv follow_topic(slug: str, on: bool) -> list[str] {
    prof = _ensure_profile();
    if topic_by_slug(slug) is None {
        return prof.followed;
    }
    current = [s for s in prof.followed if s != slug];
    if on {
        current.append(slug);
        _bump_interest(prof, slug, 0.3);
    }
    prof.followed = current;
    return current;
}

def _norm_subject(s: str) -> str {
    return re.sub("[^a-z0-9 ]", "", s.lower()).strip();
}

def _job_active(job_id: str) -> bool {
    try {
        j = jobj(job_id);
    } except Exception {
        return False;
    }
    return isinstance(j, Job) and j.status in ("queued", "running");
}

"""Queue a user-suggested subject for the generation pipeline to pick up.
Actual generation runs later (job worker), so this only enqueues a Job."""
def:priv request_generation(topic: str, subject: str) -> RequestResult {
    t = topic_by_slug(topic);
    if t is None {
        return RequestResult(ok=False, message="Unknown topic.");
    }
    if t.is_current_events {
        return RequestResult(ok=False, message="Current-events videos are curated automatically, not requested.");
    }
    subj = subject.strip()[:200];
    if not subj {
        return RequestResult(ok=False, message="Describe what you'd like a video about.");
    }
    prof = _ensure_profile();
    active = [j for j in prof.requested_jobs if _job_active(j)];
    if len(active) >= MAX_PENDING_REQUESTS {
        return RequestResult(ok=False, message="You have " + str(len(active)) + " requests pending — wait for those to finish.");
    }
    norm = _norm_subject(subj);
    for j in jobs("queued") + jobs("running") {
        if j.kind == "generate" and j.topic == topic and _norm_subject(j.subject) == norm {
            prof.requested_jobs = active;
            return RequestResult(ok=True, message="Already queued — we'll add it once it's generated.");
        }
    }
    q = job_queue();
    if q is None {
        return RequestResult(ok=False, message="Catalog isn't ready yet.");
    }
    job = (q ++> Job(kind="generate", topic=topic, subject=subj, reason="user request", created_at=now_iso()))[0];
    prof.requested_jobs = active + [jid(job)];
    return RequestResult(ok=True, message="Queued! New videos are generated in batches, check back soon.");
}

def:priv log_view(video_id: str, watch_s: float, completed: bool) -> ProfileView {
    prof = _ensure_profile();
    _roll_day(prof);
    v = video_by_id(video_id);
    if v is None {
        return _profile_view(prof);
    }
    watch = max(0.0, min(watch_s, 900.0));
    e = _engage(prof, v);
    e.views += 1;
    e.watch_s += watch;
    e.completed = e.completed or completed;
    e.skipped = (not e.completed) and watch < 2.5;
    e.last_at = now_iso();
    delta = 0.0;
    if completed {
        delta = 0.15;
    } elif watch >= 10.0 {
        delta = 0.05;
    } elif watch < 2.5 {
        delta = -0.1;
    }
    _bump_interest(prof, v.topic, delta);
    prof.videos_watched += 1;
    prof.seconds_watched += watch;
    prof.today_seconds += watch;
    prof.today_videos += 1;
    seen = dict(prof.topics_seen);
    seen[v.topic] = seen.get(v.topic, 0) + 1;
    prof.topics_seen = seen;
    if completed {
        _signal(video_id, "complete");
    } elif watch >= 2.5 {
        _signal(video_id, "view");
    } else {
        _signal(video_id, "skip");
    }
    return _profile_view(prof);
}

"""reaction: like | save | not_useful. Returns the updated view."""
def:priv set_reaction(video_id: str, reaction: str, on: bool) -> VideoView | None {
    v = video_by_id(video_id);
    if v is None or reaction not in ["like", "save", "not_useful"] {
        return None;
    }
    prof = _ensure_profile();
    e = _engage(prof, v);
    e.last_at = now_iso();
    if reaction == "like" {
        if on != e.liked {
            _bump_interest(prof, v.topic, 0.2 if on else -0.1);
        }
        e.liked = on;
    } elif reaction == "save" {
        if on != e.saved {
            _bump_interest(prof, v.topic, 0.3 if on else -0.1);
        }
        e.saved = on;
    } else {
        if on and not e.not_useful {
            _bump_interest(prof, v.topic, -0.6);
        }
        e.not_useful = on;
    }
    if on {
        _signal(video_id, reaction);
    }
    return to_view(v, e, "");
}

def:priv report_video(video_id: str, reason: str) -> bool {
    v = video_by_id(video_id);
    if v is None {
        return False;
    }
    prof = _ensure_profile();
    e = _engage(prof, v);
    if e.reported {
        return True;
    }
    e.reported = True;
    e.not_useful = True;
    _signal(video_id, "report", reason);
    return True;
}

def:priv answer_quiz(video_id: str, choice: int) -> bool {
    v = video_by_id(video_id);
    if v is None or v.quiz_answer < 0 {
        return False;
    }
    prof = _ensure_profile();
    e = _engage(prof, v);
    correct = choice == v.quiz_answer;
    if not e.quiz_answered {
        e.quiz_answered = True;
        e.quiz_correct = correct;
        prof.quiz_total += 1;
        if correct {
            prof.quiz_correct += 1;
        }
    }
    return correct;
}

def:priv list_saved() -> list[FeedItem] {
    prof = _ensure_profile();
    engaged = _engagements(prof);
    out: list[FeedItem] = [];
    for v in [prof ->:Engaged:->] {
        e = engaged.get(jid(v));
        if e is not None and e.saved and v.status == "live" {
            out.append(FeedItem(kind="video", video=to_view(v, e, "Saved by you")));
        }
    }
    return out;
}
