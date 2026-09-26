"""Vertical snap-scroll pager. Only the active card and its neighbours are
mounted; everything else is a same-height placeholder."""

import from react { useEffect }
import from .VideoCard { VideoCard }

sv import from ..services.catalog { VideoView, FeedItem }

def:pub FeedPager(
    items: list[FeedItem],
    activeIdx: int,
    paused: bool,
    loading: bool,
    emptyText: str,
    onActive: Callable[[int], None],
    onNearEnd: Callable[[], None],
    onReact: Callable[[str, str, bool], None],
    onOpenSheet: Callable[[VideoView], None],
    onWatched: Callable[[str, float, bool], None]
) -> JsxElement {
    has boxRef: Ref[any] = Ref();

    def handle_scroll(e: Event) {
        el: any = boxRef.current;
        if not el or el.clientHeight == 0 {
            return;
        }
        top = el.scrollTop as float;
        h = el.clientHeight as float;
        idx = int(top / h + 0.5);
        if idx != activeIdx and idx >= 0 and idx < len(items) {
            onActive(idx);
        }
        if idx >= len(items) - 3 {
            onNearEnd();
        }
    }

    useEffect(lambda {
        def on_key(e: any) {
            el: any = boxRef.current;
            tag = str(e.target.tagName or "");
            if not el or tag == "INPUT" or tag == "TEXTAREA" {
                return;
            }
            if e.key == "ArrowDown" or e.key == "j" {
                e.preventDefault();
                el.scrollBy({"top": el.clientHeight, "behavior": "smooth"});
            } elif e.key == "ArrowUp" or e.key == "k" {
                e.preventDefault();
                el.scrollBy({"top": -el.clientHeight, "behavior": "smooth"});
            }
        }
        window.addEventListener("keydown", on_key);
        return lambda { window.removeEventListener("keydown", on_key); };
    }, []);

    if len(items) == 0 {
        return <div className="pager empty">
            <p>{"Loading your feed…" if loading else emptyText}</p>
        </div>;
    }

    return <div className="pager" ref={boxRef} onScroll={handle_scroll}>
        {for (i, it) in enumerate(items) {
            <section key={(it.video.id if it.video is not None else "q" + str(i)) + "-" + str(i)} className="page">
                {if i >= activeIdx - 1 and i <= activeIdx + 1 {
                    <VideoCard
                        key="card"
                        item={it}
                        active={i == activeIdx and not paused}
                        onReact={onReact}
                        onOpenSheet={onOpenSheet}
                        onWatched={onWatched}
                    />
                }}
            </section>
        }}
        {loading and <section className="page page-loading"><p>Finding more good stuff…</p></section>}
    </div>;
}
