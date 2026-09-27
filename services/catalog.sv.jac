"""Catalog data model: topics, videos, creators, per-user state, and view models.

Catalog nodes live on `root.shared` and are written only from anonymous
admin-key endpoints (so the shared guest root owns them). Per-user state
(Profile, Interaction) lives under each user's own root.
"""

import json;
import os;
import hmac;
import from datetime { datetime, timezone }

glob STUDIO_NAME: str = "SmartTok Studio";

glob TAXONOMY: list[dict[str, str]] = [
    {"slug": "current-events", "name": "Current Events", "emoji": "🌍", "description": "What happened, from multiple sources, without spin."},
    {"slug": "engineering", "name": "Engineering", "emoji": "⚙️", "description": "How things are built and why they work."},
    {"slug": "science", "name": "Science", "emoji": "🔬", "description": "Physics, chemistry, biology, space and the natural world."},
    {"slug": "history", "name": "History", "emoji": "🏛️", "description": "People, empires, ideas and how we got here."},
    {"slug": "languages", "name": "Linguistics & Languages", "emoji": "🗣️", "description": "Words, etymology, sounds and learning languages."},
    {"slug": "math", "name": "Math & Logic", "emoji": "➗", "description": "Patterns, proofs and puzzles."},
    {"slug": "diy", "name": "DIY & Skills", "emoji": "🛠️", "description": "Repair, build and make things yourself."},
    {"slug": "geography", "name": "Geography & Civics", "emoji": "🗺️", "description": "Places, borders, systems and how societies run."}
];

