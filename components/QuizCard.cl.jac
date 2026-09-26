"""Recall quiz card inserted into the feed for videos the user finished."""

sv import from ..services.catalog { QuizView }
sv import from ..services.feed { answer_quiz }

def:pub QuizCard(quiz: QuizView) -> JsxElement {
    has picked: int = -1,
        correct: bool = False;

    async def choose(choice: int) -> None {
        if picked >= 0 {
            return;
        }
        picked = choice;
        correct = choice == quiz.answer_idx;
        video_id = quiz.video_id;
        try {
            await answer_quiz(video_id, choice);
        } except Exception as e {
            console.warn("[quiz] answer failed", e);
        }
    }

    return <div className="quiz">
        <div className="quiz-kicker">Quick recall · from “{quiz.video_title}”</div>
        <h2>{quiz.question}</h2>
        <div className="quiz-choices">
            {for (i, c) in enumerate(quiz.choices) {
                <button
                    key={str(i)}
                    className={
                        "choice right" if picked >= 0 and i == quiz.answer_idx
                        else ("choice wrong" if i == picked else "choice")
                    }
                    onClick={lambda e: MouseEvent { choose(i); }}
                >{c}</button>
            }}
        </div>
        {picked >= 0 and <div className="quiz-result">
            <strong>{"Correct!" if correct else "Not quite."}</strong>
            {quiz.explanation and <p>{quiz.explanation}</p>}
            <p className="hint">Swipe up to keep going</p>
        </div>}
    </div>;
}
