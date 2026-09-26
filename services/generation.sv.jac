"""Generation pipeline: sources -> script -> fact-check -> images -> TTS -> scene manifest.

Videos are stored as a compact JSON scene manifest (+ optional narration mp3)
and rendered in the browser; no server-side video encoding.
"""

import os;
import re;
import math;
import json;
import base64;
import hashlib;
import requests;
import from services.catalog { Video, PipelineRun, find_video, add_video, now_iso, safe_json, r3, STUDIO_NAME }
import from services.ai {
    Script, SceneSpec, SourceDoc, ClaimCheck, llm_enabled, llm_write_script, llm_check_claims,
    LLM_MODEL_NAME
}
import from services.curation { HTTP_HEADERS }
import from services.research { run_research_agent }

glob ALLOWED_TEMPLATES: list[str] = [
    "title_card", "bullets", "big_number", "timeline", "process_flow", "comparison",
    "definition", "quote", "bar_chart", "image"
];

glob ALLOWED_LICENSE_PREFIXES: list[str] = ["cc0", "cc by", "cc-by", "public domain", "pd"];
glob BROWSER_TTS_WPS: float = 2.6;

def media_dir() -> str {
    d = os.environ.get("ABT_MEDIA_DIR", os.path.join(os.getcwd(), "assets", "media"));
    os.makedirs(d, exist_ok=True);
    return d;
}

def _clip(s: str, n: int) -> str {
    s = re.sub("\\s+", " ", str(s or "")).strip();
    return s if len(s) <= n else s[:n - 1].rstrip() + "…";
}

def _strip_html(s: str) -> str {
    return _clip(re.sub("<[^>]+>", "", str(s or "")), 120);
}

# ------------------------------------------------------------------ sources

"""Search Wikipedia and return plaintext extracts of the top articles."""
def fetch_wikipedia_sources(query: str, max_docs: int, max_chars: int) -> list[SourceDoc] {
    api = "https://en.wikipedia.org/w/api.php";
    resp = requests.get(api, params={
        "action": "query", "list": "search", "srsearch": query, "srlimit": max_docs,
        "format": "json"
    }, headers=HTTP_HEADERS, timeout=15);
    resp.raise_for_status();
    hits = resp.json().get("query", {}).get("search", []);
    docs: list[SourceDoc] = [];
    for h in hits[:max_docs] {
        title = str(h.get("title", ""));
        if not title {
            continue;
        }
        r2 = requests.get(api, params={
            "action": "query", "prop": "extracts", "explaintext": 1, "redirects": 1,
            "titles": title, "format": "json"
        }, headers=HTTP_HEADERS, timeout=15);
        if r2.status_code != 200 {
            continue;
        }
        pages = r2.json().get("query", {}).get("pages", {});
        for p in pages.values() {
            text = str(p.get("extract", ""));
            if text {
                docs.append(SourceDoc(
                    title=title,
                    url="https://en.wikipedia.org/wiki/" + title.replace(" ", "_"),
                    text=text[:max_chars]
                ));
            }
        }
    }
    return docs;
}

# ------------------------------------------------------------------- images

