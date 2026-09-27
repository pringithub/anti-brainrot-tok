"""Marketing landing page: describes SmartTok and showcases screenshots of it running."""

import from "@jac/runtime" { Link }

obj Shot {
    has src: str,
        alt: str,
        caption: str;
}

obj Feature {
    has emoji: str,
        title: str,
        body: str;
}

glob SHOTS: list[Shot] = [
    Shot(
        src="/static/screenshots/onboarding.png", alt="Topic picker onboarding screen",
        caption="Pick what you're curious about, set a daily goal and a check-in cadence."
    ),
    Shot(
        src="/static/screenshots/feed.png", alt="Vertical swipe feed with a science short playing",
        caption="A full-screen swipe feed — like/save/share/sources/not-useful on every video."
    ),
    Shot(
        src="/static/screenshots/sources-sheet.png", alt="Sources sheet showing why a video was recommended and its quality score",
        caption="Every video explains itself: why you're seeing it and a quality score."
    ),
    Shot(
        src="/static/screenshots/topics.png", alt="Topics browser listing Current Events, Engineering, Science and more",
        caption="Browse by topic — Current Events, Engineering, Science, History and more."
    ),
    Shot(
        src="/static/screenshots/profile.png", alt="You tab showing daily goal progress, streak and narration voice picker",
        caption="Daily goal, streak and recall stats, without ever asking you to sign up."
    ),
];

glob FEATURES: list[Feature] = [
    Feature(
        emoji="🧠", title="Anti-brainrot by design",
        body="Ranking favours quality, interest and topic variety over raw watch time, "
            + "with daily goals, session check-ins and a take-a-break screen."
    ),
    Feature(
        emoji="🎥", title="Two kinds of content",
        body="Curated YouTube Shorts from ~60 hand-picked educational channels, plus SmartTok's own "
            + "~60s generated explainers, fact-checked against what they cite."
    ),
    Feature(
        emoji="🔍", title="Nothing is a black box",
        body="A Sources sheet on every video shows why it was recommended, a quality score and, "
            + "for generated videos, the Wikipedia sources and image credits behind it."
    ),
    Feature(
        emoji="👤", title="Personalised, no sign-up",
        body="Every browser gets a guest account automatically — pick topics and SmartTok remembers "
            + "your goals, streak and saves."
    ),
];

def:pub Landing -> JsxElement {
    return <div className="lp">
        <header className="lp-hero">
            <div className="lp-hero-inner">
                <div className="lp-logo">🧠 SmartTok</div>
                <h1>Scroll smarter.</h1>
                <p className="lp-sub">
                    A TikTok-style vertical video feed where every video is worth your time: science,
                    engineering, history, languages, DIY and balanced news — curated and fact-checked,
                    not optimised to keep you scrolling forever.
                </p>
                <div className="lp-cta-row">
                    <Link className="pill big" to="/app">Open the app</Link>
                    <a className="pill ghost big" href="https://github.com/pringithub/anti-brainrot-tok" target="_blank" rel="noopener noreferrer">
                        View on GitHub
                    </a>
                </div>
            </div>
        </header>

        <section className="lp-section">
            <h2>See it in action</h2>
            <div className="lp-shots">
                {for s in SHOTS {
                    <figure key={s.src} className="lp-shot">
                        <div className="lp-shot-frame">
                            <img src={s.src} alt={s.alt} loading="lazy"/>
                        </div>
                        <figcaption>{s.caption}</figcaption>
                    </figure>
                }}
            </div>
        </section>

        <section className="lp-section lp-features">
            <h2>Why SmartTok</h2>
            <div className="lp-feature-grid">
                {for f in FEATURES {
                    <div key={f.title} className="lp-feature">
                        <div className="lp-feature-emoji">{f.emoji}</div>
                        <h3>{f.title}</h3>
                        <p>{f.body}</p>
                    </div>
                }}
            </div>
        </section>

        <section className="lp-section lp-how">
            <h2>How it works</h2>
            <img
                className="lp-how-diagram" src="/static/jac_learning_platform.png"
                alt="SmartTok architecture diagram: client, server agents, graph store and external services"
                loading="lazy"
            />
            <p className="lp-how-p">
                The catalog (topics, videos, channels) lives on a shared graph; each user has a profile
                node tracking what they've watched. A ranking walker scores and diversifies a feed on
                every request. AI runs only on the server, only for background work: scoring new videos
                and running a research agent that reads Wikipedia, writes a script, fact-checks each
                claim against its sources and revises before publishing.
            </p>
        </section>

        <footer className="lp-footer">
            <Link className="pill big" to="/app">Open the app</Link>
            <p className="small">Built with <a href="https://www.jaseci.org/" target="_blank" rel="noopener noreferrer">Jac</a></p>
        </footer>
    </div>;
}
