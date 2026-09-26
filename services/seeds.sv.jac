"""Hand-authored editorial seed videos so the generated mode works without an LLM key.
Each segment is one scene; scene start words are computed from segment lengths."""

import from services.ai { Script, SceneSpec }

obj Segment {
    has text: str,
        scene: SceneSpec;
}

obj SeedVideo {
    has topic: str,
        title: str,
        summary: str,
        segments: list[Segment],
        citations: list[str],
        quiz_question: str,
        quiz_choices: list[str],
        quiz_answer: int,
        quiz_explanation: str,
        tags: list[str];

    def to_script -> Script {
        parts: list[str] = [];
        scenes: list[SceneSpec] = [];
        n = 0;
        for seg in self.segments {
            seg.scene.start_word = n;
            scenes.append(seg.scene);
            parts.append(seg.text.strip());
            n += len(seg.text.split());
        }
        return Script(
            title=self.title,
            summary=self.summary,
            narration=" ".join(parts),
            scenes=scenes,
            citations=self.citations,
            quiz_question=self.quiz_question,
            quiz_choices=self.quiz_choices,
            quiz_answer=self.quiz_answer,
            quiz_explanation=self.quiz_explanation,
            tags=self.tags
        );
    }
}

def _s(template: str, heading: str = "", body: str = "", items: list[str] = [], labels: list[str] = [],
       values: list[float] = [], image_query: str = "") -> SceneSpec {
    return SceneSpec(
        template=template, start_word=0, heading=heading, body=body, items=items, labels=labels,
        values=values, image_query=image_query
    );
}

