"""Stateful shell: guest account bootstrap, feed state, tabs, overlays and
anti-brainrot session check-ins. Handler bodies live in AppShell.impl.jac."""

import from "@jac/runtime" { jacLogin, jacSignup, jacLogout, jacIsLoggedIn }
import from .FeedPager { FeedPager }
import from .browser { rand_token, url_param, store_get, store_set, store_del, log_error, prime_speech }
import from .Panels {
    SourcesSheet, CheckinCard, BreakScreen, Onboarding, TopicsPage, ProfilePage
}

sv import from ..services.catalog { VideoView, FeedItem, TopicView, ProfileView }
sv import from ..services.feed {
    LoadFeed, list_topics, get_video, get_profile, save_onboarding, follow_topic, log_view,
    set_reaction, report_video, list_saved
}

glob PAGE_SIZE: int = 6;

def:pub AppShell -> JsxElement {
    has booted: bool = False,
        bootError: str = "",
        unlocked: bool = False,
        tab: str = "feed",
        mode: str = "foryou",
        topicSlug: str = "",
        items: list[FeedItem] = [],
        activeIdx: int = 0,
        loading: bool = False,
        exhausted: bool = False,
        profile: ProfileView | None = None,
        topics: list[TopicView] = [],
        sheet: VideoView | None = None,
        showOnboarding: bool = False,
        checkin: bool = False,
        goalReached: bool = False,
        onBreak: bool = False,
        checkinMinutes: float = 0.0,
        checkinVideos: int = 0,
        checkinTopics: int = 0;
    has itemsRef: Ref[list[FeedItem]] = Ref([]),
        loadingRef: Ref[bool] = Ref(False),
        sessionSecs: Ref[float] = Ref(0.0),
        sessionVideos: Ref[int] = Ref(0),
        sessionTopics: Ref[list[str]] = Ref([]),
        lastCheckin: Ref[float] = Ref(0.0),
        goalShown: Ref[bool] = Ref(False);

    can with entry {
        boot();
    }

    def set_items(next: list[FeedItem]);
    async def fetchFeed(feedMode: str, slug: str, excl: list[str]) -> list[FeedItem];
    async def boot -> None;
    async def ensureAccount -> bool;
    async def loadMore(reset: bool) -> None;
    async def switchMode(nextMode: str, slug: str) -> None;
    async def handleReact(video_id: str, reaction: str, on: bool) -> None;
    async def handleWatched(video_id: str, secs: float, done: bool) -> None;
    async def handleReport(video_id: str, reason: str) -> None;
    async def finishOnboarding(picked: list[str], goal: int, every: int) -> None;
    async def followTopic(slug: str, on: bool) -> None;
    async def openSaved -> None;
    def unlock(e: MouseEvent);

    def handle_active(idx: int) {
        activeIdx = idx;
    }

    def handle_near_end() {
        if not exhausted and mode != "saved" {
            loadMore(False);
        }
    }

    def open_sheet(v: VideoView) {
        sheet = v;
    }

    def close_sheet() {
        sheet = None;
    }

    def keep_learning() {
        checkin = False;
    }

    def take_break() {
        checkin = False;
        onBreak = True;
    }

    def resume() {
        onBreak = False;
    }

    def watch_topic(slug: str) {
        tab = "feed";
        switchMode("topic", slug);
    }

    def go_home(e: MouseEvent) {
        tab = "feed";
        if mode == "saved" {
            switchMode("foryou", "");
        }
    }

    def go_saved(e: MouseEvent) {
        tab = "feed";
        openSaved();
    }

    overlay_open = (not unlocked) or showOnboarding or checkin or onBreak or sheet is not None or tab != "feed";
    current_topic = "";
    for t in topics {
        if t.slug == topicSlug {
            current_topic = t.emoji + " " + t.name;
        }
    }
    empty_text = "Save videos with ☆ to rewatch them here." if mode == "saved" else "Nothing here yet. Follow a topic or check back soon.";

    return <div className="app">
        <div className="phone">
            {tab == "feed" and <header className="top-tabs">
                <button className={"tab on" if mode == "foryou" else "tab"} onClick={lambda e: MouseEvent { switchMode("foryou", ""); }}>For You</button>
                <button className={"tab on" if mode == "following" else "tab"} onClick={lambda e: MouseEvent { switchMode("following", ""); }}>Following</button>
                {mode == "topic" and <span className="tab on">{current_topic}</span>}
                {mode == "saved" and <span className="tab on">★ Saved</span>}
            </header>}

            {tab == "feed" and <FeedPager
                items={items}
                activeIdx={activeIdx}
                paused={overlay_open}
                loading={loading}
                emptyText={empty_text}
                onActive={handle_active}
                onNearEnd={handle_near_end}
                onReact={handleReact}
                onOpenSheet={open_sheet}
                onWatched={handleWatched}
            />}
            {tab == "topics" and <TopicsPage topics={topics} onWatch={watch_topic} onFollow={followTopic}/>}
            {tab == "me" and <ProfilePage profile={profile} topics={topics}/>}

            <nav className="bottom-nav">
                <button className={"nav on" if tab == "feed" and mode != "saved" else "nav"} onClick={go_home}>⌂<span>Home</span></button>
                <button className={"nav on" if tab == "topics" else "nav"} onClick={lambda e: MouseEvent { tab = "topics"; }}>◎<span>Topics</span></button>
                <button className={"nav on" if tab == "feed" and mode == "saved" else "nav"} onClick={go_saved}>★<span>Saved</span></button>
                <button className={"nav on" if tab == "me" else "nav"} onClick={lambda e: MouseEvent { tab = "me"; }}>☺<span>You</span></button>
            </nav>

            {sheet is not None and <SourcesSheet video={sheet} onClose={close_sheet} onReport={handleReport}/>}
            {checkin and <CheckinCard
                minutes={checkinMinutes} videos={checkinVideos} topics={checkinTopics}
                goalReached={goalReached} onContinue={keep_learning} onBreak={take_break}
            />}
            {onBreak and <BreakScreen onResume={resume}/>}
            {showOnboarding and unlocked and <Onboarding topics={topics} onDone={finishOnboarding}/>}
            {not unlocked and <div className="overlay splash" onClick={unlock}>
                <div className="splash-inner">
                    <div className="logo">🧠</div>
                    <h1>SmartTok</h1>
                    <p>Short videos worth your time: science, engineering, history, languages, DIY and balanced news.</p>
                    {bootError and <p className="error">{bootError}</p>}
                    <button className="pill big">{"Tap to start" if booted else "Loading…"}</button>
                </div>
            </div>}
        </div>
    </div>;
}
