"""Curation pipeline: discover Shorts from allowlisted channels via keyless
YouTube RSS, prefilter, score (LLM or heuristic) and publish/queue/reject."""

import requests;
import from xml.etree.ElementTree { Element }
import from defusedxml.ElementTree { fromstring }
import from services.catalog {
    Video, Creator, PipelineRun, all_creators, all_videos, add_video, now_iso, clamp01,
    TAXONOMY
}
import from services.ai { llm_enabled, llm_score_video, heuristic_score, LLM_MODEL_NAME, Verdict }

glob _NS: dict[str, str] = {
    "atom": "http://www.w3.org/2005/Atom",
    "yt": "http://www.youtube.com/xml/schemas/2015",
    "media": "http://search.yahoo.com/mrss/"
};

glob HTTP_HEADERS: dict[str, str] = {
    "User-Agent": "SmartTok/0.1 (educational feed; contact: admin@localhost)"
};

obj RssEntry {
    has video_id: str,
        title: str,
        published: str,
        description: str,
        thumbnail: str,
        views: int,
        url: str;
}

obj ScoreResult {
    has status: str,
        quality: float,
        topic: str,
        scores: dict[str, float],
        reason: str,
        summary: str,
        scored_by: str;
}

def _text(el: Element, path: str) -> str {
    found = el.find(path, _NS);
    if found is None or found.text is None {
        return "";
    }
    return str(found.text).strip();
}

def _attr(el: Element, path: str, name: str) -> str {
    found = el.find(path, _NS);
    if found is None {
        return "";
    }
    return str(found.get(name, ""));
}

"""Fetch the Shorts-only uploads playlist feed for a channel (max ~15 entries)."""
def fetch_channel_shorts(channel_id: str) -> list[RssEntry] {
    if not channel_id.startswith("UC") or len(channel_id) != 24 {
        return [];
    }
    url = "https://www.youtube.com/feeds/videos.xml?playlist_id=UUSH" + channel_id[2:];
    resp = requests.get(url, headers=HTTP_HEADERS, timeout=15);
    if resp.status_code != 200 {
        return [];
    }
    tree = fromstring(resp.content) as Element;
    out: list[RssEntry] = [];
    for item in tree.findall("atom:entry", _NS) {
        vid = _text(item, "yt:videoId");
        if not vid {
            continue;
        }
        link = _attr(item, "atom:link", "href");
        views = 0;
        try {
            views = int(_attr(item, "media:group/media:community/media:statistics", "views") or "0");
        } except ValueError {
            views = 0;
        }
        out.append(RssEntry(
            video_id=vid,
            title=_text(item, "atom:title"),
            published=_text(item, "atom:published"),
            description=_text(item, "media:group/media:description"),
            thumbnail=_attr(item, "media:group/media:thumbnail", "url"),
            views=views,
            url=link or ("https://www.youtube.com/shorts/" + vid)
        ));
    }
    return out;
}

def _update_trust(c: Creator, accepted: bool) {
    if accepted {
        c.accepted += 1;
    } else {
        c.rejected += 1;
    }
    # Beta prior (7 accepts / 3 rejects) so a few outcomes don't swing trust.
    c.trust = (c.accepted + 7.0) / (c.accepted + c.rejected + 10.0);
}

"""Score one entry with the LLM when available, else the keyword heuristic."""
def score_entry(e: RssEntry, c: Creator, use_llm: bool) -> ScoreResult {
    is_current = c.topic == "current-events";
    allowed = [t["slug"] for t in TAXONOMY];
    if use_llm {
        try {
            s = llm_score_video(e.title, c.name, e.description[:1500], c.topic, allowed);
            topic = s.topic if s.topic in allowed else c.topic;
            quality = clamp01(
                0.30 * s.accuracy + 0.25 * s.density + 0.15 * s.clarity
                + 0.20 * s.educational + 0.10 * (1.0 - s.clickbait)
            );
            status = "rejected";
            if s.verdict == Verdict.ACCEPT and quality >= 0.6 and s.clickbait < 0.5 {
                status = "live";
            } elif s.verdict != Verdict.REJECT and quality >= 0.45 {
                status = "review";
            }
            # Current events always get a human look before going live.
            if topic == "current-events" and status == "live" {
                status = "review";
            }
            return ScoreResult(
                status=status, quality=quality, topic=topic,
                scores={
                    "accuracy": s.accuracy, "density": s.density, "clarity": s.clarity,
                    "clickbait": s.clickbait, "bias": s.bias, "educational": s.educational
                },
                reason=s.reason, summary=s.summary, scored_by="llm:" + LLM_MODEL_NAME
            );
        } except Exception as err {
            print("[curate] LLM scoring failed, using heuristic:", str(err)[:200]);
        }
    }
    h = heuristic_score(e.title, e.description, c.trust, is_current);
    status = "rejected";
    if h["verdict"] >= 1.0 {
        status = "live";
    } elif h["verdict"] > 0.0 {
        status = "review";
    }
    return ScoreResult(
        status=status, quality=h["quality"], topic=c.topic,
        scores={"clickbait": h["clickbait"], "educational": h["educational"]},
        reason="heuristic: channel trust + title cues", summary="", scored_by="heuristic"
    );
}

"""Run one curation pass over allowlisted creators. Must run anonymously."""
def run_curation(max_per_channel: int, channel_filter: str, topic_filter: str = "") -> dict[str, int] {
    run = PipelineRun(kind="curation", started_at=now_iso());
    stats: dict[str, int] = {
        "channels": 0, "fetched": 0, "new": 0, "live": 0, "review": 0, "rejected": 0,
        "errors": 0
    };
    seen = {v.provider + ":" + v.external_id for v in all_videos()};
    use_llm = llm_enabled();
    for c in all_creators() {
        if c.blocked or c.provider != "youtube" {
            continue;
        }
        if channel_filter and channel_filter.lower() not in c.name.lower() {
            continue;
        }
        if topic_filter and c.topic != topic_filter {
            continue;
        }
        stats["channels"] += 1;
        try {
            entries = fetch_channel_shorts(c.external_id);
        } except Exception as err {
            stats["errors"] += 1;
            run.notes.append(c.name + ": " + str(err)[:120]);
            continue;
        }
        c.last_checked = now_iso();
        stats["fetched"] += len(entries);
        taken = 0;
        for e in entries {
            if taken >= max_per_channel {
                break;
            }
            key = "youtube:" + e.video_id;
            if key in seen {
                continue;
            }
            seen.add(key);
            taken += 1;
            stats["new"] += 1;
            r = score_entry(e, c, use_llm);
            status = r.status;
            v = Video(
                kind="curated",
                title=e.title[:200],
                topic=r.topic,
                status=status,
                summary=r.summary,
                quality=r.quality,
                scores=r.scores,
                score_reason=r.reason,
                scored_by=r.scored_by,
                published_at=e.published,
                duration_s=60.0,
                creator_name=c.name,
                creator_id=c.external_id,
                provider="youtube",
                external_id=e.video_id,
                source_url=e.url,
                thumbnail_url=e.thumbnail
            );
            if add_video(v) is None {
                stats["errors"] += 1;
                continue;
            }
            stats[status] = stats.get(status, 0) + 1;
            if status != "review" {
                _update_trust(c, status == "live");
            }
        }
    }
    run.stats = stats;
    run.finished_at = now_iso();
    root.shared ++> run;
    return stats;
}
