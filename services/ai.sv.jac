"""LLM-backed functions (byllm) plus cheap heuristic fallbacks.

Model is chosen by env `ABT_LLM_MODEL` (default gpt-4o-mini); provider keys come
from the usual env vars (OPENAI_API_KEY, ANTHROPIC_API_KEY, GEMINI_API_KEY...).
When no key is configured, callers fall back to heuristics / seed content.
"""

import os;
import re;
import from byllm.lib { Model }

glob LLM_MODEL_NAME: str = os.environ.get("ABT_LLM_MODEL", "gpt-4o-mini");
glob fast_llm: Model = Model(model_name=LLM_MODEL_NAME);

glob _KEY_VARS: list[str] = [
    "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY",
    "OPENROUTER_API_KEY", "GROQ_API_KEY", "MISTRAL_API_KEY", "AZURE_API_KEY"
];

def llm_enabled() -> bool {
    if os.environ.get("ABT_LLM", "") == "off" {
        return False;
    }
    if LLM_MODEL_NAME.startswith("ollama/") or LLM_MODEL_NAME.startswith("local:") {
        return True;
    }
    for k in _KEY_VARS {
        if os.environ.get(k, "") {
            return True;
        }
    }
    return False;
}

# ------------------------------------------------------------ curation scoring

enum Verdict: str { ACCEPT = "accept", REVIEW = "review", REJECT = "reject" }

obj QualityScore {
    has accuracy: float,
        density: float,
        clarity: float,
        clickbait: float,
        bias: float,
        educational: float,
        topic: str,
        summary: str,
        verdict: Verdict,
        reason: str;
}

sem QualityScore.accuracy = "0..1 likelihood the content is factually sound, judged from title/description/channel reputation.";
sem QualityScore.density = "0..1 how much genuinely useful knowledge or skill per minute it likely delivers.";
sem QualityScore.clarity = "0..1 how clearly it is likely explained.";
sem QualityScore.clickbait = "0..1, higher = more clickbait, rage-bait, hype or engagement farming.";
sem QualityScore.bias = "0..1, 0 = neutral balanced framing, 1 = one-sided advocacy or partisan spin.";
sem QualityScore.educational = "0..1 how educational it is versus pure entertainment, reaction, ads or promotion.";
sem QualityScore.topic = "Exactly one slug from the allowed topic list.";
sem QualityScore.summary = "One neutral sentence (max 25 words) saying what the viewer will learn.";
sem QualityScore.verdict = "accept only clearly educational, non-clickbait content; review if unsure or current-events; reject otherwise.";
sem QualityScore.reason = "Short justification (max 20 words).";

def llm_score_video(
    title: str, channel: str, description: str, default_topic: str, allowed_topics: list[str]
) -> QualityScore by fast_llm(temperature=0.0, max_tokens=350);

sem llm_score_video = "Rate a short-form video for an educational, anti-brainrot feed. Be strict: we want dense, accurate, neutral learning content only.";
sem llm_score_video.description = "Video description (may contain sponsor text; ignore ads).";
sem llm_score_video.default_topic = "The channel's usual topic; prefer it unless the video is clearly about another allowed topic.";

glob _CLICKBAIT_PATTERNS: list[str] = [
    "you won't believe", "you wont believe", "shocking", "insane", "gone wrong",
    "crazy", "prank", "reaction", "i tried", "vs ", "destroyed", "exposed",
    "must see", "omg", "unbelievable", "try not to", "challenge", "giveaway"
];

glob _EDU_PATTERNS: list[str] = [
    "why", "how", "what", "explained", "history", "science", "engineer", "physics",
    "math", "language", "word", "origin", "works", "made", "build", "fix", "repair",
    "discover", "learn", "theory", "fact", "invent", "design", "ancient", "space"
];

"""Cheap keyword heuristic used when no LLM is configured."""
def heuristic_score(title: str, description: str, trust: float, is_current: bool) -> dict[str, float] {
    lower = title.lower();
    clickbait = 0.0;
    for p in _CLICKBAIT_PATTERNS {
        if p in lower {
            clickbait += 0.35;
        }
    }
    letters = [c for c in title if c.isalpha()];
    if len(letters) > 8 {
        caps = len([c for c in letters if c.isupper()]) / len(letters);
        if caps > 0.6 {
            clickbait += 0.4;
        }
    }
    if title.count("!") >= 2 {
        clickbait += 0.25;
    }
    emoji_count = len(re.findall("[\U0001F300-\U0001FAFF]", title));
    if emoji_count >= 2 {
        clickbait += 0.2;
    }
    edu = 0.3;
    text = lower + " " + description[:400].lower();
    for p in _EDU_PATTERNS {
        if p in text {
            edu += 0.1;
        }
    }
    edu = min(edu, 1.0);
    clickbait = min(clickbait, 1.0);
    quality = max(0.0, min(1.0, trust * 0.6 + edu * 0.25 + (1.0 - clickbait) * 0.15));
    verdict = 1.0;
    if clickbait >= 0.5 or quality < 0.5 {
        verdict = 0.0;
    } elif is_current or quality < 0.62 or edu < 0.4 {
        verdict = 0.5;
    }
    return {"quality": quality, "clickbait": clickbait, "educational": edu, "verdict": verdict};
}