def seed_videos() -> list[SeedVideo] {
    return [
        SeedVideo(
            topic="engineering",
            title="Why Roman concrete lasts 2,000 years",
            summary="Volcanic ash, seawater crystals and self-healing lime clasts explain Roman concrete's durability.",
            segments=[
                Segment(text="Why is two-thousand-year-old Roman concrete still standing, when some modern concrete cracks within decades?",
                        scene=_s("title_card", "Why Roman concrete lasts", "Engineering · 2,000 years and counting")),
                Segment(text="Take the Pantheon in Rome. Finished around 126 AD, its dome is still the largest unreinforced concrete dome in the world.",
                        scene=_s("image", body="The Pantheon's dome, completed around 126 AD", image_query="Pantheon Rome dome interior")),
                Segment(text="Part of the secret is volcanic ash. Roman builders mixed lime with ash from around the Bay of Naples, forming mineral binders that are strong and resist chemical attack.",
                        scene=_s("process_flow", "The recipe", items=["Lime", "Volcanic ash", "Water", "Strong mineral binders"])),
                Segment(text="In harbour walls, seawater seeping through the concrete helped grow rare crystals, like aluminous tobermorite, that reinforce the material over time.",
                        scene=_s("definition", "Aluminous tobermorite", "A rare crystal that grows inside Roman marine concrete and strengthens it")),
                Segment(text="A 2023 study led by researchers at MIT found another trick: small white chunks of lime, called lime clasts, left behind by mixing with quicklime while hot.",
                        scene=_s("big_number", "2023", "MIT-led study explains the mysterious white lime clasts")),
                Segment(text="When a crack forms and water gets in, those clasts dissolve and re-harden as calcium carbonate, sealing the crack. The concrete partly heals itself.",
                        scene=_s("process_flow", "Self-healing", items=["Crack forms", "Water gets in", "Lime clast dissolves", "Calcium carbonate seals it"])),
                Segment(text="Engineers are now testing these ideas to make modern concrete that lasts longer and needs fewer repairs.",
                        scene=_s("bullets", "Why it matters", items=["Longer-lasting structures", "Fewer repairs"]))
            ],
            citations=[
                "https://en.wikipedia.org/wiki/Roman_concrete",
                "https://en.wikipedia.org/wiki/Pantheon,_Rome",
                "https://news.mit.edu/2023/roman-concrete-durability-lime-casts-0106"
            ],
            quiz_question="What do lime clasts do when water gets into a crack?",
            quiz_choices=["Dissolve and re-harden to seal it", "Expand and widen the crack", "Turn into volcanic ash", "Nothing, they are impurities"],
            quiz_answer=0,
            quiz_explanation="The lime dissolves and recrystallises as calcium carbonate, filling the crack.",
            tags=["concrete", "rome", "materials"]
        ),
        SeedVideo(
            topic="science",
            title="Why the sky is blue but sunsets are red",
            summary="Rayleigh scattering makes short wavelengths scatter more, colouring the day sky blue and sunsets red.",
            segments=[
                Segment(text="Why is the sky blue, but sunsets red? The answer is the same physics.",
                        scene=_s("title_card", "Blue sky, red sunset", "Science · one idea, two colours")),
                Segment(text="Sunlight looks white, but it contains every colour of the rainbow, each with a different wavelength.",
                        scene=_s("bar_chart", "Wavelength (nm)", labels=["Violet", "Blue", "Green", "Yellow", "Red"], values=[400.0, 450.0, 530.0, 580.0, 680.0])),
                Segment(text="When light hits the tiny nitrogen and oxygen molecules in air, it gets scattered in all directions. This is called Rayleigh scattering.",
                        scene=_s("definition", "Rayleigh scattering", "Scattering of light by particles much smaller than its wavelength")),
                Segment(text="Shorter wavelengths scatter far more strongly, roughly with one over the wavelength to the fourth power. Blue light scatters about five times more than red.",
                        scene=_s("big_number", "~5×", "How much more strongly blue light scatters than red")),
                Segment(text="So blue light reaches your eyes from every part of the sky. Violet scatters even more, but sunlight contains less of it and our eyes are less sensitive to it.",
                        scene=_s("bullets", "Why not violet?", items=["Less violet in sunlight", "Our eyes are less sensitive to it"])),
                Segment(text="At sunset, light travels through much more air to reach you. Most of the blue is scattered away along the path, leaving the reds and oranges.",
                        scene=_s("comparison", "Noon vs Sunset", items=["L|Short path through air", "L|Blue scattered toward you", "R|Long path through air", "R|Blue scattered away"])),
                Segment(text="Same sky, same physics, just a different path length.",
                        scene=_s("image", body="Longer path, redder light", image_query="sunset over sea"))
            ],
            citations=[
                "https://en.wikipedia.org/wiki/Rayleigh_scattering",
                "https://en.wikipedia.org/wiki/Diffuse_sky_radiation"
            ],
            quiz_question="Why are sunsets red?",
            quiz_choices=["Light passes through more air, scattering blue away", "The Sun cools down in the evening", "Red light scatters the most", "Dust turns blue light red"],
            quiz_answer=0,
            quiz_explanation="The long path through the atmosphere scatters most blue light out before it reaches you.",
            tags=["light", "physics", "atmosphere"]
        ),
        SeedVideo(
            topic="languages",
            title="Where does the word OK come from?",
            summary="OK began as an 1839 Boston newspaper joke abbreviation and spread through an 1840 election campaign.",
            segments=[
                Segment(text="OK might be one of the most widely used words on the planet. But where did it come from?",
                        scene=_s("title_card", "Where does OK come from?", "Linguistics · a word with a surprising past")),
                Segment(text="In the late 1830s, Boston newspapers had a fad for joke abbreviations, often of deliberately misspelled phrases.",
                        scene=_s("bullets", "1830s newspaper fad", items=["O.W. for 'oll wright'", "G.T. for 'gone to Texas'", "O.K. for 'oll korrect'"])),
                Segment(text="On March 23, 1839, the Boston Morning Post printed O.K., glossed as 'all correct', a jokey misspelling of the phrase.",
                        scene=_s("big_number", "1839", "First known printed O.K., in the Boston Morning Post")),
                Segment(text="Most of those jokes quickly vanished. OK survived, partly thanks to politics.",
                        scene=_s("quote", "Why did it survive?", "Most joke abbreviations vanished. OK didn't.")),
                Segment(text="In the 1840 presidential election, supporters of Martin Van Buren, nicknamed Old Kinderhook after his hometown, used O.K. as a slogan.",
                        scene=_s("image", body="Martin Van Buren, 'Old Kinderhook'", image_query="Martin Van Buren portrait")),
                Segment(text="The story was pieced together by linguist Allen Walker Read, who traced these early uses in the 1960s.",
                        scene=_s("definition", "Allen Walker Read", "American linguist who traced OK's origin in the 1960s")),
                Segment(text="From a Boston newspaper joke, OK went on to spread into languages around the world.",
                        scene=_s("timeline", "OK's journey", items=["1839|Boston joke abbreviation", "1840|Old Kinderhook campaign", "1960s|Read traces the origin", "Today|Used worldwide"]))
            ],
            citations=["https://en.wikipedia.org/wiki/OK"],
            quiz_question="What did O.K. originally stand for?",
            quiz_choices=["Oll korrect", "Only kidding", "Old Kinderhook", "Open kitchen"],
            quiz_answer=0,
            quiz_explanation="It began as 'oll korrect'; 'Old Kinderhook' came a year later and helped it spread.",
            tags=["etymology", "english", "history"]
        )
    ];
}