"""Find a freely licensed Wikimedia Commons image. Returns {} when none fits."""
def find_commons_image(query: str) -> dict[str, str] {
    if not query.strip() {
        return {};
    }
    resp = requests.get("https://commons.wikimedia.org/w/api.php", params={
        "action": "query", "format": "json", "generator": "search",
        "gsrsearch": query + " filetype:bitmap", "gsrnamespace": 6, "gsrlimit": 12,
        "prop": "imageinfo", "iiprop": "url|size|extmetadata|mime", "iiurlwidth": 1080
    }, headers=HTTP_HEADERS, timeout=15);
    if resp.status_code != 200 {
        return {};
    }
    pages = resp.json().get("query", {}).get("pages", {});
    best: dict[str, str] = {};
    best_score = -1.0;
    for p in pages.values() {
        infos = p.get("imageinfo", []);
        if not infos {
            continue;
        }
        info = infos[0];
        meta = info.get("extmetadata", {});
        lic = str(meta.get("LicenseShortName", {}).get("value", "")).strip();
        lic_l = lic.lower();
        if not `any([lic_l.startswith(x) for x in ALLOWED_LICENSE_PREFIXES]) {
            continue;
        }
        if "nc" in lic_l.replace("cc", "").split("-") or "-nd" in lic_l or " nd" in lic_l {
            continue;
        }
        src = str(info.get("thumburl", "") or info.get("url", ""));
        if not (src.startswith("https://upload.wikimedia.org/") or src.startswith("https://thumb.wikimedia.org/")) {
            continue;
        }
        w = float(info.get("width", 0) or 0);
        h = float(info.get("height", 0) or 0);
        if w < 500 or h < 500 {
            continue;
        }
        # Prefer larger and more portrait-ish images for a 9:16 frame.
        score = min(w * h, 4000000.0) / 4000000.0 + min(h / w, 1.5) * 0.5;
        if score > best_score {
            best_score = score;
            artist = _strip_html(str(meta.get("Artist", {}).get("value", ""))) or "Unknown author";
            best = {
                "src": src,
                "page": str(info.get("descriptionurl", "")),
                "credit": artist + " · " + lic + " · Wikimedia Commons"
            };
        }
    }
    return best;
}

# ---------------------------------------------------------------------- TTS

obj Word {
    has w: str,
        s: float,
        e: float;
}

obj TtsResult {
    has audio: str = "",
        words: list[Word] = [];
}

def _num(x: object) -> float {
    try {
        f = float(str(x));
    } except Exception {
        return 0.0;
    }
    if math.isnan(f) or math.isinf(f) {
        return 0.0;
    }
    return f;
}

def _alignment_to_words(chars: list[str], starts: list[float], ends: list[float]) -> list[Word] {
    words: list[Word] = [];
    cur = "";
    cur_start = 0.0;
    cur_end = 0.0;
    n = min(len(chars), len(starts), len(ends));
    for i in range(n) {
        ch = chars[i];
        if ch.isspace() {
            if cur {
                words.append(Word(w=cur, s=r3(cur_start), e=r3(cur_end)));
                cur = "";
            }
            continue;
        }
        if not cur {
            cur_start = starts[i];
        }
        cur += ch;
        cur_end = ends[i];
    }
    if cur {
        words.append(Word(w=cur, s=r3(cur_start), e=r3(cur_end)));
    }
    return words;
}

def _words_to_json(words: list[Word]) -> list[list[object]] {
    return [[w.w, w.s, w.e] for w in words];
}

def _words_from_json(raw: list[list[object]]) -> list[Word] {
    return [Word(w=str(r[0]), s=_num(r[1]), e=_num(r[2])) for r in raw if len(r) >= 3];
}

def elevenlabs_enabled() -> bool {
    return bool(os.environ.get("ELEVENLABS_API_KEY", "")) and os.environ.get("ABT_TTS", "") != "browser";
}

"""Synthesize narration with ElevenLabs, cached by content hash. Empty result on failure."""
def elevenlabs_tts(text: str) -> TtsResult {
    key = os.environ.get("ELEVENLABS_API_KEY", "");
    voice = os.environ.get("ELEVENLABS_VOICE_ID", "JBFqnCBsd6RMkjVDRZzb");
    model = os.environ.get("ELEVENLABS_MODEL_ID", "eleven_flash_v2_5");
    if not key {
        return TtsResult();
    }
    if not re.fullmatch("[A-Za-z0-9]{8,40}", voice) {
        print("[tts] invalid ELEVENLABS_VOICE_ID");
        return TtsResult();
    }
    digest = hashlib.sha256((model + "|" + voice + "|" + text).encode("utf-8")).hexdigest()[:24];
    mp3_path = os.path.join(media_dir(), digest + ".mp3");
    words_path = os.path.join(media_dir(), digest + ".words.json");
    url = "/static/media/" + digest + ".mp3";
    if os.path.exists(mp3_path) and os.path.exists(words_path) {
        with open(words_path, "r", encoding="utf-8") as fh {
            cached = json.load(fh) as list[list[object]];
        }
        return TtsResult(audio=url, words=_words_from_json(cached));
    }
    resp = requests.post(
        "https://api.elevenlabs.io/v1/text-to-speech/" + voice + "/with-timestamps",
        params={"output_format": "mp3_44100_64"},
        headers={"xi-api-key": key, "Content-Type": "application/json"},
        json={"text": text, "model_id": model},
        timeout=120
    );
    if resp.status_code != 200 {
        print("[tts] ElevenLabs error", resp.status_code, resp.text[:200]);
        return TtsResult();
    }
    data = resp.json() as dict[str, object];
    audio = base64.b64decode(str(data.get("audio_base64", "")));
    al = (data.get("alignment") or data.get("normalized_alignment") or {}) as dict[str, list[object]];
    words = _alignment_to_words(
        [str(c) for c in al.get("characters", [])],
        [_num(x) for x in al.get("character_start_times_seconds", [])],
        [_num(x) for x in al.get("character_end_times_seconds", [])]
    );
    if not audio or not words {
        return TtsResult();
    }
    with open(mp3_path, "wb") as fh {
        fh.write(audio);
    }
    with open(words_path, "w", encoding="utf-8") as fh {
        json.dump(_words_to_json(words), fh);
    }
    return TtsResult(audio=url, words=words);
}

"""Rough word timings for browser speech synthesis (scene timing only)."""
def estimate_words(text: str) -> list[Word] {
    out: list[Word] = [];
    t = 0.0;
    for w in text.split() {
        dur = max(0.18, len(w) / 14.0) * (2.6 / BROWSER_TTS_WPS);
        if w.endswith(".") or w.endswith("?") or w.endswith("!") {
            dur += 0.25;
        } elif w.endswith(",") or w.endswith(";") or w.endswith(":") {
            dur += 0.12;
        }
        out.append(Word(w=w, s=r3(t), e=r3(t + dur)));
        t += dur;
    }
    return out;
}

# ----------------------------------------------------------------- manifest

obj SceneOut {
    has w: int,
        template: str,
        heading: str = "",
        body: str = "",
        items: list[str] = [],
        labels: list[str] = [],
        values: list[float] = [],
        query: str = "",
        image: dict[str, str] = {},
        t: float = 0.0;

    def to_dict -> dict[str, object] {
        d: dict[str, object] = {
            "t": self.t, "w": self.w, "template": self.template, "heading": self.heading,
            "body": self.body, "items": self.items, "labels": self.labels, "values": self.values
        };
        if self.image {
            d["image"] = self.image;
        }
        return d;
    }
}

"""Clamp/validate LLM scene specs into safe, renderable scene dicts."""
def sanitize_scenes(specs: list[SceneSpec], n_words: int) -> list[SceneOut] {
    scenes: list[SceneOut] = [];
    last_start = -1;
    ordered = sorted(specs, key=lambda s: SceneSpec : s.start_word);
    for s in ordered[:14] {
        tpl = s.template if s.template in ALLOWED_TEMPLATES else "bullets";
        start = max(0, min(int(s.start_word), max(0, n_words - 1)));
        if not scenes {
            start = 0;
        }
        if start <= last_start {
            continue;
        }
        last_start = start;
        labels = [_clip(x, 24) for x in s.labels[:6]];
        values = [_num(x) for x in s.values[:len(labels)]];
        scenes.append(SceneOut(
            w=start,
            template=tpl,
            heading=_clip(s.heading, 60),
            body=_clip(s.body, 140),
            items=[_clip(x, 60) for x in s.items[:6]],
            labels=labels,
            values=values,
            query=_clip(s.image_query, 80)
        ));
    }
    if not scenes {
        scenes.append(SceneOut(w=0, template="title_card"));
    }
    return scenes;
}

obj GenerationResult {
    has ok: bool,
        status: str = "",
        video_id: str = "",
        title: str = "",
        message: str = "",
        notes: list[str] = [];
}

"""Turn a validated Script into a stored generated Video (not yet attached)."""
def build_video(
    script: Script, topic: str, allowed_urls: list[str], notes: list[str], force_review: bool,
    scored_by: str
) -> Video {
    narration = _clip(script.narration, 1400);
    n_words = len(narration.split());
    scenes = sanitize_scenes(script.scenes, n_words);
    attributions: list[str] = [];
    for sc in scenes {
        if sc.template == "image" {
            img: dict[str, str] = {};
            try {
                img = find_commons_image(sc.query);
            } except Exception as err {
                notes.append("image search failed: " + str(err)[:80]);
            }
            if img {
                sc.image = img;
                attributions.append(img["credit"] + " — " + img["page"]);
            } else {
                sc.template = "bullets" if sc.items else "title_card";
                if not sc.heading {
                    sc.heading = sc.body or script.title;
                }
                notes.append("no licensed image for '" + sc.query + "'");
            }
        }
    }
    tts = TtsResult();
    if elevenlabs_enabled() {
        try {
            tts = elevenlabs_tts(narration);
        } except Exception as err {
            notes.append("tts failed: " + str(err)[:80]);
        }
    }
    has_audio = bool(tts.audio) and len(tts.words) > 0;
    words = tts.words if has_audio else estimate_words(narration);
    for sc in scenes {
        idx = min(sc.w, len(words) - 1) if words else 0;
        sc.t = words[idx].s if words else 0.0;
    }
    duration = words[-1].e + 0.6 if words else 30.0;
    manifest: dict[str, object] = {
        "v": 1, "tts": "elevenlabs" if has_audio else "browser", "audio": tts.audio if has_audio else "",
        "duration": r3(duration), "narration": narration, "words": _words_to_json(words),
        "scenes": [sc.to_dict() for sc in scenes]
    };
    citations = [u for u in script.citations if u in allowed_urls][:6];
    if not citations {
        citations = allowed_urls[:3];
    }
    digest = hashlib.sha1((script.title + "|" + narration).encode("utf-8")).hexdigest()[:16];
    quiz_ok = (
        len(script.quiz_choices) >= 2 and 0 <= script.quiz_answer < len(script.quiz_choices)
        and bool(script.quiz_question.strip())
    );
    status = "review" if force_review or topic == "current-events" else "live";
    return Video(
        kind="generated",
        title=_clip(script.title, 80),
        topic=topic,
        status=status,
        summary=_clip(script.summary, 200),
        tags=[_clip(t, 24).lower() for t in script.tags[:4]],
        duration_s=r3(duration),
        quality=0.75 if status == "live" else 0.6,
        scored_by=scored_by,
        score_reason="generated from cited sources; claims checked" if not force_review else "needs review",
        published_at=now_iso(),
        creator_name=STUDIO_NAME,
        creator_id="abt",
        provider="abt",
        external_id=digest,
        manifest_json=safe_json(manifest),
        citations=citations,
        attributions=attributions,
        quiz_question=_clip(script.quiz_question, 160) if quiz_ok else "",
        quiz_choices=[_clip(c, 80) for c in script.quiz_choices[:4]] if quiz_ok else [],
        quiz_answer=script.quiz_answer if quiz_ok else -1,
        quiz_explanation=_clip(script.quiz_explanation, 200) if quiz_ok else "",
        review_notes=notes
    );
}

def _publish(v: Video, run: PipelineRun) -> GenerationResult {
    existing = find_video("abt", v.external_id);
    if existing is not None {
        return GenerationResult(ok=True, status=existing.status, video_id=jid(existing),
                                title=existing.title, message="already exists");
    }
    if add_video(v) is None {
        return GenerationResult(ok=False, message="unknown topic " + v.topic);
    }
    run.finished_at = now_iso();
    run.stats = {"created": 1};
    root.shared ++> run;
    return GenerationResult(ok=True, status=v.status, video_id=jid(v), title=v.title,
                            notes=v.review_notes);
}

"""Full LLM pipeline for a subject. Must run anonymously."""
def generate_from_subject(subject: str, topic: str) -> GenerationResult {
    if not llm_enabled() {
        return GenerationResult(ok=False, message="No LLM configured (set OPENAI_API_KEY or similar).");
    }
    run = PipelineRun(kind="generation", started_at=now_iso(), notes=[subject]);
    outcome = run_research_agent(subject, topic);
    if outcome.error or outcome.script is None {
        return GenerationResult(ok=False, message=outcome.error or "agent produced no script",
                                notes=outcome.trace + outcome.notes);
    }
    script = outcome.script;
    notes = ["agent: " + t for t in outcome.trace] + outcome.notes;
    force_review = outcome.needs_review;
    n_words = len(script.narration.split());
    if n_words < 80 or n_words > 220 {
        notes.append("narration length " + str(n_words) + " words");
        force_review = True;
    }
    run.notes = run.notes + outcome.trace;
    v = build_video(script, topic, [d.url for d in outcome.sources], notes, force_review,
                    "agent:" + LLM_MODEL_NAME);
    return _publish(v, run);
}

"""Publish a hand-authored script (no LLM needed)."""
def publish_script(script: Script, topic: str, citations: list[str]) -> GenerationResult {
    run = PipelineRun(kind="seed", started_at=now_iso(), notes=[script.title]);
    v = build_video(script, topic, citations, [], False, "editorial");
    return _publish(v, run);
}
