"""Offline tests for the agentic pieces and pure helpers (MockLLM, no network).

Run: jac test tests/agents_tests.jac
"""

import os;
import services.research as research_mod;
import services.ai as ai_mod;
import services.planner as planner_mod;
import from byllm.lib { MockLLM, MockToolCall }
import from services.ai { Script, SceneSpec, ClaimCheck, heuristic_score }
import from services.research { run_research_agent, search_wikipedia, read_article }
import from services.planner { PlanCatalog, TopicPlan, heuristic_plan }
import from services.generation { sanitize_scenes, _alignment_to_words }
import from services.seeds { seed_videos }
import from services.catalog { jobs }

glob TEST_ADMIN_KEY: str = "test-admin-key-0123456789";

# Stand-in for the `requests` module used by the research tools.
obj FakeResp {
    has status_code: int = 200,
        payload: dict = {};

    def json -> dict {
        return self.payload;
    }
}

# Monkeypatching goes through setattr: the checker types module globals strictly.
obj FakeRequests {
    has calls: list[str] = [];

    def get(url: str, params: dict = {}, headers: dict = {}, timeout: int = 0) -> FakeResp {
        self.calls.append(str(params.get("list", params.get("prop", ""))));
        if params.get("list") == "search" {
            return FakeResp(payload={"query": {"search": [{"title": "Roman concrete"}]}});
        }
        return FakeResp(payload={"query": {"pages": {"1": {
            "title": "Roman concrete",
            "extract": "Roman concrete used lime and volcanic ash. Lime clasts helped cracks self-heal."
        }}}});
    }
}

def _script(narration: str) -> Script {
    return Script(
        title="Why Roman concrete lasts",
        summary="Volcanic ash and lime clasts.",
        narration=narration,
        scenes=[SceneSpec(template="title_card", start_word=0, heading="Roman concrete")],
        citations=["https://en.wikipedia.org/wiki/Roman_concrete"],
        quiz_question="What did Romans mix with lime?",
        quiz_choices=["Volcanic ash", "Sand only"],
        quiz_answer=0,
        quiz_explanation="Volcanic ash."
    );
}

test "research agent calls tools, records sources and self-revises unsupported claims" {
    os.environ["OPENAI_API_KEY"] = os.environ.get("OPENAI_API_KEY", "") or "test-key";
    fake = FakeRequests();
    setattr(research_mod, "requests", fake);
    mock = MockLLM(model_name="mockllm", config={"outputs": [
        MockToolCall(tool=search_wikipedia, args={"query": "roman concrete"}),
        MockToolCall(tool=read_article, args={"title": "Roman concrete"}),
        # byllm's ReAct loop consumes one extra model turn before the final structured answer.
        _script("draft"),
        _script("Roman concrete used volcanic ash. It was invented on Mars."),
        [ClaimCheck(claim="It was invented on Mars.", supported=False)],
        _script("Roman concrete used lime and volcanic ash, and lime clasts helped it self-heal."),
        [ClaimCheck(claim="Roman concrete used lime and volcanic ash.", supported=True)]
    ]});
    setattr(research_mod, "fast_llm", mock);
    setattr(ai_mod, "fast_llm", mock);

    out = run_research_agent("Why Roman concrete lasts", "engineering");

    assert out.error == "", out.error;
    assert out.trace == ["search: roman concrete", "read: Roman concrete"], str(out.trace) + str(out.notes);
    assert [s.url for s in out.sources] == ["https://en.wikipedia.org/wiki/Roman_concrete"];
    assert out.script is not None;
    assert "Mars" not in out.script.narration, out.script.narration + " | " + str(out.notes);
    assert not out.needs_review;
    assert "revision 1: 1 unsupported claim(s)" in out.notes, str(out.notes);
}

