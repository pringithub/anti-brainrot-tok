"""Thin typed wrappers over browser globals (the checker has no stubs for them)."""

def _g -> any {
    g: any = globalThis;
    return g;
}

def:pub rand_token(n: int) -> str {
    raw = str(_g().crypto.randomUUID()) + str(_g().crypto.randomUUID());
    return raw.replace("-", "").replace("-", "").replace("-", "").replace("-", "")[:n];
}

def:pub url_param(name: str) -> str {
    params: any = _g().URLSearchParams;
    q: any = _g().Reflect.construct(params, [str(_g().location.search)]);
    return str(q.get(name) or "");
}

def:pub store_get(key: str) -> str {
    return str(_g().localStorage.getItem(key) or "");
}

def:pub store_set(key: str, value: str) {
    _g().localStorage.setItem(key, value);
}

def:pub store_del(key: str) {
    _g().localStorage.removeItem(key);
}

def:pub log_error(tag: str, err: any) {
    _g().console.error("[" + tag + "]", err);
}

def:pub origin -> str {
    return str(_g().location.origin);
}

def:pub now_ms -> float {
    return _g().Date.now() as float;
}

"""Send a YouTube IFrame API command (needs enablejsapi=1 on the embed URL)."""
def:pub yt_command(frame: any, fn: str) {
    if frame and frame.contentWindow {
        msg = _g().JSON.stringify({"event": "command", "func": fn, "args": []});
        frame.contentWindow.postMessage(msg, "https://www.youtube-nocookie.com");
    }
}

def:pub prime_speech {
    s: any = _g().speechSynthesis;
    if s {
        u: any = _g().Reflect.construct(_g().SpeechSynthesisUtterance, [" "]);
        u.volume = 0;
        s.speak(u);
    }
}
