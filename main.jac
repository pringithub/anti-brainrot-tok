"""SmartTok - entry point: server endpoints + client app."""

import from services.feed {
    LoadFeed, list_topics, get_video, get_profile, save_onboarding, follow_topic, log_view,
    set_reaction, report_video, answer_quiz, list_saved
}
import from services.admin {
    admin_bootstrap, admin_curate, admin_generate, admin_review_queue, admin_set_status,
    admin_block_creator, admin_rescore, admin_stats, admin_list_jobs, admin_run_jobs
}
import from services.planner { PlanCatalog }

cl {
    import ".styles/global.css";
    import from "@jac/runtime" { Router, Routes, Route }
    import from .components.AppShell { AppShell }
    import from .components.Landing { Landing }

    def:pub app -> JsxElement {
        return <Router>
            <Routes>
                <Route path="/" element={<Landing/>} />
                <Route path="/app" element={<AppShell/>} />
            </Routes>
        </Router>;
    }
}