# Channel ids verified against YouTube RSS (canonical channel link + feed title).
glob SEED_CHANNELS: list[dict[str, str]] = [
    {"id": "UCHnyfMqiRRG1u-2MsSQLbXA", "name": "Veritasium", "topic": "science"},
    {"id": "UCsXVk37bltHxD1rDPwtNM8Q", "name": "Kurzgesagt – In a Nutshell", "topic": "science"},
    {"id": "UCUHW94eEFW7hkUMVaZz4eDg", "name": "minutephysics", "topic": "science"},
    {"id": "UCEIwxahdLz7bap-VDs9h35A", "name": "Steve Mould", "topic": "science"},
    {"id": "UCCWeRTgd79JL0ilH0ZywSJA", "name": "AlphaPhoenix", "topic": "science"},
    {"id": "UCzR-rom72PHN9Zg7RML9EbA", "name": "PBS Eons", "topic": "science"},
    {"id": "UCZYTClx2T1of7BRZ86-8fow", "name": "SciShow", "topic": "science"},
    {"id": "UCLA_DiR1FfKNvjuUpBHmylQ", "name": "NASA", "topic": "science"},
    {"id": "UCsooa4yRKGN_zEE8iknghZA", "name": "TED-Ed", "topic": "science"},
    {"id": "UCMOqf8ab-42UUQIdVoKwjlQ", "name": "Practical Engineering", "topic": "engineering"},
    {"id": "UC6107grRI4m0o2-emgoDnAA", "name": "SmarterEveryDay", "topic": "engineering"},
    {"id": "UCR1IuLEqb6UEA_zQ81kwXfg", "name": "Real Engineering", "topic": "engineering"},
    {"id": "UCXAS_Ekkq0iFJ9dSUIkcAkw", "name": "The Efficient Engineer", "topic": "engineering"},
    {"id": "UC22BdTgxefuvUivrjesETjg", "name": "History Matters", "topic": "history"},
    {"id": "UCX6b17PVsYBQ0ip5gyeme-Q", "name": "CrashCourse", "topic": "history"},
    {"id": "UCodbH5mUeF-m_BsNueRDjcw", "name": "Overly Sarcastic Productions", "topic": "history"},
    {"id": "UCMk_WSPy3EE16aK5HLzCJzw", "name": "NativLang", "topic": "languages"},
    {"id": "UCNhX3WQEkraW3VHPyup8jkQ", "name": "Langfocus", "topic": "languages"},
    {"id": "UC4a9LfdavRlVMaSSWFdIciA", "name": "RobWords", "topic": "languages"},
    {"id": "UCoxcjq-8xIDTYp3uz647V5A", "name": "Numberphile", "topic": "math"},
    {"id": "UCYO_jab_esuFRV4b17AJtAw", "name": "3Blue1Brown", "topic": "math"},
    {"id": "UCUtWNBWbFL9We-cdXkiAuJA", "name": "This Old House", "topic": "diy"},
    {"id": "UCnorhjQR4zJkT7AVNhu395Q", "name": "Home RenoVision DIY", "topic": "diy"},
    {"id": "UCBa659QWEk1AI4Tg--mrJ2A", "name": "Tom Scott", "topic": "geography"},
    {"id": "UC2C_jShtL725hvbm1arSV9w", "name": "CGP Grey", "topic": "geography"},
    {"id": "UC9RM-iSvTu1uPJb8X5yp3EQ", "name": "Wendover Productions", "topic": "geography"},
    {"id": "UChqUTb7kYRX8-EiaN3XFrSQ", "name": "Reuters", "topic": "current-events"},
    {"id": "UC52X5wxOL_s5yw0dQk7NtgA", "name": "Associated Press", "topic": "current-events"},
    {"id": "UC6ZFN9Tx6xh-skXCuRHCDpQ", "name": "PBS NewsHour", "topic": "current-events"},
    {"id": "UC16niRr50-MSBwiO3YDb3RA", "name": "BBC News", "topic": "current-events"},
    {"id": "UCknLrEdhRCp1aegoMqRaCZg", "name": "DW News", "topic": "current-events"},
    {"id": "UCHnj59g7jezwTy5GeL8EA_g", "name": "MindYourDecisions", "topic": "math"},
    {"id": "UCRfo-DAifrP3lzcxUHtGm_A", "name": "Tom Rocks Maths", "topic": "math"},
    {"id": "UCGF5erKtI4NYUVfkmoEm2sg", "name": "polymathematic", "topic": "math"},
    {"id": "UCEWpbFLzoYGPfuWUMFPSaoA", "name": "The Organic Chemistry Tutor", "topic": "math"},
    {"id": "UC_SvYP0k05UKiJ_2ndB02IA", "name": "blackpenredpen", "topic": "math"},
    {"id": "UCzr30osBdTmuFUS8IfXtXmg", "name": "Essential Craftsman", "topic": "diy"},
    {"id": "UCP2vaEZS8MvZrFklwBtW1GA", "name": "Home Repair Tutor", "topic": "diy"},
    {"id": "UCstwpLSByklww1YojZN-KiQ", "name": "Stumpy Nubs", "topic": "diy"},
    {"id": "UCraGaDLfWec67xl9FEPndtw", "name": "See Jane Drill", "topic": "diy"},
    {"id": "UCy_QZ1EEY4S5YT6cmBTwMwg", "name": "Name Explain", "topic": "languages"},
    {"id": "UCLNoXf8gq6vhwsrYp-l0J-Q", "name": "Xiaomanyc", "topic": "languages"},
    {"id": "UCouyFdE9-Lrjo3M_2idKq1A", "name": "Dreaming Spanish", "topic": "languages"},
    {"id": "UCbxb2fqe9oNgglAoYqsYOtQ", "name": "Easy German", "topic": "languages"},
    {"id": "UCMmaBzfCCwZ2KqaBJjkj0fw", "name": "Kings and Generals", "topic": "history"},
    {"id": "UCeUJFQ0D9qs6aVNyUt9fkeQ", "name": "The Armchair Historian", "topic": "history"},
    {"id": "UCmmPgObSUPw1HL2lq6H4ffA", "name": "Geography Now", "topic": "geography"},
    {"id": "UCP5tjEmvPItGyLhmjdwP7Ww", "name": "RealLifeLore", "topic": "geography"},
    {"id": "UCuCkxoKLYO_EQ2GeFtbM_bw", "name": "Half as Interesting", "topic": "geography"},
    {"id": "UCbbQalJ4OaC0oQ0AqRaOJ9g", "name": "Map Men", "topic": "geography"},
    {"id": "UC1raaXFgsFBSFR8qNgchF2g", "name": "Geodiode", "topic": "geography"},
    {"id": "UCZ6Qas2nqiX98L0NwqfVT7A", "name": "Geography King", "topic": "geography"},
    {"id": "UCmYesELO6axBrCuSpf7S9DQ", "name": "Mr. Beat", "topic": "geography"},
    {"id": "UC510QYlOlKNyhy_zdQxnGYw", "name": "Simple History", "topic": "history"},
    {"id": "UCdp4_l1vPmpN-gDbUwhaRUQ", "name": "Branch Education", "topic": "engineering"},
    {"id": "UC6n8I1UDTKP1IWjQMg6_TwA", "name": "The B1M", "topic": "engineering"},
    {"id": "UC2bkHVIDjXS7sgrgjFtzOXQ", "name": "engineerguy", "topic": "engineering"},
    {"id": "UCxzC4EngIsMrPmbm6Nxvb-A", "name": "Scott Manley", "topic": "science"}
];