test "research agent flags review when revisions can't fix a claim" {
    setattr(research_mod, "requests", FakeRequests());
    bad = [ClaimCheck(claim="Invented on Mars.", supported=False)];
    mock = MockLLM(model_name="mockllm", config={"outputs": [
        MockToolCall(tool=read_article, args={"title": "Roman concrete"}),
        _script("draft"),
        _script("Invented on Mars."),
        bad, _script("Invented on Mars."), bad, _script("Invented on Mars."), bad
    ]});
    setattr(research_mod, "fast_llm", mock);
    setattr(ai_mod, "fast_llm", mock);

    out = run_research_agent("Roman concrete", "engineering");

    assert out.needs_review;
    assert "unsupported: Invented on Mars." in out.notes, str(out.notes);
}

test "PlanCatalog walker queues jobs from the LLM editor without duplicates" {
    os.environ["ABT_ADMIN_KEY"] = TEST_ADMIN_KEY;
    plan = TopicPlan(curate=True, subjects=["How tides work"], rationale="thin topic");
    setattr(planner_mod, "fast_llm", MockLLM(model_name="mockllm", config={"outputs": [plan] * 16}));
    before = len(jobs("queued"));

    root spawn PlanCatalog(admin_key=TEST_ADMIN_KEY, target_live=5, max_new_per_topic=1);
    after_first = jobs("queued");
    root spawn PlanCatalog(admin_key=TEST_ADMIN_KEY, target_live=5, max_new_per_topic=1);
    after_second = jobs("queued");

    # Test data persists across runs, so assert on the shape of the queue, not deltas.
    gen_topics = {j.topic for j in after_first if j.kind == "generate" and j.subject == "How tides work"};
    assert len(gen_topics) == 7, str(gen_topics);
    assert "current-events" not in gen_topics;
    assert len({j.topic for j in after_first if j.kind == "curate"}) == 8;
    assert len(after_second) == len(after_first);
    assert before <= len(after_first);
}

test "PlanCatalog rejects a wrong admin key" {
    os.environ["ABT_ADMIN_KEY"] = TEST_ADMIN_KEY;
    before = len(jobs(""));
    root spawn PlanCatalog(admin_key="nope");
    assert len(jobs("")) == before;
}

test "heuristic plan curates thin topics only" {
    assert heuristic_plan(3, 20, 0.0).curate;
    assert not heuristic_plan(40, 20, 0.1).curate;
    assert heuristic_plan(25, 20, 0.5).curate;
}

test "heuristic scorer separates clickbait from educational titles" {
    edu = heuristic_score("Why suspension bridges don't fall down", "", 0.75, False);
    bait = heuristic_score("YOU WON'T BELIEVE THIS INSANE PRANK!!!", "", 0.75, False);
    assert edu["verdict"] == 1.0;
    assert bait["verdict"] == 0.0;
}

test "scene sanitiser clamps templates, ordering and text" {
    specs = [
        SceneSpec(template="bullets", start_word=40, items=["x" * 200]),
        SceneSpec(template="<script>", start_word=5),
        SceneSpec(template="title_card", start_word=5, heading="dup start")
    ];
    scenes = sanitize_scenes(specs, 30);
    assert scenes[0].w == 0;
    assert scenes[0].template == "bullets";
    assert [s.w for s in scenes] == sorted([s.w for s in scenes]);
    assert all([len(i) <= 60 for s in scenes for i in s.items]);
    assert all([s.template != "<script>" for s in scenes]);
}

test "ElevenLabs character alignment becomes word timings" {
    words = _alignment_to_words(
        ["H", "i", " ", "y", "o", "u"], [0.0, 0.1, 0.2, 0.3, 0.4, 0.5], [0.1, 0.2, 0.3, 0.4, 0.5, 0.6]
    );
    assert [w.w for w in words] == ["Hi", "you"];
    assert words[1].s == 0.3 and words[1].e == 0.6;
}

test "seed scripts produce increasing scene start words" {
    for sv in seed_videos() {
        s = sv.to_script();
        starts = [sc.start_word for sc in s.scenes];
        assert starts[0] == 0;
        assert starts == sorted(starts) and len(set(starts)) == len(starts), sv.title;
    }
}
