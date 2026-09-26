"""Admin endpoints (catalog writes). Gated by the ABT_ADMIN_KEY env var and
required to run anonymously, so the shared guest root owns catalog nodes.
Use tools/admin.jac to call these from the command line."""

import from services.catalog {
    Video, Signal, PipelineRun, ReviewItem, ensure_catalog, all_videos, all_topics, all_creators,
    video_by_id, signal_log, to_review_item, now_iso, admin_error
}
import from services.curation { run_curation }
import from services.generation { GenerationResult, generate_from_subject, publish_script }
import from services.seeds { seed_videos }
import from services.ai { llm_enabled, LLM_MODEL_NAME }
import from services.generation { elevenlabs_enabled }
import from services.planner { JobResult, run_jobs }
import from services.catalog { Job, jobs }

glob VALID_STATUSES: list[str] = ["live", "review", "rejected", "pending"];

def _require_admin(admin_key: str) {
    err = admin_error(admin_key);
    if err {
        raise PermissionError(err);
    }
}

def:pub admin_bootstrap(admin_key: str, with_seeds: bool) -> dict[str, int] {
    _require_admin(admin_key);
    out = ensure_catalog();
    out["seeded"] = 0;
    if with_seeds {
        for sv in seed_videos() {
            r = publish_script(sv.to_script(), sv.topic, sv.citations);
            if r.ok and r.message != "already exists" {
                out["seeded"] += 1;
            }
        }
    }
    return out;
}

def:pub admin_curate(admin_key: str, max_per_channel: int, channel: str) -> dict[str, int] {
    _require_admin(admin_key);
    ensure_catalog();
    return run_curation(max(1, min(max_per_channel, 15)), channel);
}

def:pub admin_generate(admin_key: str, subject: str, topic: str) -> GenerationResult {
    _require_admin(admin_key);
    if not subject.strip() or len(subject) > 200 {
        return GenerationResult(ok=False, message="subject must be 1-200 chars");
    }
    if topic not in [t.slug for t in all_topics()] {
        return GenerationResult(ok=False, message="unknown topic");
    }
    return generate_from_subject(subject.strip(), topic);
}

def:pub admin_review_queue(admin_key: str, status: str) -> list[ReviewItem] {
    _require_admin(admin_key);
    items = [to_review_item(v) for v in all_videos() if v.status == status];
    return sorted(items, key=lambda r: ReviewItem : r.quality, reverse=True)[:200];
}

def:pub admin_set_status(admin_key: str, video_id: str, status: str) -> ReviewItem | None {
    _require_admin(admin_key);
    if status not in VALID_STATUSES {
        return None;
    }
    v = video_by_id(video_id);
    if v is None {
        return None;
    }
    v.status = status;
    v.review_notes = v.review_notes + ["status -> " + status + " at " + now_iso()];
    return to_review_item(v);
}

def:pub admin_block_creator(admin_key: str, name: str, blocked: bool) -> int {
    _require_admin(admin_key);
    n = 0;
    for c in all_creators() {
        if c.name.lower() == name.lower() {
            c.blocked = blocked;
            n += 1;
        }
    }
    return n;
}

"""Fold user signals into video stats; demote videos users flag as not useful."""
def:pub admin_rescore(admin_key: str) -> dict[str, int] {
    _require_admin(admin_key);
    log = signal_log();
    if log is None {
        return {"signals": 0};
    }
    videos = {jid(v): v for v in all_videos()};
    counts: dict[str, dict[str, int]] = {};
    total = 0;
    for s in [log -->[?:Signal]] {
        total += 1;
        per = counts.get(s.video_id, {});
        per[s.kind] = per.get(s.kind, 0) + 1;
        counts[s.video_id] = per;
    }
    demoted = 0;
    for (vid, per) in counts.items() {
        v = videos.get(vid);
        if v is None {
            continue;
        }
        v.stat_views = per.get("view", 0) + per.get("complete", 0) + per.get("skip", 0);
        v.stat_completes = per.get("complete", 0);
        v.stat_likes = per.get("like", 0);
        v.stat_saves = per.get("save", 0);
        v.stat_not_useful = per.get("not_useful", 0);
        v.stat_reports = per.get("report", 0);
        views = max(1, v.stat_views);
        bad_rate = (v.stat_not_useful + 2 * v.stat_reports) / views;
        if v.status == "live" and ((views >= 5 and bad_rate > 0.3) or v.stat_reports >= 3) {
            v.status = "review";
            v.review_notes = v.review_notes + ["auto-demoted by user signals at " + now_iso()];
            demoted += 1;
        }
    }
    return {"signals": total, "videos": len(counts), "demoted": demoted};
}

def:pub admin_stats(admin_key: str) -> dict[str, int] {
    _require_admin(admin_key);
    out: dict[str, int] = {
        "topics": len(all_topics()), "creators": len(all_creators()),
        "llm_enabled": 1 if llm_enabled() else 0, "tts_elevenlabs": 1 if elevenlabs_enabled() else 0
    };
    for v in all_videos() {
        key = v.kind + "_" + v.status;
        out[key] = out.get(key, 0) + 1;
    }
    out["runs"] = len([root.shared -->[?:PipelineRun]]);
    out["jobs_queued"] = len(jobs("queued"));
    return out;
}

def:pub admin_list_jobs(admin_key: str, status: str) -> list[Job] {
    _require_admin(admin_key);
    return sorted(jobs(status), key=lambda j: Job : j.created_at, reverse=True)[:200];
}

def:pub admin_run_jobs(admin_key: str, max_jobs: int) -> list[JobResult] {
    _require_admin(admin_key);
    return run_jobs(max(1, min(max_jobs, 20)));
}