# ---------------------------------------------------------------- catalog nodes

node Topic {
    has slug: str,
        name: str,
        emoji: str = "",
        description: str = "",
        is_current_events: bool = False;
}

node Video {
    has kind: str,
        title: str,
        topic: str,
        status: str = "pending",
        summary: str = "",
        tags: list[str] = [],
        duration_s: float = 0.0,
        language: str = "en",
        quality: float = 0.0,
        scores: dict[str, float] = {},
        score_reason: str = "",
        scored_by: str = "",
        published_at: str = "",
        added_at: str = "",
        expires_at: str = "",
        creator_name: str = "",
        creator_id: str = "",
        provider: str = "",
        external_id: str = "",
        source_url: str = "",
        thumbnail_url: str = "",
        manifest_json: str = "",
        citations: list[str] = [],
        attributions: list[str] = [],
        quiz_question: str = "",
        quiz_choices: list[str] = [],
        quiz_answer: int = -1,
        quiz_explanation: str = "",
        review_notes: list[str] = [],
        stat_views: int = 0,
        stat_completes: int = 0,
        stat_likes: int = 0,
        stat_saves: int = 0,
        stat_not_useful: int = 0,
        stat_reports: int = 0;
}

edge InTopic: Topic --> Video {}

node Creator {
    has provider: str,
        external_id: str,
        name: str,
        topic: str,
        trust: float = 0.7,
        accepted: int = 0,
        rejected: int = 0,
        blocked: bool = False,
        last_checked: str = "";
}

node SignalLog {
    has label: str = "signals";
}

node Signal {
    has video_id: str,
        kind: str,
        at: str,
        note: str = "";
}

node PipelineRun {
    has kind: str,
        started_at: str,
        finished_at: str = "",
        stats: dict[str, int] = {},
        notes: list[str] = [];
}

# ----------------------------------------------------------- per-user nodes

node Profile {
    has onboarded: bool = False,
        interests: dict[str, float] = {},
        followed: list[str] = [],
        daily_goal_min: int = 20,
        checkin_every: int = 15,
        videos_watched: int = 0,
        seconds_watched: float = 0.0,
        quiz_correct: int = 0,
        quiz_total: int = 0,
        day: str = "",
        today_seconds: float = 0.0,
        today_videos: int = 0,
        streak_days: int = 0,
        topics_seen: dict[str, int] = {},
        requested_jobs: list[str] = [],
        tts_pref: str = "elevenlabs";
}

# User -> catalog video. Owned by the user, so other users can't read its fields.
# video_id is denormalised so one edge scan builds a lookup map.
edge Engaged: Profile --> Video {
    has video_id: str,
        topic: str = "",
        views: int = 0,
        watch_s: float = 0.0,
        completed: bool = False,
        skipped: bool = False,
        liked: bool = False,
        saved: bool = False,
        not_useful: bool = False,
        reported: bool = False,
        quiz_answered: bool = False,
        quiz_correct: bool = False,
        last_at: str = "";
}

node JobQueue {
    has label: str = "jobs";
}

node Job {
    has kind: str,
        topic: str,
        subject: str = "",
        reason: str = "",
        status: str = "queued",
        attempts: int = 0,
        created_at: str = "",
        finished_at: str = "",
        result: str = "";
}

# --------------------------------------------------------------- view models

