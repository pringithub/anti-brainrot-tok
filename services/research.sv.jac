"""Research agent for generated videos (byllm ReAct with tools).

The agent searches and reads Wikipedia itself, then writes the script. Every
article it reads is recorded, so citations and the independent fact-check are
restricted to what the agent actually read. Unsupported claims trigger a
self-revision loop before anything is published.
"""

import json;
import threading;
import from dataclasses { asdict }
import from threading { Lock }
import requests;
import from services.ai {
    Script, SourceDoc, ClaimCheck, fast_llm, llm_check_claims, llm_write_script, llm_enabled,
    revise_script
}
import from services.curation { HTTP_HEADERS }

glob WIKI_API: str = "https://en.wikipedia.org/w/api.php";
glob MAX_ARTICLE_CHARS: int = 3500;
glob MAX_ARTICLES: int = 4;
glob MAX_REVISIONS: int = 2;

# One research session at a time: the tool functions record into these globs.
glob _LOCK: Lock = threading.Lock();
glob _SOURCES: dict[str, SourceDoc] = {};
glob _TRACE: list[str] = [];

# ------------------------------------------------------------------ tools

def search_wikipedia(query: str) -> list[str] {
    _TRACE.append("search: " + query[:80]);
    resp = requests.get(WIKI_API, params={
        "action": "query", "list": "search", "srsearch": query[:200], "srlimit": 5, "format": "json"
    }, headers=HTTP_HEADERS, timeout=15);
    if resp.status_code != 200 {
        return [];
    }
    hits = resp.json().get("query", {}).get("search", []);
    return [str(h.get("title", "")) for h in hits if h.get("title")];
}

sem search_wikipedia = "Search English Wikipedia. Returns up to 5 article titles.";
sem search_wikipedia.query = "Search terms, e.g. 'suspension bridge load'.";

def read_article(title: str) -> str {
    if len(_SOURCES) >= MAX_ARTICLES {
        return "Article limit reached; write the script with what you have read.";
    }
    _TRACE.append("read: " + title[:80]);
    resp = requests.get(WIKI_API, params={
        "action": "query", "prop": "extracts", "explaintext": 1, "redirects": 1,
        "titles": title[:200], "format": "json"
    }, headers=HTTP_HEADERS, timeout=15);
    if resp.status_code != 200 {
        return "Could not fetch article.";
    }
    for p in resp.json().get("query", {}).get("pages", {}).values() {
        text = str(p.get("extract", ""))[:MAX_ARTICLE_CHARS];
        real_title = str(p.get("title", title));
        if text {
            url = "https://en.wikipedia.org/wiki/" + real_title.replace(" ", "_");
            _SOURCES[url] = SourceDoc(title=real_title, url=url, text=text);
            return "URL: " + url + "\n\n" + text;
        }
    }
    return "Article not found.";
}

sem read_article = "Read the plaintext of a Wikipedia article (first ~3500 characters). Returns its URL and text. Only facts from articles you read may be used.";
sem read_article.title = "Exact article title from search_wikipedia.";

# ---------------------------------------------------------------- agents

def research_and_write(subject: str, topic: str) -> Script by fast_llm(
    tools=[search_wikipedia, read_article], max_react_iterations=10, temperature=0.4,
    max_tokens=2200
);

sem research_and_write = """You are a careful researcher and scriptwriter for an educational
short-video feed. First search Wikipedia and read the 2-3 most relevant articles about the
subject. Then write a ~60 second script grounded ONLY in what you read: no outside facts,
neutral tone, contested points attributed. Cite only URLs of articles you read.""";
sem research_and_write.subject = "What the video should explain.";
sem research_and_write.topic = "Feed topic slug (context for tone).";


# ---------------------------------------------------------------- driver

obj ResearchOutcome {
    has script: Script | None = None,
        sources: list[SourceDoc] = [],
        trace: list[str] = [],
        notes: list[str] = [],
        needs_review: bool = False,
        error: str = "";
}

def _unsupported(script: Script, sources: list[SourceDoc]) -> list[str] {
    checks = llm_check_claims(script.narration, sources);
    return [c.claim for c in checks if not c.supported];
}

"""Run the research agent, then fact-check / self-revise up to MAX_REVISIONS times."""
def run_research_agent(subject: str, topic: str) -> ResearchOutcome {
    if not llm_enabled() {
        return ResearchOutcome(error="No LLM configured.");
    }
    with _LOCK {
        _SOURCES.clear();
        _TRACE.clear();
        out = ResearchOutcome();
        script: Script | None = None;
        try {
            script = research_and_write(subject, topic);
        } except Exception as err {
            out.notes.append("agent failed, using fixed pipeline: " + str(err)[:120]);
        }
        sources = list(_SOURCES.values());
        if script is None or not sources {
            # The agent didn't read anything: do fixed retrieval and a single-shot write.
            try {
                for title in search_wikipedia(subject)[:2] {
                    read_article(title);
                }
            } except Exception as err {
                out.notes.append("retrieval failed: " + str(err)[:120]);
            }
            sources = list(_SOURCES.values());
            if not sources {
                out.error = "no sources available";
                out.trace = list(_TRACE);
                return out;
            }
            script = llm_write_script(subject, topic, sources);
            out.notes.append("used fixed retrieval");
        }
        out.trace = list(_TRACE);
    }
    bad: list[str] = [];
    try {
        bad = _unsupported(script, sources);
        rounds = 0;
        while bad and rounds < MAX_REVISIONS {
            rounds += 1;
            out.notes.append("revision " + str(rounds) + ": " + str(len(bad)) + " unsupported claim(s)");
            script = revise_script(json.dumps(asdict(script)), bad, sources);
            bad = _unsupported(script, sources);
        }
    } except Exception as err {
        out.notes.append("fact-check failed: " + str(err)[:120]);
        out.needs_review = True;
    }
    for claim in bad {
        out.notes.append("unsupported: " + claim[:120]);
    }
    out.needs_review = out.needs_review or len(bad) > 0;
    out.script = script;
    out.sources = sources;
    return out;
}