# ---------------------------------------------------------- script generation

obj SourceDoc {
    has title: str,
        url: str,
        text: str;
}

obj SceneSpec {
    has template: str,
        start_word: int,
        heading: str = "",
        body: str = "",
        items: list[str] = [],
        labels: list[str] = [],
        values: list[float] = [],
        image_query: str = "";
}

sem SceneSpec.template = "One of: title_card, bullets, big_number, timeline, process_flow, comparison, definition, quote, bar_chart, image.";
sem SceneSpec.start_word = "0-based index of the narration word where this scene starts. First scene is 0; strictly increasing; new scene every ~10-20 words.";
sem SceneSpec.heading = "Short on-screen heading (<= 40 chars). title_card: the title. big_number: the number/value. definition: the term. quote: the speaker. comparison: 'Left vs Right'.";
sem SceneSpec.body = "Short on-screen text (<= 90 chars). title_card: kicker. big_number: what it measures. definition: the meaning. quote: the quote. image: caption.";
sem SceneSpec.items = "bullets/process_flow: 2-5 items (<= 32 chars each). timeline: 'YEAR|label' entries. comparison: 'L|left point' and 'R|right point' entries.";
sem SceneSpec.labels = "bar_chart only: 2-6 bar labels.";
sem SceneSpec.values = "bar_chart only: numeric values matching labels.";
sem SceneSpec.image_query = "image only: 2-5 word Wikimedia Commons search query for a real photo/diagram of the subject (e.g. 'Pantheon Rome dome interior').";

obj Script {
    has title: str,
        summary: str,
        narration: str,
        scenes: list[SceneSpec],
        citations: list[str],
        quiz_question: str,
        quiz_choices: list[str],
        quiz_answer: int,
        quiz_explanation: str,
        tags: list[str] = [];
}

sem Script.title = "Specific, curiosity-driven but honest title (<= 60 chars). No clickbait.";
sem Script.summary = "One sentence: what the viewer learns.";
sem Script.narration = "Spoken script, 120-170 words, plain language, one core idea, a hook in the first sentence, no filler, no calls to like/subscribe. Only facts supported by the sources.";
sem Script.scenes = "5-10 scenes covering the whole narration. Mix templates; include 1-3 image scenes.";
sem Script.citations = "URLs of the provided sources actually used. Never invent URLs.";
sem Script.quiz_question = "One recall question answerable from the narration.";
sem Script.quiz_choices = "3-4 short answer choices.";
sem Script.quiz_answer = "0-based index of the correct choice.";
sem Script.tags = "2-4 lowercase tags.";

def llm_write_script(subject: str, topic: str, sources: list[SourceDoc]) -> Script by fast_llm(
    temperature=0.4, max_tokens=1800
);

sem llm_write_script = "Write a ~60 second educational short video script with scene plan, grounded ONLY in the given sources. Neutral tone; attribute contested claims.";
sem llm_write_script.subject = "What the video should explain.";
sem llm_write_script.topic = "Feed topic slug (context for tone).";

obj ClaimCheck {
    has claim: str,
        supported: bool,
        note: str = "";
}

sem ClaimCheck.supported = "True only if the sources clearly support the claim.";

def llm_check_claims(narration: str, sources: list[SourceDoc]) -> list[ClaimCheck] by fast_llm(
    temperature=0.0, max_tokens=900
);

sem llm_check_claims = "Split the narration into its factual claims (max 8) and check each strictly against the sources.";

# Lives beside Script: byllm 0.6.19 loses schema info for imported return types on tool-less calls.
def revise_script(draft_json: str, problems: list[str], sources: list[SourceDoc]) -> Script by fast_llm(
    temperature=0.2, max_tokens=2200
);

sem revise_script = """Fix the draft script (JSON): remove or correct every problem claim using only the sources.
Keep 120-170 words, keep the scene plan in sync with the narration (update start_word indices),
keep the quiz answerable from the revised narration, and keep citations to source URLs.""";
sem revise_script.draft_json = "The current script as JSON.";
sem revise_script.problems = "Claims a fact-checker found unsupported by the sources.";
