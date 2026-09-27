"""Handler bodies for AppShell. Component `has` state is referenced bare."""

impl AppShell.set_items(next: list[FeedItem]) {
    itemsRef.current = next;
    items = next;
}

impl AppShell.unlock(e: MouseEvent) {
    if not booted {
        return;
    }
    # Speaking once inside the user gesture unlocks speech synthesis for the session.
    prime_speech();
    unlocked = True;
}

impl AppShell.ensureAccount -> bool {
    ok: bool = False;
    signup: dict | None = None;
    if jacIsLoggedIn() {
        return True;
    }
    uname = store_get("abt_u");
    pwd = store_get("abt_p");
    is_new = not uname or not pwd;
    if is_new {
        uname = "g_" + rand_token(20);
        pwd = rand_token(48);
        store_set("abt_u", uname);
        store_set("abt_p", pwd);
    } else {
        ok = await jacLogin(uname, pwd);
        if ok {
            return True;
        }
    }
    signup = await jacSignup(uname, pwd);
    if signup is not None and signup["success"] {
        ok = await jacLogin(uname, pwd);
    }
    return ok;
}

impl AppShell.boot -> None {
    ok: bool = False;
    prof: ProfileView | None = None;
    tl: list[TopicView] | None = None;
    shared: FeedItem | None = None;
    try {
        ok = await ensureAccount();
        if ok {
            try {
                prof = await get_profile();
            } except Exception {
                # Stale token (e.g. server data reset): start a fresh guest account.
                jacLogout();
                store_del("abt_u");
                store_del("abt_p");
                ok = await ensureAccount();
                if ok {
                    prof = await get_profile();
                }
            }
        }
        profile = prof;
        tl = await list_topics();
        topics = tl or [];
        showOnboarding = prof is not None and not prof.onboarded;
        shared_id = url_param("v");
        if shared_id {
            shared = await get_video(shared_id);
        }
        await loadMore(True);
        if shared is not None {
            current: list[FeedItem] = itemsRef.current or [];
            set_items([shared] + current);
        }
        if not ok {
            bootError = "Couldn't create a guest session; personalisation is off.";
        }
    } except Exception as err {
        log_error("boot", err);
        bootError = "Couldn't reach the server. Is it running?";
    }
    booted = True;
}

impl AppShell.fetchFeed(feedMode: str, slug: str, excl: list[str]) -> list[FeedItem] {
    page: list[FeedItem] = [];
    try {
        result = root spawn LoadFeed(mode=feedMode, topic=slug, exclude=excl, limit=PAGE_SIZE);
        if result.reports and len(result.reports) > 0 {
            page = result.reports[0] or [];
        }
    } except Exception as err {
        log_error("feed", err);
    }
    return page;
}

impl AppShell.loadMore(reset: bool) -> None {
    page: list[FeedItem] = [];
    if loadingRef.current {
        return;
    }
    loadingRef.current = True;
    loading = True;
    base: list[FeedItem] = [] if reset else (itemsRef.current or []);
    exclude: list[str] = [];
    for it in base {
        if it.video is not None {
            exclude.append(it.video.id);
        }
        if it.quiz is not None {
            exclude.append("quiz:" + it.quiz.video_id);
        }
    }
    page = await fetchFeed(mode, topicSlug, exclude);
    exhausted = len(page) == 0;
    set_items(base + page);
    if reset {
        activeIdx = 0;
    }
    loading = False;
    loadingRef.current = False;
}

impl AppShell.switchMode(nextMode: str, slug: str) -> None {
    page: list[FeedItem] = [];
    mode = nextMode;
    topicSlug = slug;
    exhausted = False;
    activeIdx = 0;
    set_items([]);
    loadingRef.current = True;
    loading = True;
    # State writes above are async; pass explicit values.
    page = await fetchFeed(nextMode, slug, []);
    set_items(page);
    exhausted = len(page) == 0;
    loading = False;
    loadingRef.current = False;
}

impl AppShell.openSaved -> None {
    saved: list[FeedItem] | None = None;
    mode = "saved";
    topicSlug = "";
    activeIdx = 0;
    set_items([]);
    loading = True;
    try {
        saved = await list_saved();
    } except Exception as err {
        log_error("saved", err);
    }
    set_items(saved or []);
    exhausted = True;
    loading = False;
}

impl AppShell.handleReact(video_id: str, reaction: str, on: bool) -> None {
    updated: VideoView | None = None;
    try {
        updated = await set_reaction(video_id, reaction, on);
    } except Exception as err {
        log_error("react", err);
        return;
    }
    if updated is None {
        return;
    }
    current = itemsRef.current or [];
    if reaction == "not_useful" {
        set_items([it for it in current if it.video is None or it.video.id != video_id]);
        return;
    }
    # sv-imported obj constructors compile to RPC calls, so update in place.
    for it in current {
        if it.video is not None and it.video.id == video_id {
            it.video.liked = updated.liked;
            it.video.saved = updated.saved;
        }
    }
    set_items(list(current));
}

impl AppShell.handleWatched(video_id: str, secs: float, done: bool) -> None {
    prof: ProfileView | None = None;
    if secs < 0.5 {
        return;
    }
    watch_s = secs;
    completed = done;
    try {
        prof = await log_view(video_id, watch_s, completed);
    } except Exception as err {
        log_error("view", err);
        return;
    }
    if prof is None {
        return;
    }
    profile = prof;
    sessionSecs.current = (sessionSecs.current or 0.0) + secs;
    sessionVideos.current = (sessionVideos.current or 0) + 1;
    for it in itemsRef.current or [] {
        if it.video is not None and it.video.id == video_id {
            seen = sessionTopics.current or [];
            if it.video.topic not in seen {
                sessionTopics.current = seen + [it.video.topic];
            }
        }
    }
    since = (sessionSecs.current or 0.0) - (lastCheckin.current or 0.0);
    reached = prof.today_minutes >= prof.daily_goal_min and not goalShown.current;
    if since >= prof.checkin_every * 60 or reached {
        lastCheckin.current = sessionSecs.current;
        if reached {
            goalShown.current = True;
        }
        goalReached = reached;
        checkinMinutes = (sessionSecs.current or 0.0) / 60.0;
        checkinVideos = sessionVideos.current or 0;
        checkinTopics = len(sessionTopics.current or []);
        checkin = True;
    }
}

impl AppShell.handleReport(video_id: str, reason: str) -> None {
    try {
        await report_video(video_id, reason);
    } except Exception as err {
        log_error("report", err);
    }
}

impl AppShell.finishOnboarding(picked: list[str], goal: int, every: int) -> None {
    prof: ProfileView | None = None;
    try {
        prof = await save_onboarding(picked, goal, every);
    } except Exception as err {
        log_error("onboarding", err);
    }
    if prof is not None {
        profile = prof;
    }
    showOnboarding = False;
    await switchMode("foryou", "");
}

impl AppShell.followTopic(slug: str, on: bool) -> None {
    followed: list[str] | None = None;
    tl: list[TopicView] | None = None;
    try {
        followed = await follow_topic(slug, on);
        tl = await list_topics();
    } except Exception as err {
        log_error("follow", err);
    }
    if tl is not None {
        topics = tl;
    }
}

impl AppShell.setVoicePref(pref: str) -> None {
    prof: ProfileView | None = None;
    try {
        prof = await set_tts_pref(pref);
    } except Exception as err {
        log_error("voice", err);
        return;
    }
    if prof is not None {
        profile = prof;
    }
}
