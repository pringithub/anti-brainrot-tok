"""Catalog planner (walker + LLM editor) and the job worker.

PlanCatalog walks root.shared -> Topic nodes. At each topic it measures supply
(live / generated videos) and demand (user signals), asks the LLM editor what
the topic needs, and enqueues Job nodes. run_jobs() drains the queue.
"""

import re;
import from services.catalog {
    Topic, Video, Signal, Job, JobQueue, PipelineRun, job_queue, jobs, signal_log, videos_of,
    admin_error, ensure_catalog, now_iso
}
import from services.ai { fast_llm, llm_enabled, LLM_MODEL_NAME }
import from services.curation { run_curation }
import from services.generation { generate_from_subject }

obj TopicPlan {
    has curate: bool,
        subjects: list[str],
        rationale: str;
}

sem TopicPlan.curate = "True if the topic needs more curated videos from its channels.";
sem TopicPlan.subjects = "0..max_new concrete, evergreen, factual subjects for new ~60s explainers, not already covered.";
sem TopicPlan.rationale = "One short sentence explaining the plan.";

def llm_plan_topic(
    topic_name: str, description: str, live_count: int, generated_count: int,
    demand_share: float, recent_titles: list[str], max_new: int
) -> TopicPlan by fast_llm(temperature=0.6, max_tokens=500);

sem llm_plan_topic = """You are the editor of an educational short-video feed. Given a topic's
supply (live videos) and demand (share of recent learner engagement), decide whether to curate
more and propose up to max_new specific subjects for new explainers (e.g. 'How suspension
bridges carry load'). Never propose opinion, partisan, medical-advice or breaking-news subjects,
and never repeat anything in recent_titles.""";
sem llm_plan_topic.demand_share = "0..1 share of recent engagement landing in this topic.";

def _norm(s: str) -> str {
    return re.sub("[^a-z0-9 ]", "", s.lower()).strip();
}

"""Heuristic plan when no LLM is configured (can only request curation)."""
def heuristic_plan(live_count: int, target_live: int, demand_share: float) -> TopicPlan {
    needs = live_count < target_live or (demand_share > 0.25 and live_count < target_live * 2);
    return TopicPlan(curate=needs, subjects=[], rationale="heuristic: supply vs target");
}

walker:pub PlanCatalog {
    has admin_key: str = "",
        target_live: int = 20,
        max_new_per_topic: int = 2,
        reports: list[list[str]] = [];

    has demand: dict[str, float] = {},
        pending: set[str] = set(),
        queued: list[str] = [],
        use_llm: bool = False,
        error: str = "";

    can start with Root entry {
        self.error = admin_error(self.admin_key);
        if self.error {
            report [self.error];
            disengage;
        }
        ensure_catalog();
        self.use_llm = llm_enabled();
        self.queued = [];
        self.pending = {j.kind + ":" + j.topic + ":" + _norm(j.subject) for j in jobs("queued")};
        # Demand = share of recent completes/likes/saves per topic.
        topic_of = {jid(v): v.topic for t in [here -->[?:Topic]] for v in videos_of(t)};
        counts: dict[str, float] = {};
        total = 0.0;
        log = signal_log();
        if log is not None {
            for s in [log -->[?:Signal]] {
                w = {"complete": 1.0, "like": 1.5, "save": 2.0}.get(s.kind, 0.0);
                t = topic_of.get(s.video_id, "");
                if w > 0.0 and t {
                    counts[t] = counts.get(t, 0.0) + w;
                    total += w;
                }
            }
        }
        self.demand = {k: counts[k] / total for k in counts} if total > 0.0 else {};
        visit [here -->[?:Topic]];
    }

    can plan_topic with Topic entry {
        vids = videos_of(here);
        live = [v for v in vids if v.status == "live"];
        generated = [v for v in live if v.kind == "generated"];
        titles = [v.title for v in sorted(vids, key=lambda v: Video : v.added_at, reverse=True)[:30]];
        share = self.demand.get(here.slug, 0.0);
        plan = heuristic_plan(len(live), self.target_live, share);
        if self.use_llm {
            try {
                plan = llm_plan_topic(
                    here.name, here.description, len(live), len(generated), share, titles,
                    0 if here.is_current_events else self.max_new_per_topic
                );
            } except Exception as err {
                print("[plan] LLM failed for", here.slug, str(err)[:120]);
            }
        }
        existing = {_norm(t) for t in titles};
        if plan.curate {
            self._enqueue("curate", here.slug, "", plan.rationale);
        }
        if not here.is_current_events {
            for subj in plan.subjects[:self.max_new_per_topic] {
                if subj.strip() and _norm(subj) not in existing and len(subj) <= 200 {
                    self._enqueue("generate", here.slug, subj.strip(), plan.rationale);
                }
            }
        }
    }

    def _enqueue(kind: str, topic: str, subject: str, reason: str) {
        key = kind + ":" + topic + ":" + _norm(subject);
        q = job_queue();
        if key in self.pending or q is None {
            return;
        }
        self.pending.add(key);
        q ++> Job(kind=kind, topic=topic, subject=subject, reason=reason[:200], created_at=now_iso());
        self.queued.append(key);
    }

    can finish with Root exit {
        if not self.error {
            report self.queued;
        }
    }
}

obj JobResult {
    has kind: str,
        topic: str,
        subject: str,
        status: str,
        result: str;
}

"""Process up to max_jobs queued jobs (FIFO). Must run anonymously."""
def run_jobs(max_jobs: int) -> list[JobResult] {
    queued = sorted(jobs("queued"), key=lambda j: Job : j.created_at);
    out: list[JobResult] = [];
    for j in queued[:max_jobs] {
        j.status = "running";
        j.attempts += 1;
        try {
            if j.kind == "curate" {
                stats = run_curation(4, "", j.topic);
                j.result = "new=" + str(stats.get("new", 0)) + " live=" + str(stats.get("live", 0));
                j.status = "done";
            } elif j.kind == "generate" {
                r = generate_from_subject(j.subject, j.topic);
                j.result = (r.status + " " + r.title) if r.ok else ("failed: " + r.message);
                j.status = "done" if r.ok else "failed";
            } else {
                j.status = "failed";
                j.result = "unknown job kind";
            }
        } except Exception as err {
            j.status = "failed" if j.attempts >= 3 else "queued";
            j.result = str(err)[:200];
        }
        j.finished_at = now_iso();
        out.append(JobResult(kind=j.kind, topic=j.topic, subject=j.subject, status=j.status, result=j.result));
    }
    return out;
}