obj VideoView {
    has id: str,
        kind: str,
        title: str,
        topic: str,
        topic_name: str = "",
        topic_emoji: str = "",
        summary: str = "",
        tags: list[str] = [],
        duration_s: float = 0.0,
        creator_name: str = "",
        provider: str = "",
        external_id: str = "",
        embed_url: str = "",
        source_url: str = "",
        thumbnail_url: str = "",
        manifest_json: str = "",
        citations: list[str] = [],
        attributions: list[str] = [],
        quality: float = 0.0,
        scored_by: str = "",
        score_reason: str = "",
        published_at: str = "",
        has_quiz: bool = False,
        liked: bool = False,
        saved: bool = False,
        why: str = "";
}

obj QuizView {
    has video_id: str,
        video_title: str,
        question: str,
        choices: list[str],
        answer_idx: int,
        explanation: str = "";
}

obj FeedItem {
    has kind: str,
        video: VideoView | None = None,
        quiz: QuizView | None = None;
}

obj TopicView {
    has slug: str,
        name: str,
        emoji: str,
        description: str,
        count: int = 0,
        followed: bool = False,
        is_current_events: bool = False,
        is_virtual: bool = False;
}

obj RequestResult {
    has ok: bool,
        message: str = "";
}

obj ProfileView {
    has onboarded: bool,
        followed: list[str],
        daily_goal_min: int,
        checkin_every: int,
        videos_watched: int,
        minutes_watched: float,
        today_minutes: float,
        today_videos: int,
        streak_days: int,
        quiz_correct: int,
        quiz_total: int,
        top_topics: list[str] = [],
        tts_pref: str = "elevenlabs";
}

obj ReviewItem {
    has id: str,
        kind: str,
        status: str,
        title: str,
        topic: str,
        creator_name: str,
        quality: float,
        scored_by: str,
        score_reason: str,
        source_url: str,
        review_notes: list[str] = [],
        stat_not_useful: int = 0,
        stat_reports: int = 0;
}

# ------------------------------------------------------------------- helpers

def now_iso() -> str {
    return datetime.now(timezone.utc).isoformat(timespec="seconds");
}

def today_str() -> str {
    return datetime.now(timezone.utc).strftime("%Y-%m-%d");
}

def all_topics() -> list[Topic] {
    return [root.shared -->[?:Topic]];
}

def topic_by_slug(slug: str) -> Topic | None {
    for t in all_topics() {
        if t.slug == slug {
            return t;
        }
    }
    return None;
}

def videos_of(t: Topic) -> list[Video] {
    return [t ->:InTopic:->];
}

def all_videos() -> list[Video] {
    out: list[Video] = [];
    for t in all_topics() {
        out.extend(videos_of(t));
    }
    return out;
}

def find_video(provider: str, external_id: str) -> Video | None {
    for v in all_videos() {
        if v.provider == provider and v.external_id == external_id {
            return v;
        }
    }
    return None;
}

def video_by_id(video_id: str) -> Video | None {
    if not video_id {
        return None;
    }
    try {
        target = jobj(video_id);
    } except Exception {
        return None;
    }
    if isinstance(target, Video) {
        return target;
    }
    return None;
}

def signal_log() -> SignalLog | None {
    logs = [root.shared -->[?:SignalLog]];
    return logs[0] if logs else None;
}

def all_creators() -> list[Creator] {
    return [root.shared -->[?:Creator]];
}

def job_queue() -> JobQueue | None {
    qs = [root.shared -->[?:JobQueue]];
    return qs[0] if qs else None;
}

def jobs(status: str) -> list[Job] {
    q = job_queue();
    if q is None {
        return [];
    }
    return [j for j in [q -->[?:Job]] if not status or j.status == status];
}

