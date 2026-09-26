"""Admin CLI for SmartTok. Calls the running server's admin endpoints
anonymously with ABT_ADMIN_KEY. Suitable for cron.

  jac run tools/admin.jac <command> [args]

Commands:
  stats                         catalog counts
  bootstrap [--no-seeds]        create topics/channels (+ editorial seed videos)
  curate [max_per_channel] [channel]
  plan [target_live] [max_new]  PlanCatalog walker: queue curate/generate jobs
  jobs [status]                 list jobs (queued|running|done|failed, default all)
  run-jobs [n]                  process up to n queued jobs
  generate "<subject>" <topic>  research agent -> video
  review [status]               list videos by status (default review)
  approve <video_id> | reject <video_id>
  rescore                       fold user signals into stats, demote flagged videos
  block "<creator name>"

Env: ABT_API (default http://localhost:8000; `jac start --dev` uses the API port it prints),
     ABT_ADMIN_KEY (required).
"""

import os;
import sys;
import json;
import requests;

glob API: str = os.environ.get("ABT_API", "http://localhost:8000").rstrip("/");
glob KEY: str = os.environ.get("ABT_ADMIN_KEY", "");

def _post(path: str, body: dict[str, object], timeout: int) -> object {
    payload = dict(body);
    payload["admin_key"] = KEY;
    resp = requests.post(API + path, json=payload, timeout=timeout);
    if resp.status_code >= 400 {
        raise RuntimeError("HTTP " + str(resp.status_code) + ": " + resp.text[:300]);
    }
    data = resp.json() as dict[str, object];
    inner = (data.get("data") or {}) as dict[str, object];
    if inner.get("error") {
        raise RuntimeError(str(inner["error"]));
    }
    if path.startswith("/walker/") {
        return inner.get("reports");
    }
    return inner.get("result");
}

def _fn(name: str, body: dict[str, object], timeout: int = 120) -> object {
    return _post("/function/" + name, body, timeout);
}

def _strip(x: object) -> object {
    if isinstance(x, dict) {
        return {k: _strip(v) for (k, v) in x.items() if not str(k).startswith("_jac")};
    }
    if isinstance(x, list) {
        return [_strip(v) for v in x];
    }
    return x;
}

def _show(x: object) {
    print(json.dumps(_strip(x), indent=2, ensure_ascii=False));
}

def _arg(args: list[str], i: int, fallback: str) -> str {
    return args[i] if len(args) > i else fallback;
}

def main(args: list[str]) -> int {
    if not KEY {
        print("Set ABT_ADMIN_KEY first.");
        return 2;
    }
    cmd = _arg(args, 0, "help");
    if cmd == "stats" {
        _show(_fn("admin_stats", {}));
    } elif cmd == "bootstrap" {
        _show(_fn("admin_bootstrap", {"with_seeds": "--no-seeds" not in args}));
    } elif cmd == "curate" {
        _show(_fn("admin_curate", {
            "max_per_channel": int(_arg(args, 1, "5")), "channel": _arg(args, 2, "")
        }, 900));
    } elif cmd == "plan" {
        _show(_post("/walker/PlanCatalog", {
            "target_live": int(_arg(args, 1, "20")), "max_new_per_topic": int(_arg(args, 2, "2"))
        }, 900));
    } elif cmd == "jobs" {
        rows = _fn("admin_list_jobs", {"status": _arg(args, 1, "")}) or [];
        for j in rows as list[dict[str, object]] {
            print(f"{j['status']:8} {j['kind']:9} {j['topic']:15} {str(j['subject'])[:50]:50} {str(j['result'])[:40]}");
        }
    } elif cmd == "run-jobs" {
        _show(_fn("admin_run_jobs", {"max_jobs": int(_arg(args, 1, "3"))}, 1800));
    } elif cmd == "generate" {
        if len(args) < 3 {
            print('usage: generate "<subject>" <topic>');
            return 2;
        }
        _show(_fn("admin_generate", {"subject": args[1], "topic": args[2]}, 600));
    } elif cmd == "review" {
        rows = _fn("admin_review_queue", {"status": _arg(args, 1, "review")}) or [];
        for r in rows as list[dict[str, object]] {
            print(f"{r['id']}  {float(str(r['quality'])):.2f}  {r['topic']:15} {str(r['creator_name'])[:18]:18} {str(r['title'])[:60]}");
        }
    } elif cmd == "approve" or cmd == "reject" {
        status = "live" if cmd == "approve" else "rejected";
        _show(_fn("admin_set_status", {"video_id": _arg(args, 1, ""), "status": status}));
    } elif cmd == "rescore" {
        _show(_fn("admin_rescore", {}));
    } elif cmd == "block" {
        _show(_fn("admin_block_creator", {"name": _arg(args, 1, ""), "blocked": True}));
    } else {
        print(__doc__ or "see tools/admin.jac");
        return 0 if cmd == "help" else 2;
    }
    return 0;
}

with entry:__main__ {
    argv = [a for a in sys.argv[1:] if not a.endswith("admin.jac")];
    try {
        code = main(argv);
    } except Exception as err {
        print("error:", str(err));
        code = 1;
    }
    sys.exit(code);
}
