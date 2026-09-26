"""Scene templates for generated videos. LLM output only fills text/number params;
all markup/SVG here is ours, and React escapes every string."""

glob _IMG_HOSTS: list[str] = ["https://upload.wikimedia.org/", "https://thumb.wikimedia.org/"];

def _safe_img(src: str) -> str {
    for h in _IMG_HOSTS {
        if src and src.startswith(h) {
            return src;
        }
    }
    return "";
}

def _split(item: str) -> list[str] {
    if "|" not in item {
        return ["", item];
    }
    parts = item.split("|");
    rest = "";
    for (i, p) in enumerate(parts[1:]) {
        rest = rest + ("|" if i > 0 else "") + p;
    }
    return [parts[0], rest];
}

def _delay(i: int) -> dict[str, object] {
    return {"animationDelay": str(0.15 + i * 0.35) + "s"};
}

def:pub TitleCard(heading: str, body: str, emoji: str) -> JsxElement {
    return <div className="scene scene-title">
        <div className="scene-emoji">{emoji}</div>
        <h1 className="pop">{heading}</h1>
        {body and <p className="fade" style={_delay(1)}>{body}</p>}
    </div>;
}

def:pub BulletsScene(heading: str, items: list[str]) -> JsxElement {
    return <div className="scene scene-bullets">
        {heading and <h2 className="pop">{heading}</h2>}
        <ul>
            {for (i, it) in enumerate(items) {
                <li key={str(i)} className="slide" style={_delay(i + 1)}>{it}</li>
            }}
        </ul>
    </div>;
}

def:pub BigNumberScene(heading: str, body: str) -> JsxElement {
    return <div className="scene scene-number">
        <div className="big pop">{heading}</div>
        <p className="fade" style={_delay(1)}>{body}</p>
    </div>;
}

def:pub TimelineScene(heading: str, items: list[str]) -> JsxElement {
    n = max(1, len(items));
    return <div className="scene scene-timeline">
        {heading and <h2 className="pop">{heading}</h2>}
        <div className="timeline">
            <svg className="timeline-line" viewBox="0 0 20 100" preserveAspectRatio="none">
                <line x1="10" y1="0" x2="10" y2="100" stroke="currentColor" strokeWidth="2"/>
            </svg>
            {for (i, it) in enumerate(items) {
                <div key={str(i)} className="tl-row slide" style={_delay(i + 1)}>
                    <span className="tl-dot"/>
                    <span className="tl-year">{_split(it)[0]}</span>
                    <span className="tl-label">{_split(it)[1]}</span>
                </div>
            }}
        </div>
        <span className="sr-only">{str(n) + " events"}</span>
    </div>;
}

def:pub ProcessScene(heading: str, items: list[str]) -> JsxElement {
    return <div className="scene scene-process">
        {heading and <h2 className="pop">{heading}</h2>}
        {for (i, it) in enumerate(items) {
            <div key={str(i)} className="step-wrap slide" style={_delay(i + 1)}>
                <div className="step">{it}</div>
                {i < len(items) - 1 and <svg className="arrow" viewBox="0 0 24 24" width="28" height="28">
                    <path d="M12 4v14m0 0l-6-6m6 6l6-6" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"/>
                </svg>}
            </div>
        }}
    </div>;
}

def:pub ComparisonScene(heading: str, items: list[str]) -> JsxElement {
    parts = heading.split(" vs ");
    left_t = parts[0] if len(parts) > 0 else "";
    right_t = parts[1] if len(parts) > 1 else "";
    lefts = [_split(x)[1] for x in items if _split(x)[0] == "L"];
    rights = [_split(x)[1] for x in items if _split(x)[0] == "R"];
    return <div className="scene scene-compare">
        <div className="col col-left slide" style={_delay(0)}>
            <h3>{left_t}</h3>
            {for (i, x) in enumerate(lefts) { <p key={"l" + str(i)}>{x}</p> }}
        </div>
        <div className="vs pop">vs</div>
        <div className="col col-right slide" style={_delay(1)}>
            <h3>{right_t}</h3>
            {for (i, x) in enumerate(rights) { <p key={"r" + str(i)}>{x}</p> }}
        </div>
    </div>;
}

def:pub DefinitionScene(heading: str, body: str) -> JsxElement {
    return <div className="scene scene-definition">
        <div className="def-label fade">definition</div>
        <h2 className="pop">{heading}</h2>
        <p className="fade" style={_delay(1)}>{body}</p>
    </div>;
}

def:pub QuoteScene(heading: str, body: str) -> JsxElement {
    return <div className="scene scene-quote">
        <div className="quote-mark pop">“</div>
        <p className="fade">{body}</p>
        {heading and <div className="quote-by fade" style={_delay(1)}>{"— " + heading}</div>}
    </div>;
}

def:pub BarChartScene(heading: str, labels: list[str], values: list[float]) -> JsxElement {
    top = 1.0;
    for v in values {
        if v > top {
            top = v;
        }
    }
    return <div className="scene scene-bars">
        {heading and <h2 className="pop">{heading}</h2>}
        <div className="bars">
            {for (i, lab) in enumerate(labels) {
                <div key={str(i)} className="bar-row">
                    <span className="bar-label">{lab}</span>
                    <div className="bar-track">
                        <div
                            className="bar-fill grow"
                            style={{"width": str(int(100.0 * (values[i] if i < len(values) else 0.0) / top)) + "%", "animationDelay": str(0.2 + i * 0.25) + "s"}}
                        />
                    </div>
                    <span className="bar-value">{str(values[i]) if i < len(values) else ""}</span>
                </div>
            }}
        </div>
    </div>;
}

def:pub ImageScene(src: str, body: str, credit: str) -> JsxElement {
    safe = _safe_img(src);
    return <div className="scene scene-image">
        {safe and <img className="kenburns" src={safe} alt={body} referrerPolicy="no-referrer"/>}
        <div className="image-shade"/>
        {body and <p className="image-caption fade">{body}</p>}
        {credit and <div className="image-credit">{credit}</div>}
    </div>;
}

"""Dispatch a manifest scene dict to its template component."""
def:pub SceneView(scene: dict, emoji: str) -> JsxElement {
    tpl = str(scene["template"] or "title_card");
    heading = str(scene["heading"] or "");
    body = str(scene["body"] or "");
    items = (scene["items"] or []) as list[str];
    if tpl == "bullets" {
        return <BulletsScene heading={heading} items={items}/>;
    }
    if tpl == "big_number" {
        return <BigNumberScene heading={heading} body={body}/>;
    }
    if tpl == "timeline" {
        return <TimelineScene heading={heading} items={items}/>;
    }
    if tpl == "process_flow" {
        return <ProcessScene heading={heading} items={items}/>;
    }
    if tpl == "comparison" {
        return <ComparisonScene heading={heading} items={items}/>;
    }
    if tpl == "definition" {
        return <DefinitionScene heading={heading} body={body}/>;
    }
    if tpl == "quote" {
        return <QuoteScene heading={heading} body={body}/>;
    }
    if tpl == "bar_chart" {
        return <BarChartScene heading={heading} labels={(scene["labels"] or []) as list[str]} values={(scene["values"] or []) as list[float]}/>;
    }
    if tpl == "image" {
        img = scene["image"] or {};
        return <ImageScene src={str(img["src"] or "")} body={body} credit={str(img["credit"] or "")}/>;
    }
    return <TitleCard heading={heading} body={body} emoji={emoji}/>;
}