"""Create taxonomy topics, the signal log and seed creators. Must run anonymously
so the shared guest root owns the catalog. Idempotent."""
def ensure_catalog() -> dict[str, int] {
    created: dict[str, int] = {"topics": 0, "creators": 0, "signal_log": 0};
    existing = {t.slug: t for t in all_topics()};
    for spec in TAXONOMY {
        if spec["slug"] not in existing {
            t = (root.shared ++> Topic(
                slug=spec["slug"],
                name=spec["name"],
                emoji=spec["emoji"],
                description=spec["description"],
                is_current_events=(spec["slug"] == "current-events")
            ))[0];
            grant(t, level=ReadPerm);
            created["topics"] += 1;
        }
    }
    if signal_log() is None {
        log = (root.shared ++> SignalLog())[0];
        grant(log, level=ConnectPerm);
        created["signal_log"] = 1;
    }
    q = job_queue();
    if q is None {
        q = (root.shared ++> JobQueue())[0];
    }
    # ConnectPerm lets authenticated users enqueue their own generation requests.
    grant(q, level=ConnectPerm);
    for v in all_videos() {
        grant(v, level=ConnectPerm);
        if v.provider == "abt" and v.creator_name != STUDIO_NAME {
            v.creator_name = STUDIO_NAME;
        }
    }
    known = {c.external_id for c in all_creators()};
    for ch in SEED_CHANNELS {
        if ch["id"] not in known {
            root.shared ++> Creator(
                provider="youtube", external_id=ch["id"], name=ch["name"], topic=ch["topic"]
            );
            created["creators"] += 1;
        }
    }
    return created;
}

"""Attach a new video under its topic and open it to all readers."""
def add_video(v: Video) -> Video | None {
    t = topic_by_slug(v.topic);
    if t is None {
        return None;
    }
    if not v.added_at {
        v.added_at = now_iso();
    }
    t +>:InTopic:+> v;
    # ConnectPerm (includes read) lets users attach their own Engaged edges.
    grant(v, level=ConnectPerm);
    return v;
}

def embed_url_for(v: Video) -> str {
    if v.provider == "youtube" and v.external_id {
        return (
            "https://www.youtube-nocookie.com/embed/" + v.external_id
            + "?autoplay=1&playsinline=1&rel=0&modestbranding=1&enablejsapi=1&loop=1&playlist=" + v.external_id
        );
    }
    return "";
}

def to_view(v: Video, eng: Engaged | None, why: str) -> VideoView {
    t = topic_by_slug(v.topic);
    return VideoView(
        id=jid(v),
        kind=v.kind,
        title=v.title,
        topic=v.topic,
        topic_name=t.name if t is not None else v.topic,
        topic_emoji=t.emoji if t is not None else "",
        summary=v.summary,
        tags=v.tags,
        duration_s=v.duration_s,
        creator_name=v.creator_name,
        provider=v.provider,
        external_id=v.external_id,
        embed_url=embed_url_for(v),
        source_url=v.source_url,
        thumbnail_url=v.thumbnail_url,
        manifest_json=v.manifest_json,
        citations=v.citations,
        attributions=v.attributions,
        quality=r3(v.quality),
        scored_by=v.scored_by,
        score_reason=v.score_reason,
        published_at=v.published_at,
        has_quiz=(v.quiz_answer >= 0 and len(v.quiz_choices) > 1),
        liked=eng.liked if eng is not None else False,
        saved=eng.saved if eng is not None else False,
        why=why
    );
}

def to_review_item(v: Video) -> ReviewItem {
    return ReviewItem(
        id=jid(v),
        kind=v.kind,
        status=v.status,
        title=v.title,
        topic=v.topic,
        creator_name=v.creator_name,
        quality=r3(v.quality),
        scored_by=v.scored_by,
        score_reason=v.score_reason,
        source_url=v.source_url,
        review_notes=v.review_notes,
        stat_not_useful=v.stat_not_useful,
        stat_reports=v.stat_reports
    );
}

"""Return "" when the caller may administer the catalog, else the reason.
Admin calls must be anonymous so catalog nodes stay owned by the shared root."""
def admin_error(admin_key: str) -> str {
    expected = os.environ.get("ABT_ADMIN_KEY", "");
    if len(expected) < 12 {
        return "admin disabled: set ABT_ADMIN_KEY (>= 12 chars)";
    }
    if not hmac.compare_digest(admin_key.encode("utf-8"), expected.encode("utf-8")) {
        return "forbidden";
    }
    if jid(root) != jid(root.shared) {
        return "admin calls must be anonymous (no Authorization header)";
    }
    return "";
}

def safe_json(data: object) -> str {
    return json.dumps(data, ensure_ascii=False, separators=(",", ":"));
}

def r3(x: float) -> float {
    return int(x * 1000.0 + 0.5) / 1000.0;
}

def clamp01(x: float) -> float {
    return max(0.0, min(1.0, x));
}
