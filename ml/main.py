"""
FastAPI service for the analytics that need fitting.

Split of responsibility:
  Postgres trigger  incremental BKT mastery update on every attempt (fast path)
  TypeScript        blame propagation, diagnosis counts (no fitting needed)
  this service      anything that has to be fitted from data

Run:
  uvicorn main:app --reload
  open http://localhost:8000/docs
"""

from __future__ import annotations

from fastapi import BackgroundTasks, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from db import fetch
from modules import attention, bkt, evaluate, features, forgetting, planner

app = FastAPI(title="Diagnostic ML service", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class Health(BaseModel):
    ok: bool
    database: str
    attempts: int
    students: int
    concepts: int
    mastery_rows: int
    plans: int


@app.get("/health", response_model=Health)
def health():
    try:
        c = fetch(
            """
            select
              (select count(*) from attempts)  as attempts,
              (select count(*) from profiles)  as students,
              (select count(*) from concepts)  as concepts,
              (select count(*) from mastery)   as mastery_rows,
              (select count(*) from study_plans where is_current) as plans
            """
        )[0]
    except Exception as e:
        raise HTTPException(503, f"Database unreachable: {e}")

    return Health(
        ok=True, database="connected",
        attempts=c["attempts"], students=c["students"], concepts=c["concepts"],
        mastery_rows=c["mastery_rows"], plans=c["plans"],
    )


@app.get("/features/summary")
def features_summary(student_id: str | None = None):
    return features.summary(features.attempts_frame(student_id))


@app.get("/features/focus-bins")
def focus_bins(student_id: str):
    bins = features.session_accuracy_bins(features.attempts_frame(student_id))
    if bins.empty:
        raise HTTPException(404, "No session-timed attempts for this student.")
    return bins.to_dict("records")


@app.get("/features/hourly")
def hourly(student_id: str):
    h = features.hourly_accuracy(features.attempts_frame(student_id))
    if h.empty:
        raise HTTPException(404, "No attempts for this student.")
    return h.to_dict("records")


# ----------------------------------------------------------------- pipeline

def _recompute(student_id: str | None) -> dict:
    """The full pipeline, in dependency order. bkt first: everything else
    reads the mastery rows it writes."""
    df = features.attempts_frame(student_id)
    if df.empty:
        return {"status": "no_attempts"}

    steps = {"mastery_rows": bkt.materialize(df)}

    fits = attention.fit_all(student_id)
    steps["attention_profiles"] = attention.write(fits) if not fits.empty else 0
    steps["hourly_rows"] = attention.write_hourly(student_id)

    reviews = forgetting.with_mastery(df)
    if not reviews.empty:
        pooled = forgetting.fit_pooled(reviews)
        sf = forgetting.fit_all_students(reviews, pooled)
        h = {r.student_id: r.half_life for r in sf.itertuples()
             if r.half_life is not None}
        obs, model, _ = forgetting.concept_adjustment(reviews, h)
        if not obs.empty:
            steps["half_life_rows"] = forgetting.write(
                forgetting.predict(obs, model))

    ids = [student_id] if student_id else [
        str(r["student_id"]) for r in fetch("select student_id from profiles")
    ]
    shared = planner.load_shared()
    planned = 0
    for sid in ids:
        if planner.plan_for(str(sid), False, shared)["status"] == "planned":
            planned += 1
    steps["plans"] = planned

    return {"status": "complete", **steps}


@app.post("/recompute/{student_id}")
def recompute_one(student_id: str):
    return _recompute(student_id)


@app.post("/recompute-all")
def recompute_all(background: BackgroundTasks):
    """Runs in the background: a full cohort takes minutes, which is longer
    than most HTTP clients will wait."""
    background.add_task(_recompute, None)
    return {"status": "started", "note": "check /health for updated counts"}


@app.get("/plan/{student_id}")
def get_plan(student_id: str):
    res = planner.plan_for(student_id, dry=True)
    if res["status"] != "planned":
        raise HTTPException(404, res.get("hint", res["status"]))
    return res


# ----------------------------------------------------------------- simulate

class SimulateRequest(BaseModel):
    student_id: str
    hours: dict[str, float]      # subject_id -> hours allocated


@app.post("/simulate")
def simulate(req: SimulateRequest):
    """Projected mastery under a hypothetical allocation.

    Gains saturate: the sixth hour on a subject already known is worth a
    fraction of the first hour on one that is not. Modelled as
    room * (1 - exp(-hours / ceiling)).
    """
    import numpy as np

    rows = fetch(
        """select c.subject_id, avg(m.mastery_prob) as mastery, count(*) as n
             from mastery m join concepts c on c.concept_id = m.concept_id
            where m.student_id = %s
            group by c.subject_id""",
        (req.student_id,),
    )
    if not rows:
        raise HTTPException(404, "No mastery rows for this student.")

    out, before, after = [], 0.0, 0.0
    for r in rows:
        sid = r["subject_id"]
        m = float(r["mastery"])
        hours = float(req.hours.get(sid, 0.0))
        ceiling = 4.0 + 8.0 * (1 - m)          # weaker subjects absorb more time
        projected = min(0.98, m + (1 - m) * (1 - np.exp(-hours / ceiling)))

        out.append(dict(
            subject_id=sid, concepts=r["n"],
            current=round(m, 3), projected=round(projected, 3),
            hours=hours, gain=round(projected - m, 3),
        ))
        before += m
        after += projected

    n = len(rows)
    return {
        "student_id": req.student_id,
        "subjects": out,
        "mean_before": round(before / n, 3),
        "mean_after": round(after / n, 3),
        "note": "Ignores forgetting before the exam and prerequisite unlocking, "
                "both of which the scheduler does account for.",
    }


# ----------------------------------------------------------------- evaluation

@app.get("/evaluate")
def evaluate_endpoint():
    """Ablation table, calibration and parameter recovery. Slow: it refits."""
    df = features.attempts_frame()
    if df.empty:
        raise HTTPException(404, "No attempts.")
    res = evaluate.run(df)
    if "error" in res:
        raise HTTPException(400, res["error"])
    return {**res, "recovery": evaluate.recovery()}