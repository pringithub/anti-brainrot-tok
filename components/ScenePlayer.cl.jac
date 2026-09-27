"""Plays a generated video's scene manifest: narration audio (ElevenLabs mp3) or
browser speech synthesis, with scenes and captions synced to the narration."""

import from react { useEffect, useMemo }
import from .Scenes { SceneView }

def _synth -> any {
    g: any = globalThis;
    return g.speechSynthesis;
}

def _chunk(words: list[list], a: int, b: int) -> str {
    out = "";
    for w in words[a:b] {
        out = (out + " " + str(w[0])) if out else str(w[0]);
    }
    return out;
}

def _scene_at(scenes: list[dict], t: float) -> int {
    idx = 0;
    for (i, sc) in enumerate(scenes) {
        if float(sc["t"] or 0) <= t + 0.05 {
            idx = i;
        }
    }
    return idx;
}

def _word_at(words: list[list], t: float) -> int {
    k = 0;
    for (i, w) in enumerate(words) {
        if float(str(w[1])) <= t {
            k = i;
        }
    }
    return k;
}

def:pub ScenePlayer(
    manifestJson: str, emoji: str, active: bool, voicePref: str, onEnded: Callable[[], None]
) -> JsxElement {
    has t: float = 0.0,
        speechScene: int = 0,
        paused: bool = False,
        blocked: bool = False,
        ended: bool = False,
        replayKey: int = 0;
    has audioRef: Ref[any] = Ref(),
        genRef: Ref[int] = Ref(0),
        startRef: Ref[float] = Ref(0.0);

    m: any = useMemo(lambda -> any {
        try {
            return JSON.parse(manifestJson);
        } except Exception {
            return {};
        }
    }, [manifestJson]);
    scenes = (m["scenes"] or []) as list[dict];
    words = (m["words"] or []) as list[list];
    use_audio = (voicePref == "elevenlabs") and (m["tts"] == "elevenlabs") and bool(m["audio"]);
    duration = float(m["duration"] or 30);

    def _pick_voice -> any {
        synth = _synth();
        if not synth or voicePref != "google" {
            return None;
        }
        voices = (synth.getVoices() or []) as list[any];
        for v in voices {
            if "google" in str(v.name or "").lower() {
                return v;
            }
        }
        return None;
    }

    def speak_all(gen: int) {
        synth = _synth();
        if not synth {
            return;
        }
        synth.cancel();
        startRef.current = Date.now();
        n = len(scenes);
        for i in range(n) {
            a = int(scenes[i]["w"] or 0);
            b = int(scenes[i + 1]["w"] or 0) if i + 1 < n else len(words);
            queue_utterance(_chunk(words, a, b), i, i == n - 1, gen);
        }
    }

    def queue_utterance(text: str, idx: int, last: bool, gen: int) {
        g: any = globalThis;
        u: any = new(g.SpeechSynthesisUtterance, text);  # jac:ignore[E1053]
        u.rate = 1.0;
        u.lang = "en-US";
        voice = _pick_voice();
        if voice {
            u.voice = voice;
        }
        u.onstart = lambda {
            if genRef.current == gen {
                speechScene = idx;
            }
        };
        if last {
            u.onend = lambda {
                if genRef.current == gen {
                    ended = True;
                    onEnded();
                }
            };
        }
        _synth().speak(u);
    }


    useEffect(lambda {
        gen = (genRef.current or 0) + 1;
        genRef.current = gen;
        el: any = audioRef.current;
        if not active {
            if use_audio and el {
                el.pause();
            }
            if not use_audio and _synth() {
                _synth().cancel();
            }
            return;
        }
        t = 0.0;
        speechScene = 0;
        ended = False;
        paused = False;
        if use_audio and el {
            el.currentTime = 0;
            p = el.play();
            if p {
                p.catch(lambda e: any { blocked = True; });
            }
            timer = setInterval(lambda { t = el.currentTime as float; }, 120);
            return lambda { clearInterval(timer); el.pause(); };
        }
        speak_all(gen);
        timer2 = setInterval(lambda {
            if genRef.current == gen {
                t = min(duration, (Date.now() - startRef.current) / 1000.0);
            }
        }, 200);
        return lambda {
            clearInterval(timer2);
            genRef.current = (genRef.current or 0) + 1;
            if _synth() {
                _synth().cancel();
            }
        };
    }, [active, replayKey]);

    def handle_tap(e: MouseEvent) {
        el: any = audioRef.current;
        if blocked {
            blocked = False;
            if el {
                el.play();
            }
            return;
        }
        if ended {
            return;
        }
        if use_audio and el {
            if el.paused {
                el.play();
                paused = False;
            } else {
                el.pause();
                paused = True;
            }
        } elif _synth() {
            if paused {
                _synth().resume();
                paused = False;
            } else {
                _synth().pause();
                paused = True;
            }
        }
    }

    def handle_replay(e: MouseEvent) {
        e.stopPropagation();
        replayKey = replayKey + 1;
    }

    def handle_audio_end(e: Event) {
        ended = True;
        onEnded();
    }

    idx = _scene_at(scenes, t) if use_audio else speechScene;
    scene = scenes[idx] if idx < len(scenes) else {"template": "title_card"};
    a = int(scene["w"] or 0);
    b = int(scenes[idx + 1]["w"] or 0) if idx + 1 < len(scenes) else len(words);
    k = _word_at(words, t) if use_audio else -1;
    lo = max(a, k - 5) if use_audio else a;
    hi = min(b, k + 7) if use_audio else b;
    progress = min(100.0, 100.0 * t / duration) if duration > 0 else 0.0;

    return <div className="scene-player" onClick={handle_tap}>
        <div className="progress"><div className="progress-fill" style={{"width": str(progress) + "%"}}/></div>
        <div key={str(idx) + "-" + str(replayKey)} className="scene-frame">
            <SceneView scene={scene} emoji={emoji}/>
        </div>
        <div className="captions">
            {for i in range(lo, hi) {
                <span key={str(i)} className={"cap-word now" if i == k else "cap-word"}>{str(words[i][0]) + " "}</span>
            }}
        </div>
        {use_audio and <audio ref={audioRef} src={str(m["audio"])} preload="auto" onEnded={handle_audio_end}/>}
        {paused and <div className="center-badge">❚❚</div>}
        {blocked and <div className="center-badge">▶ Tap to play</div>}
        {ended and <div className="end-card">
            <button className="pill" onClick={handle_replay}>↻ Replay</button>
            <span className="hint">Swipe up for the next one</span>
        </div>}
    </div>;
}
