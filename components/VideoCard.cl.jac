"""One feed item. Generated videos are full-bleed with SmartTok overlays; third-party
embeds get a framed layout where nothing covers the player, so YouTube's own
controls and ours are both visible and usable. Reports dwell time on deactivate."""

import from react { useEffect }
import from .ScenePlayer { ScenePlayer }
import from .QuizCard { QuizCard }
import from .browser { now_ms }

sv import from ..services.catalog { VideoView, FeedItem }

glob EMBED_COMPLETE_S: float = 40.0;
glob DOUBLE_TAP_MS: float = 320.0;

def:pub EmbedPlayer(video: VideoView, active: bool) -> JsxElement {
    if not active or not video.embed_url.startswith("https://www.youtube-nocookie.com/embed/") {
        return <div className="embed-poster">
            {video.thumbnail_url and <img src={video.thumbnail_url} alt="" referrerPolicy="no-referrer"/>}
        </div>;
    }
    return <iframe
        className="embed-frame"
        src={video.embed_url}
        title={video.title}
        allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
        referrerPolicy="strict-origin-when-cross-origin"
        allowFullScreen={True}
    />;
}

def:pub RailButton(icon: str, label: str, on: bool, onPress: Callable[[], None]) -> JsxElement {
    def press(e: MouseEvent) {
        e.stopPropagation();
        onPress();
    }
    return <button className={"rail-btn on" if on else "rail-btn"} onClick={press} aria-label={label}>
        <span className="rail-icon">{icon}</span>
        <span className="rail-label">{label}</span>
    </button>;
}

def:pub VideoCard(
    item: FeedItem,
    active: bool,
    voicePref: str,
    onReact: Callable[[str, str, bool], None],
    onOpenSheet: Callable[[VideoView], None],
    onWatched: Callable[[str, float, bool], None],
    onNext: Callable[[], None]
) -> JsxElement {
    has startRef: Ref[float] = Ref(0.0),
        doneRef: Ref[bool] = Ref(False),
        lastTapRef: Ref[float] = Ref(0.0);
    has heart: bool = False;

    video = item.video;
    vid = video.id if video is not None else "";

    useEffect(lambda {
        if not active or not vid {
            return;
        }
        startRef.current = Date.now();
        doneRef.current = False;
        return lambda {
            secs = (Date.now() - (startRef.current or 0.0)) / 1000.0;
            done = bool(doneRef.current) or (video is not None and video.kind == "curated" and secs >= EMBED_COMPLETE_S);
            onWatched(vid, secs, done);
        };
    }, [active, vid]);

    if item.kind == "quiz" and item.quiz is not None {
        return <div className="card card-quiz"><QuizCard quiz={item.quiz}/></div>;
    }
    if video is None {
        return <div className="card"/>;
    }

    def mark_done() {
        doneRef.current = True;
    }

    def toggle_like() {
        onReact(vid, "like", not video.liked);
    }

    def toggle_save() {
        onReact(vid, "save", not video.saved);
    }

    def not_useful() {
        onReact(vid, "not_useful", True);
    }

    def open_info() {
        onOpenSheet(video);
    }

    def go_next(e: MouseEvent) {
        e.stopPropagation();
        onNext();
    }

    def share() {
        url = window.location.origin + "/app?v=" + vid;
        nav: any = window.navigator;
        if nav.share {
            nav.share({"title": video.title, "url": url}).catch(lambda e: any {});
        } elif nav.clipboard {
            nav.clipboard.writeText(url);
        }
    }

    # onDoubleClick is unreliable on touch screens, so detect double taps from click timing.
    def handle_tap(e: MouseEvent) {
        t = now_ms();
        if t - (lastTapRef.current or 0.0) > DOUBLE_TAP_MS {
            lastTapRef.current = t;
            return;
        }
        lastTapRef.current = 0.0;
        if not video.liked {
            onReact(vid, "like", True);
        }
        heart = True;
        setTimeout(lambda { heart = False; }, 700);
    }

    return <div className={"card card-" + video.kind} onClick={handle_tap}>
        <div className="media">
            {video.kind == "generated"
                and <ScenePlayer manifestJson={video.manifest_json} emoji={video.topic_emoji} active={active} voicePref={voicePref} onEnded={mark_done}/>}
            {video.kind != "generated" and <EmbedPlayer video={video} active={active}/>}
        </div>
        {heart and <div className="big-heart">♥</div>}
        <div className="rail">
            <RailButton icon={"♥" if video.liked else "♡"} label="Like" on={video.liked} onPress={toggle_like}/>
            <RailButton icon={"★" if video.saved else "☆"} label="Save" on={video.saved} onPress={toggle_save}/>
            <RailButton icon="ⓘ" label="Sources" on={False} onPress={open_info}/>
            <RailButton icon="↗" label="Share" on={False} onPress={share}/>
            <RailButton icon="⊘" label="Not useful" on={False} onPress={not_useful}/>
        </div>
        <div className="info">
            <div className="chips">
                <span className="chip">{video.topic_emoji + " " + video.topic_name}</span>
                {video.kind == "generated" and <span className="chip chip-gen">Generated · cited</span>}
                {video.topic == "current-events" and <span className="chip chip-news">Multi-source · reviewed</span>}
            </div>
            <div className="creator">{"@" + video.creator_name}</div>
            <div className="title">{video.title}</div>
            {video.why and <div className="why">{video.why}</div>}
            {video.kind != "generated" and <button className="pill next-btn" onClick={go_next}>Next ↓</button>}
        </div>
    </div>;
}
