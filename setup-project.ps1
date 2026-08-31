# ============================================================
# AI Personal Learning Assistant - project file writer
# Run from the PROJECT ROOT (the folder that contains web\)
# Overwrites existing files. Assumes Tailwind v4.
# ============================================================

$ErrorActionPreference = 'Stop'

if (-not (Test-Path 'web\package.json')) {
    Write-Host 'ERROR: run this from the project root, not from inside web\' -ForegroundColor Red
    exit 1
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-ProjectFile {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $full = Join-Path (Get-Location).Path $Path
    [System.IO.File]::WriteAllText($full, $Content, $utf8NoBom)
    Write-Host "  wrote $Path" -ForegroundColor DarkGray
}

Write-Host ''
Write-Host 'Writing project files...' -ForegroundColor Cyan

Write-ProjectFile 'ml\.env.example' @'
# Supabase -> Project Settings -> Database -> Connection string (URI)
# Use the SESSION POOLER string if direct connection is refused on your network.
DATABASE_URL=postgresql://postgres.PROJECT:PASSWORD@aws-0-REGION.pooler.supabase.com:5432/postgres
'@

Write-ProjectFile 'ml\README.md' @'
# ML service

## Setup

```bash
cd ml
python -m venv venv
venv\Scripts\activate          # Windows
source venv/bin/activate       # macOS / Linux
pip install -r requirements.txt
```

Copy `.env.example` to `.env` and paste your connection string from
**Supabase -> Project Settings -> Database -> Connection string (URI)**.

If a direct connection is refused (common on college networks and IPv4-only
hosts), use the **Session pooler** string instead.

## Generate a synthetic cohort

```bash
python synth.py --dry                        # summary, writes nothing
python synth.py --students 30 --days 21      # generate and insert
python synth.py --clean                      # remove the synthetic cohort
```

Ground truth lands in `ground_truth.json`. That file is the point: it records
the parameters the data was generated from, so the fitting code can be checked
against something known before it is trusted on real students.

## Inspect the features

```bash
python -m modules.features
```

## Run the API

```bash
uvicorn main:app --reload
```

Then open http://localhost:8000/docs

## Build order

## Pipeline order

Run in this order. Each step depends on the one before it.

```bash
python synth.py --students 30 --days 21   # generate a cohort (once)
python -m modules.bkt                     # materialize mastery  <- REQUIRED FIRST
python -m modules.attention --validate    # focus half-life
python -m modules.forgetting --validate   # retention half-life
python -m modules.planner --all           # weekly plans
python -m modules.evaluate                # ablation table and recovery
```

Or run the whole thing through the API:

```bash
uvicorn main:app --reload
curl -X POST http://localhost:8000/recompute-all
```

`modules.bkt` must run before the others. synth.py disables the incremental
Postgres trigger during load, so a synthetic cohort has no mastery rows until
the forward pass writes them. Anything reading `mastery` sees an empty table
until then, and fails quietly rather than loudly.

| Module | Status | Depends on |
|---|---|---|
| `synth.py` | done | content migrations |
| `modules/features.py` | done | db |
| `modules/bkt.py` | done | features |
| `modules/attention.py` | done | features |
| `modules/forgetting.py` | done | bkt, features |
| `modules/planner.py` | done | all of the above |
| `modules/evaluate.py` | done | ground_truth.json, all fits |
'@

Write-ProjectFile 'ml\db.py' @'
"""Shared database access. Everything else imports from here."""

import os
import psycopg
from psycopg.rows import dict_row
from dotenv import load_dotenv

load_dotenv()

DATABASE_URL = os.environ.get("DATABASE_URL")
if not DATABASE_URL:
    raise RuntimeError(
        "DATABASE_URL is not set. Copy .env.example to .env and fill it in "
        "from Supabase > Project Settings > Database."
    )


def connect():
    """A new connection. Callers use it as a context manager."""
    return psycopg.connect(DATABASE_URL, row_factory=dict_row)


def fetch(sql: str, params: tuple = ()) -> list[dict]:
    with connect() as conn, conn.cursor() as cur:
        cur.execute(sql, params)
        return cur.fetchall()


def execute(sql: str, params: tuple = ()) -> None:
    with connect() as conn, conn.cursor() as cur:
        cur.execute(sql, params)
        conn.commit()


def executemany(sql: str, rows: list[tuple]) -> None:
    if not rows:
        return
    with connect() as conn, conn.cursor() as cur:
        cur.executemany(sql, rows)
        conn.commit()
'@

Write-ProjectFile 'ml\main.py' @'
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
'@

Write-ProjectFile 'ml\modules\__init__.py' @'

'@

Write-ProjectFile 'ml\modules\attention.py' @'
"""
Attention model: per-student focus half-life.

Fits  accuracy(t) = baseline * exp(-t / tau)  where t is ACTIVE minutes into a
session. tau is the focus half-life: the timescale over which this student's
accuracy decays within a sitting.

Two independent channels are fitted and compared:
  accuracy channel   from attempts.minutes_into_session
  typing channel     from typing_windows (rhythm degradation)

If both channels give a similar tau, that is evidence the construct is real
rather than an artefact of one measurement. That agreement is worth reporting.

Deliberately NOT claimed: drowsiness, tiredness, or any internal state. What
is measured is deviation from the student's own early-session baseline.

Usage:
    python -m modules.attention              fit and write
    python -m modules.attention --dry        fit and print, write nothing
    python -m modules.attention --validate   check tau against ground truth
"""

from __future__ import annotations

import argparse
import json
import os

import numpy as np
import pandas as pd
from scipy.optimize import curve_fit

from db import executemany
from modules import features

# Below these, a fit is noise. Reporting a tau from three attempts would be
# worse than reporting nothing.
MIN_SESSIONS = 3
MIN_ATTEMPTS = 40
MIN_BINS = 4
BIN_MINUTES = 3.0

TAU_LO, TAU_HI = 5.0, 90.0
DEFAULT_BLOCK_MIN = 25


def _decay(t, floor, tau):
    """Relative accuracy decays toward a floor, not toward zero.

    Fitted on accuracy NORMALISED by the student's own early-session level, so
    the curve starts at 1.0 by construction and amplitude is not a free
    parameter. Three free parameters against seven noisy bins was
    underdetermined and drove tau to its upper bound; two is tractable.
    """
    return floor + (1.0 - floor) * np.exp(-t / tau)


def fit_tau(bins: pd.DataFrame) -> tuple[float | None, float | None, float | None]:
    """Returns (tau, baseline, r_squared). None when the fit is not usable."""
    if len(bins) < MIN_BINS:
        return None, None, None

    t = bins["bin"].to_numpy(dtype=float)
    # Difficulty-adjusted where available: raw accuracy cannot separate
    # "tired" from "the sampled items were harder".
    col = "accuracy_adj" if "accuracy_adj" in bins.columns else "accuracy"
    y = bins[col].to_numpy(dtype=float)
    w = bins["n"].to_numpy(dtype=float)

    # Normalise by the earliest bins: this student's own reference level.
    early = bins.nsmallest(2, "bin")
    base_level = float(np.average(early[col], weights=early["n"]))
    if base_level < 0.15:
        return None, None, None
    y = y / base_level

    try:
        popt, _ = curve_fit(
            _decay, t, y,
            p0=[0.6, 25.0],
            bounds=([0.0, TAU_LO], [0.95, TAU_HI]),
            sigma=1.0 / np.sqrt(w),
            maxfev=12000,
        )
    except Exception:
        return None, None, None

    floor, tau = float(popt[0]), float(popt[1])
    baseline = base_level
    pred = _decay(t, floor, tau)
    ss_res = float(np.sum(w * (y - pred) ** 2))
    ss_tot = float(np.sum(w * (y - np.average(y, weights=w)) ** 2))
    r2 = 1 - ss_res / ss_tot if ss_tot > 0 else None

    return tau, baseline, r2


def fit_typing_tau(tw: pd.DataFrame) -> float | None:
    """Second channel: typing rhythm degrades on the same curve.

    Uses burst length, which rises with focus, so it decays like accuracy does.
    """
    if tw.empty or len(tw) < 8:
        return None

    d = tw.dropna(subset=["minutes_into_session", "mean_burst_len"]).copy()
    if len(d) < 8:
        return None

    d["bin"] = (d["minutes_into_session"] // 5) * 5
    g = d.groupby("bin").agg(y=("mean_burst_len", "mean"), n=("mean_burst_len", "size"))
    g = g[g["n"] >= 2].reset_index()
    if len(g) < MIN_BINS:
        return None

    # Normalise so the curve shape, not the units, drives the fit.
    y = g["y"].to_numpy(dtype=float)
    y = y / max(y.max(), 1e-6)

    try:
        popt, _ = curve_fit(
            _decay, g["bin"].to_numpy(dtype=float), y,
            p0=[0.5, 25.0],
            bounds=([0.0, TAU_LO], [0.95, TAU_HI]),
            maxfev=12000,
        )
    except Exception:
        return None
    return float(popt[1])


def fatigue_slope(df: pd.DataFrame) -> float | None:
    """Response-time drift per active minute. Positive means slowing down."""
    d = df.dropna(subset=["minutes_into_session", "time_ratio"])
    if len(d) < 20:
        return None
    x = d["minutes_into_session"].to_numpy(dtype=float)
    y = d["time_ratio"].to_numpy(dtype=float)
    if x.std() < 1e-6:
        return None
    return float(np.polyfit(x, y, 1)[0])


def fit_all(student_id: str | None = None) -> pd.DataFrame:
    df = features.attempts_frame(student_id)
    if df.empty:
        return pd.DataFrame()

    sess = features.sessions_frame(student_id)
    tw = features.typing_frame(student_id)
    all_bins = features.session_accuracy_bins(df, bin_minutes=BIN_MINUTES)

    rows = []
    for sid, sdf in df.groupby("student_id"):
        n_sessions = int(sess[sess["student_id"] == sid].shape[0]) if not sess.empty else 0
        n_attempts = len(sdf)

        if n_sessions < MIN_SESSIONS or n_attempts < MIN_ATTEMPTS:
            rows.append(dict(
                student_id=sid, tau=None, baseline=None, r2=None,
                typing_tau=None, slope=None, block_min=DEFAULT_BLOCK_MIN,
                active_ratio=None, sessions=n_sessions, attempts=n_attempts,
                status="insufficient_data",
            ))
            continue

        bins = all_bins[all_bins["student_id"] == sid] if not all_bins.empty else pd.DataFrame()
        tau, baseline, r2 = fit_tau(bins)
        t_tau = fit_typing_tau(tw[tw["student_id"] == sid]) if not tw.empty else None

        ssub = sess[sess["student_id"] == sid] if not sess.empty else pd.DataFrame()
        active_ratio = None
        if not ssub.empty and ssub["planned_minutes"].notna().any():
            active_ratio = float(
                (ssub["active_minutes"] / ssub["planned_minutes"].clip(lower=1)).mean()
            )

        # A tau pinned at a bound is a failed fit wearing a number. Mark it
        # rather than trusting it; the cohort median is substituted below.
        at_bound = tau is not None and (tau >= TAU_HI * 0.98 or tau <= TAU_LO * 1.02)
        if at_bound:
            tau, r2 = None, None

        block = int(np.clip(round(tau), 15, 50)) if tau else DEFAULT_BLOCK_MIN

        rows.append(dict(
            student_id=sid, tau=tau, baseline=baseline, r2=r2,
            typing_tau=t_tau, slope=fatigue_slope(sdf),
            block_min=block, active_ratio=active_ratio,
            sessions=n_sessions, attempts=n_attempts,
            status="fitted" if tau else "fit_failed",
        ))

    fits = pd.DataFrame(rows)

    # Partial pooling: students whose own curve is not identifiable inherit the
    # cohort median rather than a hard-coded 25. Recorded as "pooled" so the
    # report can state how many students were individually fitted.
    good = fits[fits["status"] == "fitted"]
    if len(good) >= 3:
        median_tau = float(good["tau"].median())
        mask = fits["status"].isin(["fit_failed", "insufficient_data"])
        fits.loc[mask, "tau"] = median_tau
        fits.loc[mask, "block_min"] = int(np.clip(round(median_tau), 15, 50))
        fits.loc[mask, "status"] = "pooled"

    return fits


def write(fits: pd.DataFrame) -> int:
    usable = fits[fits["status"].isin(["fitted", "pooled"])]
    if usable.empty:
        return 0

    executemany(
        """
        insert into attention_profile
          (student_id, focus_half_life_min, baseline_accuracy, fatigue_slope,
           recommended_block_min, recommended_break_min, active_ratio,
           sample_sessions, updated_at)
        values (%s,%s,%s,%s,%s,%s,%s,%s, now())
        on conflict (student_id) do update set
          focus_half_life_min   = excluded.focus_half_life_min,
          baseline_accuracy     = excluded.baseline_accuracy,
          fatigue_slope         = excluded.fatigue_slope,
          recommended_block_min = excluded.recommended_block_min,
          active_ratio          = excluded.active_ratio,
          sample_sessions       = excluded.sample_sessions,
          updated_at            = now()
        """,
        [
            (
                r.student_id, round(r.tau, 2),
                round(r.baseline, 4) if r.baseline is not None else None,
                round(r.slope, 5) if r.slope is not None else None,
                int(r.block_min), 5,
                round(r.active_ratio, 3) if r.active_ratio is not None else None,
                int(r.sessions),
            )
            for r in usable.itertuples()
        ],
    )
    return len(usable)


def write_hourly(student_id: str | None = None) -> int:
    df = features.attempts_frame(student_id)
    h = features.hourly_accuracy(df)
    if h.empty:
        return 0
    h = h[h["n"] >= 5]
    if h.empty:
        return 0

    executemany(
        """
        insert into hourly_performance
          (student_id, hour_of_day, attempt_count, accuracy, mean_time_ratio)
        values (%s,%s,%s,%s,%s)
        on conflict (student_id, hour_of_day) do update set
          attempt_count   = excluded.attempt_count,
          accuracy        = excluded.accuracy,
          mean_time_ratio = excluded.mean_time_ratio
        """,
        [
            (r.student_id, int(r.hour), int(r.n),
             round(float(r.accuracy), 4), round(float(r.mean_time_ratio), 4))
            for r in h.itertuples()
        ],
    )
    return len(h)


def validate(fits: pd.DataFrame) -> dict:
    """Compare fitted tau against the value the synthetic data was generated
    from. This is the check that makes the whole pipeline defensible: if the
    fitter cannot recover a parameter we chose ourselves, it recovers nothing.
    """
    path = os.path.join(os.path.dirname(__file__), "..", "ground_truth.json")
    if not os.path.exists(path):
        return {"error": "ground_truth.json not found. Run synth.py first."}

    with open(path, encoding="utf-8") as f:
        truth = json.load(f)

    # psycopg returns uuid.UUID objects; ground truth holds strings.
    true_tau = {str(s["student_id"]): s["focus_tau_min"] for s in truth["students"]}
    fitted = fits[fits["status"] == "fitted"]

    pairs = [
        (true_tau[str(r.student_id)], r.tau)
        for r in fitted.itertuples()
        if str(r.student_id) in true_tau
    ]
    if len(pairs) < 3:
        return {"error": f"only {len(pairs)} synthetic students fitted"}

    t = np.array([p[0] for p in pairs])
    f_ = np.array([p[1] for p in pairs])
    err = f_ - t

    return {
        "n": len(pairs),
        "true_tau_mean": round(float(t.mean()), 2),
        "fitted_tau_mean": round(float(f_.mean()), 2),
        "bias": round(float(err.mean()), 2),
        "mae": round(float(np.abs(err).mean()), 2),
        "rmse": round(float(np.sqrt((err ** 2).mean())), 2),
        "correlation": round(float(np.corrcoef(t, f_)[0, 1]), 3),
        "within_20pct": round(float((np.abs(err) / t < 0.2).mean()), 3),
    }


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--student", type=str, default=None)
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--validate", action="store_true")
    a = ap.parse_args()

    fits = fit_all(a.student)
    if fits.empty:
        raise SystemExit("No attempts found.")

    print(fits["status"].value_counts().to_string(), "\n")

    ok = fits[fits["status"] == "fitted"]
    if not ok.empty:
        print("fitted focus half-life (minutes)")
        print(f"  median  {ok['tau'].median():.1f}")
        print(f"  range   {ok['tau'].min():.1f} - {ok['tau'].max():.1f}")
        print(f"  mean r2 {ok['r2'].dropna().mean():.3f}")

        both = ok.dropna(subset=["typing_tau"])
        if len(both) >= 3:
            corr = both["tau"].corr(both["typing_tau"])
            print(f"\ntwo-channel agreement (accuracy vs typing)")
            print(f"  correlation {corr:.3f} across {len(both)} students")

    if a.validate:
        print("\nparameter recovery against ground truth")
        print(json.dumps(validate(fits), indent=2))

    if not a.dry:
        n = write(fits)
        h = write_hourly(a.student)
        print(f"\nwrote {n} attention profiles, {h} hourly rows")
    else:
        print("\n--dry: nothing written")
'@

Write-ProjectFile 'ml\modules\bkt.py' @'
"""
Bayesian Knowledge Tracing forward pass.

Produces a mastery estimate for every attempt, using only the attempts that
came BEFORE it. Downstream modules need this: forgetting has to separate
"they never knew it" from "they knew it and forgot", and it cannot do that
from a running correct-rate, which conflates the two.

Confidence modulates the guess parameter, matching the Postgres trigger:
a hesitant correct answer earns less credit than a certain one.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

from db import executemany

P_INIT, P_TRANSIT, P_SLIP, P_GUESS = 0.15, 0.18, 0.09, 0.22


def forward(df: pd.DataFrame,
            p_init: float = P_INIT,
            p_transit: float = P_TRANSIT,
            p_slip: float = P_SLIP,
            p_guess: float = P_GUESS) -> pd.DataFrame:
    """Adds `bkt_prior` (mastery BEFORE this attempt) and `bkt_post` (after).

    Sorting by time within each (student, concept) is what makes `bkt_prior`
    a legitimate predictor rather than a leak.
    """
    d = df.sort_values(["student_id", "concept_id", "created_at"]).copy()

    priors = np.empty(len(d))
    posts = np.empty(len(d))

    i = 0
    for _, g in d.groupby(["student_id", "concept_id"], sort=False):
        m = p_init
        for _, row in g.iterrows():
            priors[i] = m

            guess = p_guess
            conf = row.get("confidence")
            if conf == 1:
                guess = min(0.60, p_guess * 2.0)
            elif conf == 3:
                guess = max(0.05, p_guess * 0.4)

            if row["is_correct"]:
                num = m * (1 - p_slip)
                den = num + (1 - m) * guess
            else:
                num = m * p_slip
                den = num + (1 - m) * (1 - guess)

            m_post = num / den if den > 0 else m
            m = min(0.99, max(0.01, m_post + (1 - m_post) * p_transit))

            posts[i] = m
            i += 1

    d["bkt_prior"] = priors
    d["bkt_post"] = posts
    return d


def log_likelihood(df: pd.DataFrame, p_init, p_transit, p_slip, p_guess) -> float:
    """Likelihood of the observed outcomes under these parameters. Used by the
    grid search in bkt_fit."""
    d = forward(df, p_init, p_transit, p_slip, p_guess)
    m = d["bkt_prior"].to_numpy()
    p_correct = m * (1 - p_slip) + (1 - m) * p_guess
    p_correct = np.clip(p_correct, 1e-6, 1 - 1e-6)
    y = d["is_correct"].astype(float).to_numpy()
    return float(np.sum(y * np.log(p_correct) + (1 - y) * np.log(1 - p_correct)))


def materialize(df: pd.DataFrame) -> int:
    """Write the final BKT state per (student, concept) into `mastery`.

    Needed because synth.py disables the incremental trigger during load, so
    synthetic students have no mastery rows at all. Anything reading `mastery`
    - the planner, the dashboard, forgetting's UPDATE statements - silently
    sees nothing until this runs.

    Real students get their rows from the Postgres trigger on every attempt.
    This is the offline equivalent, and it is also how a full recompute would
    rebuild mastery after refitting parameters.
    """
    if df.empty:
        return 0

    traced = forward(df)

    last = (
        traced.sort_values("created_at")
        .groupby(["student_id", "concept_id"])
        .agg(
            mastery=("bkt_post", "last"),
            n=("bkt_post", "size"),
            last_review_at=("created_at", "max"),
        )
        .reset_index()
    )

    rows = [
        (
            r.student_id,
            r.concept_id,
            round(float(r.mastery), 4),
            round(float(1.0 / np.sqrt(r.n + 1)), 4),   # shrinks with observations
            int(r.n),
            r.last_review_at,
        )
        for r in last.itertuples()
    ]

    executemany(
        """
        insert into mastery
          (student_id, concept_id, mastery_prob, uncertainty,
           observation_count, last_review_at, updated_at)
        values (%s, %s, %s, %s, %s, %s, now())
        on conflict (student_id, concept_id) do update set
          mastery_prob      = excluded.mastery_prob,
          uncertainty       = excluded.uncertainty,
          observation_count = excluded.observation_count,
          last_review_at    = excluded.last_review_at,
          updated_at        = now()
        """,
        rows,
    )
    return len(rows)


if __name__ == "__main__":
    import argparse
    from modules import features

    ap = argparse.ArgumentParser(description="Materialize BKT mastery estimates")
    ap.add_argument("--student", type=str, default=None)
    ap.add_argument("--dry", action="store_true")
    a = ap.parse_args()

    df = features.attempts_frame(a.student)
    if df.empty:
        raise SystemExit("No attempts found.")

    traced = forward(df)
    print(f"attempts        {len(traced)}")
    print(f"student concept {traced.groupby(['student_id','concept_id']).ngroups}")
    print(f"mean mastery    {traced['bkt_post'].mean():.3f}")
    print(f"range           {traced['bkt_post'].min():.3f} - {traced['bkt_post'].max():.3f}")

    if a.dry:
        print("\n--dry: nothing written")
    else:
        n = materialize(df)
        print(f"\nwrote {n} mastery rows")
'@

Write-ProjectFile 'ml\modules\evaluate.py' @'
"""
Evaluation and ablation.

Produces the numbers a results section needs, and — more importantly — the
ablation table that shows each component earns its place. A system that
performs identically with a component removed does not need that component,
and saying so is stronger than claiming everything helps.

Metrics
-------
next-answer AUC       can the model predict the next response correct/incorrect
                      on held-out attempts? The standard knowledge-tracing metric.
calibration           when the model says 0.7, is it right about 70% of the time?
root-cause precision  does blame propagation land on a concept the student is
                      actually weak at, rather than the one they failed?
parameter recovery    fitted vs generating values, from ground_truth.json

Ablations
---------
Each removes ONE mechanism and re-measures, holding everything else fixed:
  no_confidence     confidence stops modulating the guess rate
  no_error_typing   all wrong answers treated identically
  no_forgetting     mastery never decays
  no_prereq_blame   failures are not propagated down the graph

Usage:
    python -m modules.evaluate                  full run, prints tables
    python -m modules.evaluate --json out.json  also write machine-readable
"""

from __future__ import annotations

import argparse
import json
import os

import numpy as np
import pandas as pd
from sklearn.metrics import roc_auc_score

from db import fetch
from modules import bkt, features

HOLDOUT_FRACTION = 0.2
MIN_TEST_ATTEMPTS = 200


# ---------------------------------------------------------------- split

def chronological_split(df: pd.DataFrame, frac: float = HOLDOUT_FRACTION):
    """Last `frac` of each student's history is held out.

    A random split would leak: attempt 400 helps predict attempt 12 only
    because the model has already seen the student learn. Splitting on time
    is the only honest option for sequential data.
    """
    train_parts, test_parts = [], []
    for _, g in df.groupby("student_id"):
        g = g.sort_values("created_at")
        cut = int(len(g) * (1 - frac))
        if cut < 10 or len(g) - cut < 3:
            train_parts.append(g)
            continue
        train_parts.append(g.iloc[:cut])
        test_parts.append(g.iloc[cut:])

    train = pd.concat(train_parts) if train_parts else pd.DataFrame()
    test = pd.concat(test_parts) if test_parts else pd.DataFrame()
    return train, test


# ---------------------------------------------------------------- prediction

def predict_correct(train: pd.DataFrame, test: pd.DataFrame,
                    use_confidence: bool = True,
                    use_forgetting: bool = True,
                    half_lives: dict | None = None) -> np.ndarray:
    """P(correct) for each held-out attempt, from mastery carried forward.

    The mastery state is built from TRAIN only, then decayed to each test
    attempt's timestamp. Nothing from the test set feeds back in.
    """
    p_slip, p_guess = bkt.P_SLIP, bkt.P_GUESS

    traced = bkt.forward(train) if use_confidence else bkt.forward(
        train.assign(confidence=2)      # flatten confidence to neutral
    )

    state = (
        traced.sort_values("created_at")
        .groupby(["student_id", "concept_id"])
        .agg(mastery=("bkt_post", "last"), at=("created_at", "max"))
        .to_dict("index")
    )

    out = np.empty(len(test))
    for i, row in enumerate(test.itertuples()):
        key = (row.student_id, row.concept_id)
        entry = state.get(key)
        m = entry["mastery"] if entry else bkt.P_INIT

        if use_forgetting and entry is not None:
            h = (half_lives or {}).get(row.student_id, 5.0)
            days = (row.created_at - entry["at"]).total_seconds() / 86400
            m = m * (2.0 ** (-max(0.0, days) / max(0.5, h)))

        out[i] = np.clip(m * (1 - p_slip) + (1 - m) * p_guess, 1e-6, 1 - 1e-6)

    return out


def calibration(y: np.ndarray, p: np.ndarray, bins: int = 10) -> pd.DataFrame:
    """Predicted probability against observed frequency. Perfect calibration
    puts every row on the diagonal."""
    edges = np.linspace(0, 1, bins + 1)
    idx = np.clip(np.digitize(p, edges) - 1, 0, bins - 1)
    rows = []
    for b in range(bins):
        mask = idx == b
        if mask.sum() < 5:
            continue
        rows.append(dict(
            bin=f"{edges[b]:.1f}-{edges[b+1]:.1f}",
            n=int(mask.sum()),
            predicted=round(float(p[mask].mean()), 3),
            observed=round(float(y[mask].mean()), 3),
        ))
    return pd.DataFrame(rows)


def expected_calibration_error(y: np.ndarray, p: np.ndarray, bins: int = 10) -> float:
    cal = calibration(y, p, bins)
    if cal.empty:
        return float("nan")
    w = cal["n"] / cal["n"].sum()
    return float((w * (cal["predicted"] - cal["observed"]).abs()).sum())


# ---------------------------------------------------------------- root cause

def root_cause_precision(df: pd.DataFrame, use_prereq: bool = True) -> dict:
    """Does blame propagation point at a genuinely weak concept?

    With ground truth available, "correct" means the identified root has lower
    true mastery than the concept that visibly failed. Without propagation the
    root IS the failed concept, so the measure collapses to zero by
    construction — which is the point of the ablation.
    """
    path = os.path.join(os.path.dirname(__file__), "..", "ground_truth.json")
    if not os.path.exists(path):
        return {"error": "ground_truth.json not found"}

    with open(path, encoding="utf-8") as f:
        truth = json.load(f)
    final = {
        str(s["student_id"]): s["final_mastery"] for s in truth["students"]
    }

    edges = pd.DataFrame(fetch(
        "select parent_id, child_id, weight from prerequisites"))
    parents: dict[str, list[tuple[str, float]]] = {}
    for e in edges.itertuples():
        parents.setdefault(e.child_id, []).append((e.parent_id, float(e.weight)))

    traced = bkt.forward(df)
    est = (
        traced.sort_values("created_at")
        .groupby(["student_id", "concept_id"])["bkt_post"].last().to_dict()
    )

    hits, total, depths = 0, 0, []
    fails = df[~df["is_correct"]].groupby(["student_id", "concept_id"]).size()

    for (sid, cid), n in fails.items():
        key = str(sid)
        if key not in final or cid not in final[key] or n < 2:
            continue

        root, depth = cid, 0
        if use_prereq:
            current = cid
            for _ in range(4):
                ps = parents.get(current)
                if not ps:
                    break
                scored = [
                    (pid, w * (1 - est.get((sid, pid), 0.15)))
                    for pid, w in ps
                ]
                if not scored:
                    break
                top = max(scored, key=lambda x: x[1])[0]
                if est.get((sid, top), 0.15) >= 0.8:
                    break
                current, root, depth = top, top, depth + 1

        total += 1
        depths.append(depth)
        if root in final[key] and final[key][root] < final[key].get(cid, 1.0):
            hits += 1

    if total == 0:
        return {"error": "no evaluable failures"}

    return {
        "n_failures": total,
        "precision": round(hits / total, 3),
        "mean_depth": round(float(np.mean(depths)), 2),
    }


# ---------------------------------------------------------------- ablations

CONFIGS = [
    ("full",            dict(confidence=True,  forgetting=True,  prereq=True)),
    ("no_confidence",   dict(confidence=False, forgetting=True,  prereq=True)),
    ("no_forgetting",   dict(confidence=True,  forgetting=False, prereq=True)),
    ("no_prereq_blame", dict(confidence=True,  forgetting=True,  prereq=False)),
]


def run(df: pd.DataFrame) -> dict:
    train, test = chronological_split(df)
    if len(test) < MIN_TEST_ATTEMPTS:
        return {"error": f"only {len(test)} held-out attempts, need "
                         f"{MIN_TEST_ATTEMPTS}. Generate a longer cohort."}

    half_lives = {
        r["student_id"]: float(r["half_life_days"] or 5.0)
        for r in fetch(
            """select student_id, avg(half_life_days) as half_life_days
                 from mastery group by student_id"""
        )
    }

    y = test["is_correct"].astype(int).to_numpy()
    results, cal_full = [], None

    for name, cfg in CONFIGS:
        p = predict_correct(
            train, test,
            use_confidence=cfg["confidence"],
            use_forgetting=cfg["forgetting"],
            half_lives=half_lives,
        )
        auc = roc_auc_score(y, p) if len(np.unique(y)) > 1 else float("nan")
        ece = expected_calibration_error(y, p)
        rc = root_cause_precision(train, use_prereq=cfg["prereq"])

        if name == "full":
            cal_full = calibration(y, p)

        results.append(dict(
            config=name,
            auc=round(float(auc), 4),
            ece=round(float(ece), 4),
            root_cause_precision=rc.get("precision"),
            mean_blame_depth=rc.get("mean_depth"),
        ))

    table = pd.DataFrame(results)
    base = table[table["config"] == "full"].iloc[0]
    table["auc_delta"] = (table["auc"] - base["auc"]).round(4)

    return dict(
        train_attempts=len(train),
        test_attempts=len(test),
        students=int(df["student_id"].nunique()),
        base_rate=round(float(y.mean()), 4),
        ablation=table.to_dict("records"),
        calibration=cal_full.to_dict("records") if cal_full is not None else [],
    )


def recovery() -> dict:
    """Fitted parameters against the values the cohort was generated from."""
    path = os.path.join(os.path.dirname(__file__), "..", "ground_truth.json")
    if not os.path.exists(path):
        return {"error": "ground_truth.json not found"}
    with open(path, encoding="utf-8") as f:
        truth = json.load(f)

    true_tau = {str(s["student_id"]): s["focus_tau_min"] for s in truth["students"]}
    true_hl = {str(s["student_id"]): s["half_life_days"] for s in truth["students"]}

    fitted_tau = {
        str(r["student_id"]): float(r["focus_half_life_min"])
        for r in fetch(
            """select student_id, focus_half_life_min from attention_profile
                where focus_half_life_min is not null"""
        )
    }
    fitted_hl = {
        str(r["student_id"]): float(r["half_life_days"])
        for r in fetch(
            """select student_id, avg(half_life_days) as half_life_days
                 from mastery where half_life_days is not null
                group by student_id"""
        )
    }

    def compare(true_map, fit_map, label):
        pairs = [(true_map[k], fit_map[k]) for k in fit_map if k in true_map]
        if len(pairs) < 3:
            return {"parameter": label, "n": len(pairs), "note": "too few matched"}
        t = np.array([p[0] for p in pairs])
        f = np.array([p[1] for p in pairs])
        return {
            "parameter": label,
            "n": len(pairs),
            "true_mean": round(float(t.mean()), 2),
            "fitted_mean": round(float(f.mean()), 2),
            "bias": round(float((f - t).mean()), 2),
            "mae": round(float(np.abs(f - t).mean()), 2),
            "correlation": round(float(np.corrcoef(t, f)[0, 1]), 3),
        }

    return {
        "focus_half_life_min": compare(true_tau, fitted_tau, "focus half-life (min)"),
        "retention_half_life_days": compare(true_hl, fitted_hl, "retention half-life (days)"),
    }


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", type=str, default=None)
    a = ap.parse_args()

    df = features.attempts_frame()
    if df.empty:
        raise SystemExit("No attempts found.")

    print(f"attempts {len(df)}, students {df['student_id'].nunique()}\n")

    res = run(df)
    if "error" in res:
        raise SystemExit(res["error"])

    print(f"train {res['train_attempts']}  test {res['test_attempts']}  "
          f"base rate {res['base_rate']}\n")

    print("ABLATION")
    t = pd.DataFrame(res["ablation"])
    print(t.to_string(index=False))
    print("\nauc_delta is relative to the full system. A negative value means")
    print("removing that component made prediction worse, so it earns its place.\n")

    if res["calibration"]:
        print("CALIBRATION (full system)")
        print(pd.DataFrame(res["calibration"]).to_string(index=False))
        print()

    print("PARAMETER RECOVERY")
    rec = recovery()
    for v in rec.values():
        print(json.dumps(v))

    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump({**res, "recovery": rec}, f, indent=2)
        print(f"\nwrote {a.json}")
'@

Write-ProjectFile 'ml\modules\features.py' @'
"""
Feature builder. Everything downstream imports from here.

One rule: this module reads and reshapes. It fits nothing and writes nothing.
Keeping it inert means every other module can be tested against the same
frame without worrying about ordering or side effects.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

from db import fetch


def attempts_frame(student_id: str | None = None) -> pd.DataFrame:
    """One row per attempt, joined to the question, concept and chosen option.

    Columns added on top of the raw rows:
      time_ratio            time taken / question median
      attempt_index         0-based position in this student's history
      concept_attempt_index 0-based position within this concept
      days_since_last       gap since this student last saw this concept
      prior_correct_rate    running accuracy on this concept, excluding now
      is_rapid              answered in under 20% of the median time
      held_belief           the wrong option carried a tagged misconception
    """
    where = "where a.student_id = %s" if student_id else ""
    params = (student_id,) if student_id else ()

    rows = fetch(
        f"""
        select
            a.attempt_id, a.student_id, a.question_id, a.chosen_option_id,
            a.session_id, a.is_correct, a.confidence, a.time_taken_sec,
            a.minutes_into_session, a.error_type, a.created_at,
            q.primary_concept_id as concept_id,
            q.difficulty, q.median_time_sec,
            c.subject_id, c.level as concept_level,
            o.misconception_id
        from attempts a
        join questions q on q.question_id = a.question_id
        join concepts  c on c.concept_id  = q.primary_concept_id
        left join options o on o.option_id = a.chosen_option_id
        {where}
        order by a.student_id, a.created_at
        """,
        params,
    )

    df = pd.DataFrame(rows)
    if df.empty:
        return df

    df["created_at"] = pd.to_datetime(df["created_at"], utc=True)
    for col in ("difficulty", "median_time_sec", "time_taken_sec", "minutes_into_session"):
        df[col] = pd.to_numeric(df[col], errors="coerce")

    df["time_ratio"] = df["time_taken_sec"] / df["median_time_sec"].clip(lower=1)
    df["is_rapid"] = df["time_ratio"] < 0.2
    df["held_belief"] = (~df["is_correct"]) & df["misconception_id"].notna()

    df["attempt_index"] = df.groupby("student_id").cumcount()
    df["concept_attempt_index"] = df.groupby(["student_id", "concept_id"]).cumcount()

    gap = df.groupby(["student_id", "concept_id"])["created_at"].diff()
    df["days_since_last"] = gap.dt.total_seconds() / 86400

    # Running accuracy on this concept BEFORE the current attempt. Shifting is
    # what keeps the current outcome out of its own feature.
    grp = df.groupby(["student_id", "concept_id"])["is_correct"]
    df["prior_correct_rate"] = (
        grp.apply(lambda s: s.shift().expanding().mean()).reset_index(level=[0, 1], drop=True)
    )

    return df


def sessions_frame(student_id: str | None = None) -> pd.DataFrame:
    """Sessions with a tracked active_minutes. Untracked sessions are dropped:
    a null there means the student had tracking off, not that it was zero."""
    where = "where student_id = %s and active_minutes is not null" if student_id \
        else "where active_minutes is not null"
    params = (student_id,) if student_id else ()

    df = pd.DataFrame(
        fetch(
            f"""
            select session_id, student_id, started_at, ended_at, planned_minutes,
                   active_minutes, blur_count, idle_seconds, baseline_accuracy,
                   end_reason
            from study_sessions {where} order by student_id, started_at
            """,
            params,
        )
    )
    if df.empty:
        return df
    df["started_at"] = pd.to_datetime(df["started_at"], utc=True)
    df["active_minutes"] = pd.to_numeric(df["active_minutes"], errors="coerce")
    return df


def typing_frame(student_id: str | None = None) -> pd.DataFrame:
    where = "where student_id = %s" if student_id else ""
    params = (student_id,) if student_id else ()

    df = pd.DataFrame(
        fetch(
            f"""
            select window_id, session_id, student_id, minutes_into_session,
                   chars_typed, mean_iki_ms, sd_iki_ms, backspace_rate,
                   pauses_over_2s, pauses_thinking, pauses_lost,
                   mean_burst_len, run_attempts, run_failures, created_at
            from typing_windows {where} order by student_id, created_at
            """,
            params,
        )
    )
    if df.empty:
        return df
    for c in ("minutes_into_session", "mean_iki_ms", "sd_iki_ms",
              "backspace_rate", "mean_burst_len"):
        df[c] = pd.to_numeric(df[c], errors="coerce")
    return df


def concept_graph() -> tuple[pd.DataFrame, pd.DataFrame]:
    concepts = pd.DataFrame(
        fetch("select concept_id, subject_id, name, level from concepts")
    )
    edges = pd.DataFrame(
        fetch("select parent_id, child_id, weight from prerequisites")
    )
    if not edges.empty:
        edges["weight"] = pd.to_numeric(edges["weight"], errors="coerce")
    return concepts, edges


def session_accuracy_bins(df: pd.DataFrame, bin_minutes: float = 5.0,
                          adjust_difficulty: bool = True) -> pd.DataFrame:
    """Accuracy against minutes into session, binned, optionally adjusted for
    how hard the sampled items were.

    Raw accuracy conflates two things: the student tiring, and the questions
    happening to get harder. When practice is targeted at weak concepts the
    difficulty is roughly constant and raw accuracy is fine. Once sampling
    mixes weak, mid and strong concepts, an easy item at minute 5 and a hard
    one at minute 30 look identical to fatigue, and the fit collapses.

    `accuracy_adj` divides observed accuracy by the accuracy BKT expects given
    the mastery the student brought to those items, so what remains is the
    part attributable to time in the session.
    """
    if df.empty or df["minutes_into_session"].isna().all():
        return pd.DataFrame()

    d = df.dropna(subset=["minutes_into_session"]).copy()
    d["bin"] = (d["minutes_into_session"] // bin_minutes) * bin_minutes

    if adjust_difficulty:
        from modules import bkt
        traced = bkt.forward(d)
        m = traced["bkt_prior"].to_numpy()
        traced["expected"] = m * (1 - bkt.P_SLIP) + (1 - m) * bkt.P_GUESS
        d = traced

    agg = {
        "accuracy": ("is_correct", "mean"),
        "n": ("is_correct", "size"),
        "mean_time_ratio": ("time_ratio", "mean"),
    }
    if adjust_difficulty:
        agg["expected"] = ("expected", "mean")

    out = d.groupby(["student_id", "bin"]).agg(**agg).reset_index()

    if adjust_difficulty:
        out["accuracy_adj"] = out["accuracy"] / out["expected"].clip(lower=0.05)
    else:
        out["accuracy_adj"] = out["accuracy"]

    # Bins with almost nothing in them add noise to the curve fit.
    return out[out["n"] >= 3]


def hourly_accuracy(df: pd.DataFrame, tz_offset_hours: int = 5.5) -> pd.DataFrame:
    """Accuracy by local hour of day. Default offset is IST."""
    if df.empty:
        return pd.DataFrame()
    d = df.copy()
    local = d["created_at"] + pd.Timedelta(hours=tz_offset_hours)
    d["hour"] = local.dt.hour
    return (
        d.groupby(["student_id", "hour"])
        .agg(
            accuracy=("is_correct", "mean"),
            n=("is_correct", "size"),
            mean_time_ratio=("time_ratio", "mean"),
        )
        .reset_index()
    )


def summary(df: pd.DataFrame) -> dict:
    if df.empty:
        return {"attempts": 0}
    return {
        "attempts": len(df),
        "students": df["student_id"].nunique(),
        "concepts": df["concept_id"].nunique(),
        "accuracy": round(float(df["is_correct"].mean()), 3),
        "median_attempts_per_concept": int(
            df.groupby(["student_id", "concept_id"]).size().median()
        ),
        "confidently_wrong": int(((~df["is_correct"]) & (df["confidence"] == 3)).sum()),
        "misconception_hits": int(df["held_belief"].sum()),
        "rapid_responses": int(df["is_rapid"].sum()),
        "with_session_timing": int(df["minutes_into_session"].notna().sum()),
    }


if __name__ == "__main__":
    import json

    df = attempts_frame()
    print(json.dumps(summary(df), indent=2))
    if not df.empty:
        print("\nfocus bins (head):")
        print(session_accuracy_bins(df).head(10).to_string(index=False))
'@

Write-ProjectFile 'ml\modules\forgetting.py' @'
"""
Forgetting model: per-student retention half-life, plus per-concept adjustment.

Retention decays as  R(d) = 2 ** (-d / half_life)  where d is days since the
concept was last practised. Effective mastery is  mastery_prob * R(d).

METHOD, and why it changed
--------------------------
The obvious approach is to derive a point estimate per pair,
    h = -gap / log2(accuracy)
then regress h on features. That leaks: gap and accuracy appear on both sides,
so the model rediscovers its own arithmetic and reports an r-squared near 0.93
while predicting nothing. It failed validation against ground truth, which is
what validation is for.

What is done instead: fit half-life per student by MAXIMUM LIKELIHOOD over
observed review outcomes. Each review is a Bernoulli trial whose success
probability is a decay function of the gap. Nothing derived from the outcome
is used as a predictor.

    P(correct | gap) = guess + (1 - guess) * m * 2 ** (-gap / h)

A separate ridge then predicts per-concept DEVIATION from the student's own
half-life, using only features known before the review: how often the concept
has been practised, its difficulty, its depth in the graph, and how many named
misconceptions have been seen on it.

Usage:
    python -m modules.forgetting              fit and write
    python -m modules.forgetting --dry        print, write nothing
    python -m modules.forgetting --validate   check against ground truth
"""

from __future__ import annotations

import argparse
import json
import os

import numpy as np
import pandas as pd
from scipy.optimize import minimize, minimize_scalar
from sklearn.linear_model import Ridge
from sklearn.model_selection import cross_val_score

from db import executemany
from modules import bkt, features

MIN_REVIEWS_PER_STUDENT = 20
EARLY_SESSION_MIN = 12.0   # attention is near baseline before this point
MIN_ROWS_FOR_RIDGE = 60
HALF_LIFE_LO, HALF_LIFE_HI = 0.5, 45.0
DEFAULT_HALF_LIFE = 5.0
GUESS_RATE = 0.25          # 4-option MCQ floor

# Only features knowable BEFORE the review. Nothing derived from its outcome.
FEATURES = [
    "practice_count",
    "prior_misconceptions",
    "difficulty",
    "concept_level",
]


def review_rows(df: pd.DataFrame) -> pd.DataFrame:
    """One row per review: an attempt on a concept seen before, after a real gap.

    Restricted to EARLY in the session. Within-session attention decay also
    depresses accuracy, and the retention likelihood has nowhere to put that
    term, so it gets attributed to forgetting and biases the half-life down.
    Fitting only where attention is near its own baseline removes the confound
    at the cost of some data.
    """
    d = df.dropna(subset=["days_since_last"]).copy()
    d = d[d["days_since_last"] > 0.02]        # same-session repeats are not reviews

    if "minutes_into_session" in d.columns:
        early = d["minutes_into_session"].isna() | (
            d["minutes_into_session"] <= EARLY_SESSION_MIN
        )
        # Only apply the filter if enough survives to fit on.
        if int(early.sum()) >= MIN_REVIEWS_PER_STUDENT * 3:
            d = d[early]

    if d.empty:
        return d

    d["was_misconception"] = (d["error_type"] == "misconception").astype(int)
    grp = d.groupby(["student_id", "concept_id"])
    d["prior_misconceptions"] = (
        grp["was_misconception"].apply(lambda s: s.shift().expanding().sum())
        .reset_index(level=[0, 1], drop=True).fillna(0)
    )
    d["practice_count"] = d["concept_attempt_index"].astype(float)
    return d


def with_mastery(df: pd.DataFrame) -> pd.DataFrame:
    """Attach a BKT mastery estimate to every attempt, then keep the reviews.

    The forward pass runs over the FULL history, not just reviews, so the
    estimate entering each review reflects everything practised before it.
    A running correct-rate cannot do this: it conflates never-learned with
    learned-then-forgotten, which is precisely the distinction being fitted.
    """
    traced = bkt.forward(df)
    d = review_rows(traced)
    if d.empty:
        return d
    d["prior_mastery"] = d["bkt_prior"].clip(0.05, 0.98)
    return d


def _neg_log_likelihood(params, gaps: np.ndarray, correct: np.ndarray,
                        mastery: np.ndarray) -> float:
    """Two free parameters: half-life and a constant attenuation.

    Observed accuracy sits below what mastery alone predicts, because of
    residual attention decay, item difficulty, and belief-driven wrong
    answers. None of those are in this model. With only h free, the optimiser
    can lower the curve's LEVEL solely by shrinking h, which produced a
    fourfold underestimate against ground truth.

    Letting `attenuation` absorb the level leaves h identified by the SHAPE of
    the decay across gaps, which is the thing actually being asked.
    """
    h, attenuation = params
    retention = np.power(2.0, -gaps / max(h, 1e-3))
    p = GUESS_RATE + (1 - GUESS_RATE) * attenuation * mastery * retention
    p = np.clip(p, 1e-6, 1 - 1e-6)
    return -float(np.sum(correct * np.log(p) + (1 - correct) * np.log(1 - p)))


def _optimise(gaps, correct, mastery):
    """Returns (half_life, attenuation) or (None, None)."""
    best = None
    # A few starts: the surface is not guaranteed convex in two dimensions.
    for h0 in (2.0, 6.0, 15.0):
        res = minimize(
            _neg_log_likelihood,
            x0=[h0, 0.8],
            args=(gaps, correct, mastery),
            bounds=[(HALF_LIFE_LO, HALF_LIFE_HI), (0.25, 1.0)],
            method="L-BFGS-B",
        )
        if res.success and (best is None or res.fun < best.fun):
            best = res
    if best is None:
        return None, None
    return float(best.x[0]), float(best.x[1])


def fit_student_half_life(d: pd.DataFrame) -> float | None:
    """Maximum likelihood over this student's review outcomes."""
    if len(d) < MIN_REVIEWS_PER_STUDENT:
        return None

    gaps = d["days_since_last"].to_numpy(dtype=float)
    correct = d["is_correct"].astype(float).to_numpy()
    mastery = d["prior_mastery"].to_numpy(dtype=float)

    # Half-life is only identifiable if the gaps actually vary.
    if float(np.std(gaps)) < 0.4:
        return None

    h, _att = _optimise(gaps, correct, mastery)
    if h is None:
        return None
    # Sitting on a bound means the likelihood was flat, not that the student
    # forgets in twelve hours.
    if h <= HALF_LIFE_LO * 1.05 or h >= HALF_LIFE_HI * 0.98:
        return None
    return h


def fit_pooled(d: pd.DataFrame) -> float | None:
    """One half-life for the whole cohort. Far better identified than any
    individual fit, and the honest fallback when per-student recovery is
    unreliable at this data volume."""
    if len(d) < 200:
        return None
    h, att = _optimise(
        d["days_since_last"].to_numpy(dtype=float),
        d["is_correct"].astype(float).to_numpy(),
        d["prior_mastery"].to_numpy(dtype=float),
    )
    if h is not None:
        print(f"  pooled attenuation {att:.2f} "
              f"(absorbs attention, difficulty, belief effects)")
    return h


def fit_all_students(d: pd.DataFrame, pooled: float | None = None) -> pd.DataFrame:
    """Per-student fits, falling back to the pooled value where the individual
    likelihood is flat or the student has too few reviews.

    This is partial pooling in its simplest form: use the individual estimate
    when the data supports one, otherwise use the cohort. The status column
    records which, so the report can state how many students were pooled.
    """
    rows = []
    for sid, g in d.groupby("student_id"):
        h = fit_student_half_life(g)
        if h is None and pooled is not None:
            rows.append(dict(student_id=sid, half_life=pooled,
                             reviews=len(g), status="pooled"))
        else:
            rows.append(dict(
                student_id=sid, half_life=h, reviews=len(g),
                status="fitted" if h else "no_estimate",
            ))
    return pd.DataFrame(rows)


def concept_adjustment(d: pd.DataFrame, student_h: dict):
    """Ridge on the log RATIO between a concept's apparent half-life and the
    student's own. Predictors are pre-review features only."""
    rows = []
    for (sid, cid), g in d.groupby(["student_id", "concept_id"]):
        base = student_h.get(sid)
        if base is None or len(g) < 2:
            continue

        gaps = g["days_since_last"].to_numpy(dtype=float)
        correct = g["is_correct"].astype(float).to_numpy()
        mastery = g["prior_mastery"].to_numpy(dtype=float)

        if float(np.std(gaps)) < 0.3:
            continue
        h_c, _ = _optimise(gaps, correct, mastery)
        if h_c is None:
            continue

        rows.append(dict(
            student_id=sid,
            concept_id=cid,
            base_half_life=base,
            concept_half_life=h_c,
            log_ratio=float(np.log(max(h_c, 1e-3) / base)),
            practice_count=float(g["practice_count"].max()),
            prior_misconceptions=float(g["prior_misconceptions"].max()),
            difficulty=float(g["difficulty"].mean()),
            concept_level=float(g["concept_level"].mean()),
            reviews=len(g),
        ))

    obs = pd.DataFrame(rows)
    if len(obs) < MIN_ROWS_FOR_RIDGE:
        return obs, None, None

    X = obs[FEATURES].to_numpy(dtype=float)
    y = obs["log_ratio"].to_numpy(dtype=float)

    model = Ridge(alpha=1.0)
    cv = cross_val_score(model, X, y, cv=min(5, len(obs) // 12), scoring="r2")
    cv_r2 = float(np.mean(cv))

    # A negative cross-validated r-squared means the model predicts worse than
    # the mean. Applying it would add noise, so it is discarded and the
    # student-level half-life is used unchanged. Reported, not hidden.
    if cv_r2 <= 0.02:
        return obs, None, cv_r2

    model.fit(X, y)
    return obs, model, cv_r2


def predict(obs: pd.DataFrame, model) -> pd.DataFrame:
    obs = obs.copy()
    if model is None:
        obs["predicted_half_life"] = obs["base_half_life"]
        return obs
    adj = model.predict(obs[FEATURES].to_numpy(dtype=float))
    # Cap the adjustment: a concept should not be predicted to decay ten times
    # faster than the student does in general.
    adj = np.clip(adj, -0.7, 0.7)
    obs["predicted_half_life"] = np.clip(
        obs["base_half_life"] * np.exp(adj), HALF_LIFE_LO, HALF_LIFE_HI
    )
    return obs


def write(pred: pd.DataFrame) -> int:
    """Updates existing mastery rows. If none exist - which is the case for a
    synthetic cohort until `python -m modules.bkt` has run - this matches
    nothing, so the caller is told to check rather than trusting the count."""
    rows = []
    for r in pred.itertuples():
        h = float(r.predicted_half_life)
        days_to_075 = h * np.log2(1 / 0.75)   # 2^(-d/h) = 0.75
        rows.append((round(h, 3), round(float(days_to_075), 3),
                     r.student_id, r.concept_id))

    executemany(
        """
        update mastery
           set half_life_days = %s,
               next_review_at = coalesce(last_review_at, now())
                                + (%s || ' days')::interval,
               updated_at = now()
         where student_id = %s and concept_id = %s
        """,
        rows,
    )
    return len(rows)


def validate(student_fits: pd.DataFrame) -> dict:
    path = os.path.join(os.path.dirname(__file__), "..", "ground_truth.json")
    if not os.path.exists(path):
        return {"error": "ground_truth.json not found. Run synth.py first."}

    with open(path, encoding="utf-8") as f:
        truth = json.load(f)
    # psycopg returns uuid.UUID; ground truth holds strings.
    true_h = {str(s["student_id"]): s["half_life_days"] for s in truth["students"]}

    ok = student_fits[student_fits["status"] == "fitted"]
    pairs = [
        (true_h[str(r.student_id)], r.half_life)
        for r in ok.itertuples()
        if str(r.student_id) in true_h
    ]
    # Only individually fitted students are validated: pooled students all
    # carry the same value, so including them would inflate the correlation.
    if len(pairs) < 3:
        return {"error": f"only {len(pairs)} synthetic students matched"}

    t = np.array([p[0] for p in pairs])
    f_ = np.array([p[1] for p in pairs])
    err = f_ - t

    return {
        "n": len(pairs),
        "true_mean": round(float(t.mean()), 2),
        "fitted_mean": round(float(f_.mean()), 2),
        "bias": round(float(err.mean()), 2),
        "mae": round(float(np.abs(err).mean()), 2),
        "rmse": round(float(np.sqrt((err ** 2).mean())), 2),
        "correlation": round(float(np.corrcoef(t, f_)[0, 1]), 3),
        "within_30pct": round(float((np.abs(err) / t < 0.3).mean()), 3),
    }


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--student", type=str, default=None)
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--validate", action="store_true")
    a = ap.parse_args()

    df = features.attempts_frame(a.student)
    if df.empty:
        raise SystemExit("No attempts found.")

    d = with_mastery(df)
    print(f"review attempts   {len(d)}")
    if d.empty:
        raise SystemExit("No multi-day reviews. Run synth.py --days 35.")

    pooled = fit_pooled(d)
    print(f"pooled half-life  {pooled:.2f} days" if pooled else "pooled fit failed")

    student_fits = fit_all_students(d, pooled)
    print(student_fits["status"].value_counts().to_string())

    ok = student_fits[student_fits["half_life"].notna()]
    if ok.empty:
        raise SystemExit("\nNo student had enough reviews. Try synth.py --days 35.")

    print(f"\nper-student half-life (days)")
    print(f"  median {ok['half_life'].median():.2f}")
    print(f"  range  {ok['half_life'].min():.2f} - {ok['half_life'].max():.2f}")

    student_h = {r.student_id: r.half_life for r in ok.itertuples()}
    obs, model, cv_r2 = concept_adjustment(d, student_h)
    print(f"\nstudent x concept rows {len(obs)}")

    if model is not None:
        print(f"cross-validated r2     {cv_r2:.3f} on log ratio")
        print("coefficients (pre-review features only)")
        for name, coef in zip(FEATURES, model.coef_):
            print(f"  {name:22s} {coef:+.4f}")
    elif cv_r2 is not None:
        print(f"cross-validated r2     {cv_r2:.3f} - does not beat the mean, "
              "so the concept adjustment is discarded")
        print("using the student-level half-life unchanged")
    else:
        print("not enough rows for the concept adjustment; using the student "
              "half-life unchanged")

    pred = predict(obs, model)
    if not pred.empty:
        print(f"\npredicted half-life (days)")
        print(f"  median {pred['predicted_half_life'].median():.2f}")
        print(f"  range  {pred['predicted_half_life'].min():.2f} - "
              f"{pred['predicted_half_life'].max():.2f}")

    if a.validate:
        print("\nrecovery against ground truth")
        print(json.dumps(validate(student_fits), indent=2))

    if not a.dry and not pred.empty:
        n = write(pred)
        print(f"\nattempted {n} mastery updates with half_life_days and next_review_at")
        print("(UPDATE only touches existing rows - run "
              "`python -m modules.bkt` first if mastery is empty)")
    elif a.dry:
        print("\n--dry: nothing written")
'@

Write-ProjectFile 'ml\modules\planner.py' @'
"""
Planner: turns mastery, forgetting, attention and the concept graph into a
week of study blocks.

Priority per concept:

    priority = (1 - effective_mastery)      how much room there is to gain
             * blame_share                  how much downstream failure it explains
             * exam_weight                  how much the target exam tests it
             * urgency                      how close it is to being forgotten
             * readiness                    whether its prerequisites are met

Then a greedy knapsack over the student's weekly minutes, with three
constraints the schedule must respect:

  block length   capped at the fitted focus half-life, not a fixed 45 minutes
  DAG order      nothing is scheduled before its unmet prerequisites
  circadian      new material in high-accuracy hours, review in low ones

Usage:
    python -m modules.planner --student <uuid>
    python -m modules.planner --student <uuid> --dry
    python -m modules.planner --all
"""

from __future__ import annotations

import argparse
import json
import uuid as uuidlib
from datetime import date, timedelta

import numpy as np
import pandas as pd

from db import connect, execute, executemany, fetch

DEFAULT_BLOCK_MIN = 25
DEFAULT_HALF_LIFE = 5.0
MASTERED = 0.80              # above this a concept only needs review
READY = 0.60                 # prerequisite must reach this to unblock a child
HORIZON_DAYS = 7
BLAME_DEPTH = 4


def load_shared() -> dict:
    """Content that is the same for every student. Fetched once, not per student.

    Reloading the concept graph inside a 31-student loop meant 31 identical
    round trips to a pooler in another region, which is most of why --all
    appeared to hang.
    """
    return dict(
        concepts=pd.DataFrame(fetch(
            "select concept_id, name, subject_id, level from concepts")),
        edges=pd.DataFrame(fetch(
            "select parent_id, child_id, weight from prerequisites")),
    )


def load(student_id: str, shared: dict | None = None) -> dict:
    """Per-student data. All six queries run over ONE connection: opening a
    new one per query means a fresh TLS handshake each time."""
    if shared is None:
        shared = load_shared()

    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            """select m.concept_id, m.mastery_prob, m.uncertainty, m.half_life_days,
                      m.last_review_at, m.observation_count,
                      c.name, c.subject_id, c.level
                 from mastery m join concepts c on c.concept_id = m.concept_id
                where m.student_id = %s""",
            (student_id,),
        )
        mastery = pd.DataFrame(cur.fetchall())

        cur.execute(
            """select focus_half_life_min, recommended_block_min,
                      recommended_break_min
                 from attention_profile where student_id = %s""",
            (student_id,),
        )
        attention = cur.fetchall()

        cur.execute(
            """select hour_of_day, accuracy, attempt_count
                 from hourly_performance
                where student_id = %s and attempt_count >= 5""",
            (student_id,),
        )
        hourly = pd.DataFrame(cur.fetchall())

        cur.execute(
            "select weekly_minutes, target_exam_id from profiles where student_id = %s",
            (student_id,),
        )
        profile = cur.fetchall()

        cur.execute(
            """select q.primary_concept_id as concept_id, count(*) as failures
                 from attempts a join questions q on q.question_id = a.question_id
                where a.student_id = %s and not a.is_correct
                group by 1""",
            (student_id,),
        )
        failures = pd.DataFrame(cur.fetchall())

        exam_id = profile[0]["target_exam_id"] if profile else None
        weights = pd.DataFrame()
        if exam_id:
            cur.execute(
                "select concept_id, weight from exam_topic_weights where exam_id = %s",
                (exam_id,),
            )
            weights = pd.DataFrame(cur.fetchall())

    return dict(
        mastery=mastery,
        concepts=shared["concepts"],
        edges=shared["edges"],
        attention=attention[0] if attention else None,
        hourly=hourly,
        weekly_minutes=profile[0]["weekly_minutes"] if profile else 300,
        exam_id=exam_id, exam_weights=weights, failures=failures,
    )


def effective_mastery(row) -> float:
    """Mastery decayed to today: m * 2^(-days_elapsed / half_life)."""
    m = float(row["mastery_prob"])
    if pd.isna(row.get("last_review_at")):
        return m
    h = float(row.get("half_life_days") or DEFAULT_HALF_LIFE)
    days = (pd.Timestamp.now(tz="UTC") - pd.Timestamp(row["last_review_at"])).days
    return float(np.clip(m * (2.0 ** (-max(0, days) / max(0.5, h))), 0.01, 0.99))


def blame_shares(data: dict, eff: dict) -> dict:
    """Distribute each concept's failures down the prerequisite graph.

    Same rule as the TypeScript implementation the dashboard uses:
    blame = edge weight * (1 - mastery) * uncertainty, normalised per level.
    Recomputed here so the planner does not depend on the web app.
    """
    if data["edges"].empty or data["failures"].empty:
        return {}

    parents: dict[str, list[tuple[str, float]]] = {}
    for e in data["edges"].itertuples():
        parents.setdefault(e.child_id, []).append((e.parent_id, float(e.weight)))

    unc = {
        r["concept_id"]: float(r.get("uncertainty") or 1.0)
        for _, r in data["mastery"].iterrows()
    }

    shares: dict[str, float] = {}
    for f in data["failures"].itertuples():
        current, credit = f.concept_id, float(f.failures)
        shares[current] = shares.get(current, 0.0) + credit

        for _ in range(BLAME_DEPTH):
            ps = parents.get(current)
            if not ps:
                break
            scored = [
                (pid, w * (1 - eff.get(pid, 0.15)) * unc.get(pid, 1.0))
                for pid, w in ps
            ]
            total = sum(s for _, s in scored)
            if total <= 0:
                break
            top_id, top_raw = max(scored, key=lambda x: x[1])
            credit *= top_raw / total
            shares[top_id] = shares.get(top_id, 0.0) + credit
            if eff.get(top_id, 0.15) >= MASTERED:
                break
            current = top_id

    peak = max(shares.values()) if shares else 1.0
    return {k: v / peak for k, v in shares.items()}


def readiness(cid: str, edges: pd.DataFrame, eff: dict) -> float:
    """1.0 when every prerequisite is met, falling toward 0 as they are not."""
    ps = edges[edges["child_id"] == cid] if not edges.empty else pd.DataFrame()
    if ps.empty:
        return 1.0
    total_w = float(ps["weight"].sum()) or 1.0
    met = sum(
        float(r.weight) * min(1.0, eff.get(r.parent_id, 0.15) / READY)
        for r in ps.itertuples()
    )
    return float(np.clip(met / total_w, 0.05, 1.0))


def score(data: dict) -> pd.DataFrame:
    if data["mastery"].empty:
        return pd.DataFrame()

    m = data["mastery"].copy()
    m["effective"] = m.apply(effective_mastery, axis=1)
    eff = dict(zip(m["concept_id"], m["effective"]))

    shares = blame_shares(data, eff)
    weights = (
        dict(zip(data["exam_weights"]["concept_id"], data["exam_weights"]["weight"]))
        if not data["exam_weights"].empty else {}
    )

    rows = []
    now = pd.Timestamp.now(tz="UTC")
    for r in m.itertuples():
        e = float(getattr(r, "effective"))

        # Urgency rises as retention approaches the 0.75 review threshold.
        urgency = 1.0
        if not pd.isna(getattr(r, "last_review_at", pd.NaT)):
            h = float(getattr(r, "half_life_days") or DEFAULT_HALF_LIFE)
            days = (now - pd.Timestamp(r.last_review_at)).days
            retention = 2.0 ** (-max(0, days) / max(0.5, h))
            urgency = float(np.clip(1.4 - retention, 0.25, 1.4))

        ready = readiness(r.concept_id, data["edges"], eff)
        blame = 0.15 + shares.get(r.concept_id, 0.0)
        weight = float(weights.get(r.concept_id, 1.0))

        # Classification keys on RAW mastery, not decayed mastery.
        #
        # A concept learned to 0.90 that has decayed to 0.09 is a review, not
        # new material: the student has met it, they have forgotten it, and a
        # short refresher restores it far faster than teaching it again. Keying
        # on the decayed value called that "NEW" and allocated a full block to
        # re-teaching something already known.
        raw = float(r.mastery_prob)
        if e >= MASTERED:
            kind = "FRESH"                       # known and not yet decaying
        elif raw >= MASTERED:
            kind = "REVIEW"                      # known, decayed, needs a refresh
        elif ready >= 0.75:
            kind = "NEW"
        else:
            kind = "BLOCKED"

        priority = (1 - e) * blame * weight * urgency * ready

        rows.append(dict(
            concept_id=r.concept_id, name=r.name, subject_id=r.subject_id,
            level=int(r.level), mastery=float(r.mastery_prob), effective=e,
            blame=blame, urgency=urgency, readiness=ready,
            exam_weight=weight, kind=kind, priority=priority,
        ))

    return pd.DataFrame(rows).sort_values("priority", ascending=False)


def best_hours(hourly: pd.DataFrame) -> tuple[int, int]:
    """(hour for new material, hour for review). Falls back to 9 and 21."""
    if hourly.empty or len(hourly) < 3:
        return 9, 21
    h = hourly.sort_values("accuracy", ascending=False)
    return int(h.iloc[0]["hour_of_day"]), int(h.iloc[-1]["hour_of_day"])


def build(data: dict, scored: pd.DataFrame) -> list[dict]:
    if scored.empty:
        return []

    block_min = DEFAULT_BLOCK_MIN
    if data["attention"] and data["attention"].get("recommended_block_min"):
        block_min = int(data["attention"]["recommended_block_min"])

    budget = int(data["weekly_minutes"])
    new_hour, review_hour = best_hours(data["hourly"])

    # BLOCKED is dropped rather than deferred: the prerequisites are already
    # in the queue and will surface ahead of it.
    # FRESH is dropped too: retention is still high, so a block spent there
    # buys nothing. It reappears once decay makes it a REVIEW.
    queue = scored[~scored["kind"].isin(["BLOCKED", "FRESH"])].copy()

    items, spent, day, index_in_day = [], 0, 0, 0
    review_len = max(10, block_min // 2)

    # Interleave: a day of nothing but new material front-loads all the
    # hardest work, and reviews are cheap enough to slot alongside.
    for r in queue.itertuples():
        length = review_len if r.kind == "REVIEW" else block_min
        if spent + length > budget:
            break

        # Hardest and newest material first in the day, while attention is high.
        position = "early" if index_in_day == 0 else (
            "middle" if index_in_day == 1 else "late")

        items.append(dict(
            concept_id=r.concept_id,
            name=r.name,
            scheduled_for=date.today() + timedelta(days=day),
            block_index=index_in_day,
            minutes=length,
            position=position,
            hour=new_hour if r.kind == "NEW" else review_hour,
            kind=r.kind,
            priority=round(float(r.priority), 4),
            reason=dict(
                effective_mastery=round(float(r.effective), 3),
                raw_mastery=round(float(r.mastery), 3),
                blame_share=round(float(r.blame), 3),
                urgency=round(float(r.urgency), 3),
                readiness=round(float(r.readiness), 3),
                exam_weight=round(float(r.exam_weight), 2),
                block_minutes_from=(
                    "fitted focus half-life"
                    if data["attention"] else "default (no attention profile)"
                ),
            ),
        ))

        spent += length
        index_in_day += 1
        if index_in_day >= 3:
            index_in_day = 0
            day = (day + 1) % HORIZON_DAYS

    return items


def write(student_id: str, items: list[dict]) -> str | None:
    if not items:
        return None

    plan_id = str(uuidlib.uuid4())

    # All three statements on one connection and one commit: three separate
    # round trips per student adds up fast across a cohort.
    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            "update study_plans set is_current = false where student_id = %s",
            (student_id,),
        )
        cur.execute(
            """insert into study_plans (plan_id, student_id, horizon_days, is_current)
               values (%s, %s, %s, true)""",
            (plan_id, student_id, HORIZON_DAYS),
        )
        cur.executemany(
            """insert into plan_items
                 (plan_id, concept_id, scheduled_for, block_index,
                  allocated_minutes, position_in_block, priority_score, reason)
               values (%s,%s,%s,%s,%s,%s,%s,%s)""",
            [
                (plan_id, i["concept_id"], i["scheduled_for"], i["block_index"],
                 i["minutes"], i["position"], i["priority"], json.dumps(i["reason"]))
                for i in items
            ],
        )
        conn.commit()

    return plan_id


def plan_for(student_id: str, dry: bool = False, shared: dict | None = None) -> dict:
    data = load(student_id, shared)
    scored = score(data)
    if scored.empty:
        return {
            "student_id": student_id,
            "status": "no_mastery_rows",
            "hint": "Run: python -m modules.bkt   to materialize mastery first.",
        }

    items = build(data, scored)
    plan_id = None if dry else write(student_id, items)

    return {
        "student_id": student_id,
        "status": "planned",
        "plan_id": plan_id,
        "blocks": len(items),
        "minutes": sum(i["minutes"] for i in items),
        "budget": data["weekly_minutes"],
        "block_length": (
            data["attention"]["recommended_block_min"]
            if data["attention"] else DEFAULT_BLOCK_MIN
        ),
        "items": items,
    }


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--student", type=str)
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--dry", action="store_true")
    a = ap.parse_args()

    if a.all:
        ids = [r["student_id"] for r in fetch("select student_id from profiles")]
    elif a.student:
        ids = [a.student]
    else:
        raise SystemExit("Pass --student <uuid> or --all")

    shared = load_shared()
    print(f"loaded {len(shared['concepts'])} concepts, "
          f"{len(shared['edges'])} edges (once)\n")

    total = 0
    for n, sid in enumerate(ids, 1):
        if len(ids) > 1:
            print(f"  [{n}/{len(ids)}] {sid}", flush=True)
        res = plan_for(str(sid), a.dry, shared)
        if res["status"] != "planned":
            if len(ids) == 1:
                print(res.get("hint", res["status"]))
            continue
        total += 1

        if len(ids) == 1:
            print(f"budget {res['budget']} min, block length {res['block_length']} min")
            counts = {}
            for i in res["items"]:
                counts[i["kind"]] = counts.get(i["kind"], 0) + 1
            split = ", ".join(f"{v} {k.lower()}" for k, v in sorted(counts.items()))
            print(f"scheduled {res['blocks']} blocks, {res['minutes']} minutes"
                  f"{' (' + split + ')' if split else ''}\n")
            for i in res["items"][:12]:
                print(f"  {i['scheduled_for']}  {i['hour']:02d}:00  "
                      f"{i['kind']:7s} {i['minutes']:3d}m  {i['name'][:34]:34s} "
                      f"p={i['priority']:.4f}")
            if res["items"]:
                print("\nwhy the top block:")
                print(json.dumps(res["items"][0]["reason"], indent=2))

    print(f"\n{'would plan' if a.dry else 'planned'} for {total} students")
'@

Write-ProjectFile 'ml\requirements.txt' @'
fastapi==0.115.6
uvicorn[standard]==0.34.0
psycopg[binary]==3.2.3
pandas==2.2.3
numpy==2.2.1
scikit-learn==1.6.0
scipy==1.15.0
networkx==3.4.2
python-dotenv==1.0.1
'@

Write-ProjectFile 'ml\synth.py' @'
"""
Synthetic cohort generator.

The point is NOT to fabricate plausible-looking data. It is to produce data
whose GENERATING PARAMETERS ARE KNOWN, so the fitting code in modules/ can be
checked against ground truth before it ever touches real students.

If bkt_fit cannot recover parameters from a cohort we generated ourselves,
it will not recover anything from 30 classmates either.

What is simulated
-----------------
  ability          per student, latent, drives learning rate
  true mastery     per (student, concept), evolves via a BKT forward model
  prerequisites    a concept is hard to learn while its parents are weak
  misconceptions   a student can HOLD a belief; while held, the matching
                   distractor is chosen preferentially and with high confidence
  forgetting       exponential decay with a per-student half-life
  attention        accuracy decays within a session with half-life tau
  typing           window metrics degrade in step with the focus curve

Ground truth is written to ml/ground_truth.json for the evaluation step.

Usage
-----
  python synth.py --students 30 --days 21          generate and insert
  python synth.py --students 30 --days 21 --dry    print summary only
  python synth.py --clean                          remove synthetic rows
"""

from __future__ import annotations

import argparse
import json
import math
import random
import uuid
from dataclasses import dataclass, field, asdict
from datetime import datetime, timedelta, timezone

from db import fetch, execute, executemany

# Synthetic students are tagged so --clean never touches a real account.
SYNTH_COHORT = "synthetic-v1"
SYNTH_DOMAIN = "synthetic.local"

# profiles.student_id references auth.users(id), so a synthetic student needs a
# row there first. Inserting into auth.users fires the handle_new_user trigger,
# which creates the matching profiles row for us.
AUTH_INSERT = """
insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data
) values (
    '00000000-0000-0000-0000-000000000000', %s::uuid, 'authenticated', 'authenticated',
    %s::text, 'synthetic-no-login', now(), now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('display_name', %s::text)
)
on conflict (id) do nothing
"""

# BKT ground truth. bkt_fit should recover something close to these.
TRUE_P_TRANSIT = 0.18   # chance of learning on any practice opportunity
TRUE_P_SLIP = 0.09      # knows it, answers wrong
TRUE_P_GUESS = 0.22     # does not know it, answers right

SESSION_LEN_CHOICES = [15, 22, 30, 45]


@dataclass
class Student:
    student_id: str
    name: str
    ability: float           # -1 weak .. +1 strong
    half_life_days: float    # forgetting
    focus_tau_min: float     # attention half-life
    baseline_accuracy: float
    diligence: float         # how often they actually study
    typing_speed_ms: float   # baseline inter-key interval
    true_mastery: dict = field(default_factory=dict)
    held_beliefs: set = field(default_factory=set)


def load_content():
    concepts = fetch("select concept_id, subject_id, name, level from concepts")
    prereqs = fetch("select parent_id, child_id, weight from prerequisites")
    questions = fetch(
        """
        select q.question_id, q.primary_concept_id, q.difficulty, q.median_time_sec
          from questions q where q.is_active
        """
    )
    options = fetch(
        "select option_id, question_id, is_correct, misconception_id from options"
    )
    if not concepts or not questions:
        raise SystemExit(
            "No content found. Run migrations 002 and 004 in the Supabase SQL editor first."
        )

    by_q: dict[str, list[dict]] = {}
    for o in options:
        by_q.setdefault(str(o["question_id"]), []).append(o)

    return concepts, prereqs, questions, by_q


def make_students(n: int, concepts: list[dict], rng: random.Random) -> list[Student]:
    students = []
    for i in range(n):
        ability = rng.gauss(0, 0.5)
        s = Student(
            student_id=str(uuid.uuid4()),
            name=f"synth-{i:03d}",
            ability=max(-1.2, min(1.2, ability)),
            half_life_days=max(1.5, rng.gauss(6.0 + ability * 2.0, 1.5)),
            focus_tau_min=max(8.0, rng.gauss(24 + ability * 6, 7)),
            baseline_accuracy=min(0.95, max(0.4, 0.62 + ability * 0.15)),
            diligence=min(0.95, max(0.25, rng.gauss(0.6, 0.18))),
            typing_speed_ms=max(90, rng.gauss(190 - ability * 30, 40)),
        )
        # Starting mastery correlates with ability and is lower for deep concepts.
        for c in concepts:
            base = 0.35 + s.ability * 0.2 - c["level"] * 0.05
            s.true_mastery[c["concept_id"]] = min(0.9, max(0.02, rng.gauss(base, 0.12)))
        students.append(s)
    return students


def seed_beliefs(students, questions, options_by_q, rng):
    """Give each student a handful of held misconceptions to start with."""
    all_misc = sorted(
        {
            o["misconception_id"]
            for opts in options_by_q.values()
            for o in opts
            if o["misconception_id"]
        }
    )
    for s in students:
        k = rng.randint(2, 6)
        s.held_beliefs = set(rng.sample(all_misc, min(k, len(all_misc))))


def prereq_readiness(student: Student, concept_id: str, parents: dict) -> float:
    """Learning is throttled while prerequisites are weak. This is the signal
    blame propagation is supposed to detect, so it must be in the data."""
    ps = parents.get(concept_id, [])
    if not ps:
        return 1.0
    total_w = sum(w for _, w in ps) or 1.0
    weighted = sum(student.true_mastery.get(p, 0.15) * w for p, w in ps) / total_w
    return 0.35 + 0.65 * weighted


def decayed(mastery: float, days: float, half_life: float) -> float:
    return mastery * (2 ** (-days / max(0.5, half_life)))


def answer(
    student: Student,
    question: dict,
    opts: list[dict],
    minutes_in: float,
    rng: random.Random,
):
    """Simulate one attempt. Returns (option, is_correct, confidence, seconds, err)."""
    cid = question["primary_concept_id"]
    m = student.true_mastery.get(cid, 0.15)

    # Attention: accuracy decays within the session.
    focus = math.exp(-minutes_in / student.focus_tau_min)
    effective = m * (0.55 + 0.45 * focus)

    # Difficulty shifts the effective mastery.
    effective = max(0.02, min(0.98, effective - float(question["difficulty"]) * 0.09))

    correct_opt = next((o for o in opts if o["is_correct"]), None)
    wrong_opts = [o for o in opts if not o["is_correct"]]
    if correct_opt is None or not wrong_opts:
        return None

    # A held belief pulls the student toward the matching distractor.
    belief_opts = [
        o for o in wrong_opts
        if o["misconception_id"] and o["misconception_id"] in student.held_beliefs
    ]
    belief_pull = 0.55 if belief_opts else 0.0

    knows = rng.random() < effective
    if knows:
        is_correct = rng.random() > TRUE_P_SLIP
    else:
        if belief_opts and rng.random() < belief_pull:
            is_correct = False
        else:
            is_correct = rng.random() < TRUE_P_GUESS

    if is_correct:
        chosen = correct_opt
    elif belief_opts and rng.random() < belief_pull:
        chosen = rng.choice(belief_opts)
    else:
        chosen = rng.choice(wrong_opts)

    # Confidence: high when they know it, and high when a belief is driving
    # the wrong answer. That pairing is exactly what "confidently wrong" means.
    if knows:
        confidence = rng.choices([1, 2, 3], weights=[0.1, 0.3, 0.6])[0]
    elif chosen.get("misconception_id") in student.held_beliefs:
        confidence = rng.choices([1, 2, 3], weights=[0.1, 0.25, 0.65])[0]
    else:
        confidence = rng.choices([1, 2, 3], weights=[0.5, 0.35, 0.15])[0]

    median = float(question["median_time_sec"])
    ratio = rng.lognormvariate(math.log(1.0 / (0.7 + focus * 0.5)), 0.35)
    seconds = max(3.0, median * ratio)

    # Rapid guessing appears late in a session.
    if focus < 0.45 and rng.random() < 0.22:
        seconds = median * rng.uniform(0.06, 0.18)

    if seconds / median < 0.2:
        err = "guess" if is_correct else "careless"
    elif is_correct:
        err = "mastered" if confidence == 3 else "uncertain_correct"
    elif chosen.get("misconception_id"):
        err = "misconception"
    else:
        err = "procedural_slip"

    return chosen, is_correct, confidence, seconds, err


def update_mastery(student: Student, cid: str, is_correct: bool, parents: dict, rng):
    """BKT forward step, throttled by prerequisite readiness."""
    m = student.true_mastery.get(cid, 0.15)
    if is_correct:
        post = (m * (1 - TRUE_P_SLIP)) / (
            m * (1 - TRUE_P_SLIP) + (1 - m) * TRUE_P_GUESS
        )
    else:
        post = (m * TRUE_P_SLIP) / (m * TRUE_P_SLIP + (1 - m) * (1 - TRUE_P_GUESS))

    readiness = prereq_readiness(student, cid, parents)
    learn = TRUE_P_TRANSIT * readiness * (0.7 + 0.3 * (student.ability + 1) / 2)
    student.true_mastery[cid] = min(0.98, max(0.01, post + (1 - post) * learn))


def typing_window(student: Student, minutes_in: float, rng: random.Random) -> dict:
    """Window metrics that degrade with the same focus curve as accuracy."""
    focus = math.exp(-minutes_in / student.focus_tau_min)
    mean_iki = student.typing_speed_ms * (1 + (1 - focus) * 0.75)
    sd_iki = mean_iki * (0.45 + (1 - focus) * 0.9)
    backspace = 0.04 + (1 - focus) * 0.11
    burst = max(3.0, 18 * focus + rng.gauss(0, 2))
    pauses = int(max(0, rng.gauss(2 + (1 - focus) * 5, 1.5)))
    lost = int(pauses * (1 - focus) * rng.uniform(0.3, 0.8))
    return dict(
        chars=int(max(40, rng.gauss(420 * (0.5 + focus), 80))),
        mean_iki=round(mean_iki, 1),
        sd_iki=round(sd_iki, 1),
        backspace=round(backspace, 4),
        burst=round(burst, 1),
        pauses=pauses,
        thinking=max(0, pauses - lost),
        lost=lost,
        longest=int(2000 + (1 - focus) * 9000),
    )


def generate(n_students: int, days: int, seed: int, dry: bool):
    rng = random.Random(seed)
    concepts, prereqs, questions, options_by_q = load_content()

    parents: dict[str, list[tuple[str, float]]] = {}
    for e in prereqs:
        parents.setdefault(e["child_id"], []).append(
            (e["parent_id"], float(e["weight"]))
        )

    q_by_concept: dict[str, list[dict]] = {}
    for q in questions:
        q_by_concept.setdefault(q["primary_concept_id"], []).append(q)

    students = make_students(n_students, concepts, rng)
    seed_beliefs(students, questions, options_by_q, rng)

    initial = {s.student_id: dict(s.true_mastery) for s in students}

    profiles, sessions, attempts, twindows = [], [], [], []
    start = datetime.now(timezone.utc) - timedelta(days=days)

    for s in students:
        profiles.append(
            (
                s.student_id,
                s.name,
                SYNTH_COHORT,
                int(rng.choice([180, 240, 300, 420])),
                True,
            )
        )

        last_seen: dict[str, datetime] = {}

        for day in range(days):
            if rng.random() > s.diligence:
                continue

            day_start = start + timedelta(
                days=day, hours=rng.choice([9, 10, 14, 20, 21]), minutes=rng.randint(0, 50)
            )
            planned = rng.choice(SESSION_LEN_CHOICES)
            session_id = str(uuid.uuid4())
            minutes_in = 0.0
            n_correct_early = correct_early = 0

            # Concept selection: mostly weak, but not exclusively.
            #
            # Sampling ONLY the weakest concepts compresses the range of true
            # mastery at any moment, and a model cannot predict variance that
            # is not there. The first version of this generator did exactly
            # that and produced a next-answer AUC of 0.52, indistinguishable
            # from chance, which looked like a model failure but was a
            # sampling artefact.
            #
            # Real study mixes targeted practice with review and mock tests, so
            # 65% weak, 20% mid-range, 15% uniform reproduces that spread.
            ranked = sorted(s.true_mastery.items(), key=lambda kv: kv[1])
            weak = [c for c, _ in ranked[: max(6, len(concepts) // 4)]
                    if c in q_by_concept]
            midrange = [c for c, _ in ranked[len(ranked) // 3: 2 * len(ranked) // 3]
                        if c in q_by_concept]
            everything = [c for c in s.true_mastery if c in q_by_concept]
            if not weak and not everything:
                continue

            blur_count = 0
            idle_seconds = 0
            next_typing_at = 2.0

            while minutes_in < planned:
                roll = rng.random()
                if roll < 0.65 and weak:
                    cid = rng.choice(weak)
                elif roll < 0.85 and midrange:
                    cid = rng.choice(midrange)
                else:
                    cid = rng.choice(everything)
                q = rng.choice(q_by_concept[cid])
                opts = options_by_q.get(str(q["question_id"]), [])
                if len(opts) < 2:
                    continue

                # Forgetting since this concept was last practised.
                if cid in last_seen:
                    gap = (day_start - last_seen[cid]).total_seconds() / 86400
                    s.true_mastery[cid] = max(
                        0.02, decayed(s.true_mastery[cid], gap, s.half_life_days)
                    )

                res = answer(s, q, opts, minutes_in, rng)
                if res is None:
                    continue
                chosen, is_correct, confidence, seconds, err = res

                ts = day_start + timedelta(minutes=minutes_in)
                attempts.append(
                    (
                        str(uuid.uuid4()), s.student_id, str(q["question_id"]),
                        str(chosen["option_id"]), session_id, is_correct, confidence,
                        int(round(seconds)), round(minutes_in, 2), err, ts,
                    )
                )

                if minutes_in <= 5:
                    n_correct_early += 1
                    correct_early += 1 if is_correct else 0

                update_mastery(s, cid, is_correct, parents, rng)
                last_seen[cid] = ts

                # A held belief can be corrected after repeated exposure.
                belief_id = chosen.get("misconception_id")
                if belief_id and belief_id in s.held_beliefs and rng.random() < 0.12:
                    s.held_beliefs.discard(belief_id)

                minutes_in += seconds / 60 + rng.uniform(0.05, 0.4)

                if rng.random() < 0.09:
                    blur_count += 1
                    idle_seconds += int(rng.uniform(20, 180))

                if minutes_in >= next_typing_at:
                    w = typing_window(s, minutes_in, rng)
                    twindows.append(
                        (
                            session_id, s.student_id, round(minutes_in, 2), 120,
                            w["chars"], w["mean_iki"], w["sd_iki"], w["backspace"],
                            w["pauses"], w["longest"], w["burst"],
                            w["thinking"], w["lost"], 0, 0,
                            day_start + timedelta(minutes=minutes_in),
                        )
                    )
                    next_typing_at = minutes_in + 2.0

            baseline = (correct_early / n_correct_early) if n_correct_early else None
            sessions.append(
                (
                    session_id, s.student_id, None, day_start,
                    day_start + timedelta(minutes=minutes_in), planned,
                    round(minutes_in, 2), blur_count, idle_seconds, baseline,
                    "fatigue_cutoff" if minutes_in < planned * 0.7 else "completed",
                )
            )

    truth = {
        "cohort": SYNTH_COHORT,
        "seed": seed,
        "bkt": {
            "p_transit": TRUE_P_TRANSIT,
            "p_slip": TRUE_P_SLIP,
            "p_guess": TRUE_P_GUESS,
        },
        "students": [
            {
                "student_id": s.student_id,
                "name": s.name,
                "ability": round(s.ability, 3),
                "half_life_days": round(s.half_life_days, 2),
                "focus_tau_min": round(s.focus_tau_min, 2),
                "baseline_accuracy": round(s.baseline_accuracy, 3),
                "typing_speed_ms": round(s.typing_speed_ms, 1),
                "initial_mastery": {k: round(v, 4) for k, v in initial[s.student_id].items()},
                "final_mastery": {k: round(v, 4) for k, v in s.true_mastery.items()},
                "remaining_beliefs": sorted(s.held_beliefs),
            }
            for s in students
        ],
    }

    print(f"students        {len(students)}")
    print(f"sessions        {len(sessions)}")
    print(f"attempts        {len(attempts)}")
    print(f"typing windows  {len(twindows)}")
    print(f"mean attempts/student  {len(attempts)/max(1,len(students)):.1f}")

    if dry:
        print("\n--dry: nothing written")
        return

    insert(profiles, sessions, attempts, twindows)

    with open("ground_truth.json", "w", encoding="utf-8") as f:
        json.dump(truth, f, indent=2)
    print("\nground truth -> ml/ground_truth.json")


def insert(profiles, sessions, attempts, twindows):
    """Write directly to Postgres.

    Order matters: auth.users first (the handle_new_user trigger creates the
    profiles row), then profile fields, then the rest.

    The BKT trigger on `attempts` is disabled for the load. These rows already
    carry their own generating process, and we want mastery fitted offline
    rather than trigger-updated row by row.
    """
    print("\nwriting...")

    auth_rows = [
        (sid, f"{name}@{SYNTH_DOMAIN}", name)
        for sid, name, _cohort, _mins, _track in profiles
    ]
    executemany(AUTH_INSERT, auth_rows)
    print(f"  auth users      {len(auth_rows)}")

    # The trigger created profiles rows with just the display name.
    executemany(
        """update profiles
              set cohort = %s, weekly_minutes = %s, tracking_opt_in = %s
            where student_id = %s""",
        [(cohort, mins, track, sid) for sid, _n, cohort, mins, track in profiles],
    )
    print(f"  profiles        {len(profiles)}")

    execute("alter table attempts disable trigger trg_apply_bkt")
    try:
        executemany(
            """insert into study_sessions
                 (session_id, student_id, subject_id, started_at, ended_at,
                  planned_minutes, active_minutes, blur_count, idle_seconds,
                  baseline_accuracy, end_reason)
               values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
               on conflict (session_id) do nothing""",
            sessions,
        )
        print(f"  sessions        {len(sessions)}")

        executemany(
            """insert into attempts
                 (attempt_id, student_id, question_id, chosen_option_id, session_id,
                  is_correct, confidence, time_taken_sec, minutes_into_session,
                  error_type, created_at)
               values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
               on conflict (attempt_id) do nothing""",
            attempts,
        )
        print(f"  attempts        {len(attempts)}")

        executemany(
            """insert into typing_windows
                 (session_id, student_id, minutes_into_session, window_seconds,
                  chars_typed, mean_iki_ms, sd_iki_ms, backspace_rate,
                  pauses_over_2s, longest_pause_ms, mean_burst_len,
                  pauses_thinking, pauses_lost, run_attempts, run_failures, created_at)
               values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
            twindows,
        )
        print(f"  typing windows  {len(twindows)}")
    finally:
        execute("alter table attempts enable trigger trg_apply_bkt")

    print("done")


def clean():
    """Delete the synthetic cohort. Removing auth.users cascades to profiles,
    and profiles cascades to attempts, sessions, mastery and typing windows.
    Matching on the synthetic email domain means a real account can never be
    caught by this."""
    rows = fetch(
        "select id from auth.users where email like %s",
        (f"%@{SYNTH_DOMAIN}",),
    )
    if not rows:
        print("nothing to clean")
        return
    print(f"removing {len(rows)} synthetic students and everything they own")
    execute("delete from auth.users where email like %s", (f"%@{SYNTH_DOMAIN}",))
    print("done")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--students", type=int, default=30)
    ap.add_argument("--days", type=int, default=21)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--dry", action="store_true", help="summarise without writing")
    ap.add_argument("--clean", action="store_true", help="delete the synthetic cohort")
    a = ap.parse_args()

    if a.clean:
        clean()
    else:
        generate(a.students, a.days, a.seed, a.dry)
'@

Write-ProjectFile 'supabase\migrations\002_seed_starter_content.sql' @'
-- =====================================================================
-- 002_seed_starter_content.sql
-- 16 concepts, 18 DAG edges, 12 misconceptions, 20 tagged questions.
-- Enough to run a real placement test before the full bank exists.
-- Safe to re-run: every insert is idempotent.
-- =====================================================================

insert into subjects (subject_id, name, description, is_authored) values
  ('dbms', 'Database Management Systems', 'Relational model through normalization', true),
  ('dsa', 'Data Structures and Algorithms', 'Arrays through shortest paths', true)
on conflict (subject_id) do nothing;

insert into concepts (concept_id, subject_id, name, level) values
  ('dbms.relational_model', 'dbms', 'Relational model', 0),
  ('dbms.keys', 'dbms', 'Keys', 1),
  ('dbms.functional_dependency', 'dbms', 'Functional dependency', 2),
  ('dbms.normalization_2nf', 'dbms', 'Second normal form', 3),
  ('dbms.normalization_3nf', 'dbms', 'Third normal form', 4),
  ('dbms.joins', 'dbms', 'SQL joins', 2),
  ('dsa.arrays', 'dsa', 'Arrays and indexing', 0),
  ('dsa.complexity', 'dsa', 'Time complexity', 0),
  ('dsa.sorting', 'dsa', 'Sorting basics', 1),
  ('dsa.recursion', 'dsa', 'Recursion', 1),
  ('dsa.binary_search', 'dsa', 'Binary search', 2),
  ('dsa.heaps', 'dsa', 'Heaps and priority queues', 2),
  ('dsa.graph_repr', 'dsa', 'Graph representation', 2),
  ('dsa.bfs', 'dsa', 'BFS', 3),
  ('dsa.dfs', 'dsa', 'DFS', 3),
  ('dsa.dijkstra', 'dsa', 'Dijkstra', 4)
on conflict (concept_id) do nothing;

insert into prerequisites (parent_id, child_id, weight) values
  ('dbms.relational_model', 'dbms.keys', 0.9),
  ('dbms.keys', 'dbms.functional_dependency', 0.8),
  ('dbms.keys', 'dbms.joins', 0.7),
  ('dbms.functional_dependency', 'dbms.normalization_2nf', 0.9),
  ('dbms.normalization_2nf', 'dbms.normalization_3nf', 0.9),
  ('dbms.functional_dependency', 'dbms.normalization_3nf', 0.7),
  ('dsa.arrays', 'dsa.sorting', 0.8),
  ('dsa.complexity', 'dsa.sorting', 0.7),
  ('dsa.arrays', 'dsa.binary_search', 0.6),
  ('dsa.sorting', 'dsa.binary_search', 0.8),
  ('dsa.sorting', 'dsa.heaps', 0.85),
  ('dsa.arrays', 'dsa.graph_repr', 0.6),
  ('dsa.recursion', 'dsa.dfs', 0.9),
  ('dsa.graph_repr', 'dsa.bfs', 0.8),
  ('dsa.graph_repr', 'dsa.dfs', 0.8),
  ('dsa.heaps', 'dsa.dijkstra', 0.9),
  ('dsa.bfs', 'dsa.dijkstra', 0.7),
  ('dsa.graph_repr', 'dsa.dijkstra', 0.6)
on conflict (parent_id, child_id) do nothing;

insert into misconceptions (misconception_id, concept_id, label, remediation_note) values
  ('dbms.m01', 'dbms.keys', 'Believes a foreign key must be unique', 'Show a one-to-many example where the FK repeats across many rows.'),
  ('dbms.m02', 'dbms.keys', 'Treats primary and candidate key as interchangeable', 'A relation may have several candidate keys; exactly one is chosen as primary.'),
  ('dbms.m03', 'dbms.normalization_3nf', 'Confuses transitive with partial dependency', 'Partial needs a composite key. Transitive works through a non-key attribute.'),
  ('dbms.m04', 'dbms.normalization_2nf', 'Thinks 2NF applies with a single-attribute key', 'With an atomic key there is no proper subset, so 2NF cannot be violated.'),
  ('dbms.m05', 'dbms.joins', 'Expects LEFT JOIN to drop unmatched left rows', 'LEFT JOIN keeps every left row and pads the right side with NULL.'),
  ('dsa.m01', 'dsa.complexity', 'Reads nested loops as automatically quadratic', 'The inner bound matters. A halving inner loop gives n log n, not n squared.'),
  ('dsa.m02', 'dsa.heaps', 'Assumes heapify is repeated insertion', 'Bottom-up heapify is O(n); n successive insertions is O(n log n).'),
  ('dsa.m03', 'dsa.binary_search', 'Forgets the sorted-input precondition', 'Binary search on unsorted data is not slow, it is wrong.'),
  ('dsa.m04', 'dsa.bfs', 'Uses a stack for BFS', 'BFS needs FIFO. A stack turns it into DFS.'),
  ('dsa.m05', 'dsa.dijkstra', 'Believes Dijkstra handles negative weights', 'Once a node is settled it is never revisited, which negative edges break.'),
  ('dsa.m06', 'dsa.sorting', 'Thinks quicksort is always O(n log n)', 'Worst case is quadratic when pivots split badly.'),
  ('dsa.m07', 'dsa.recursion', 'Omits the base case from the cost', 'Every recursive call must reduce toward a terminating case.')
on conflict (misconception_id) do nothing;

-- Default BKT parameters. The Python service refits these once data exists.
insert into bkt_params (concept_id, p_init, p_transit, p_slip, p_guess)
select concept_id, 0.15, 0.15, 0.10, 0.25 from concepts
on conflict (concept_id) do nothing;

-- Questions and options. Deterministic UUIDs so re-running does not duplicate.
do $$
declare qid uuid;
begin
  qid := md5('seed-q001')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.keys', 'Which of the following may contain duplicate values in a relation?', -0.8, 40, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.keys', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q001-o0')::uuid, qid, 'Primary key', false, 'dbms.m02', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q001-o1')::uuid, qid, 'Foreign key', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q001-o2')::uuid, qid, 'Candidate key', false, 'dbms.m02', 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q001-o3')::uuid, qid, 'Super key', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q002')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.keys', 'A relation has candidate keys {A} and {B, C}. How many primary keys does it have?', -0.3, 45, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.keys', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q002-o0')::uuid, qid, 'Two', false, 'dbms.m02', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q002-o1')::uuid, qid, 'One', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q002-o2')::uuid, qid, 'Three', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q002-o3')::uuid, qid, 'None until declared', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q003')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.functional_dependency', 'Given A -> B and B -> C, which dependency follows by transitivity?', -0.5, 40, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.functional_dependency', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q003-o0')::uuid, qid, 'B -> A', false, null, 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q003-o1')::uuid, qid, 'A -> C', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q003-o2')::uuid, qid, 'C -> A', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q003-o3')::uuid, qid, 'AC -> B', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q004')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.normalization_2nf', 'R(A, B, C) has the single candidate key A. Can R violate 2NF?', 0.4, 55, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.normalization_2nf', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q004-o0')::uuid, qid, 'Yes, if A -> B -> C', false, 'dbms.m04', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q004-o1')::uuid, qid, 'No, an atomic key has no proper subset', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q004-o2')::uuid, qid, 'Yes, whenever a non-key attribute exists', false, 'dbms.m04', 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q004-o3')::uuid, qid, 'Only if C is multivalued', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q005')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.normalization_3nf', 'R(A, B, C) has A as the only candidate key, with A -> B and B -> C. Which normal form does R violate?', 0.3, 55, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.normalization_3nf', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q005-o0')::uuid, qid, 'First normal form', false, null, 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q005-o1')::uuid, qid, 'Second normal form', false, 'dbms.m03', 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q005-o2')::uuid, qid, 'Third normal form', true, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q005-o3')::uuid, qid, 'No violation', false, 'dbms.m03', 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q006')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.normalization_3nf', 'Which condition is required for a transitive dependency to exist?', 0.5, 50, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.normalization_3nf', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q006-o0')::uuid, qid, 'A composite primary key', false, 'dbms.m03', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q006-o1')::uuid, qid, 'A non-key attribute determining another non-key attribute', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q006-o2')::uuid, qid, 'A multivalued attribute', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q006-o3')::uuid, qid, 'At least two relations', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q007')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.joins', 'Table A has 5 rows, table B has 3, and only 2 rows match on the join key. How many rows does A LEFT JOIN B return?', 0.0, 50, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.joins', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q007-o0')::uuid, qid, '2', false, 'dbms.m05', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q007-o1')::uuid, qid, '5', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q007-o2')::uuid, qid, '3', false, 'dbms.m05', 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q007-o3')::uuid, qid, '15', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q008')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.joins', 'Which join returns only rows present in both tables?', -0.9, 30, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.joins', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q008-o0')::uuid, qid, 'LEFT JOIN', false, 'dbms.m05', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q008-o1')::uuid, qid, 'INNER JOIN', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q008-o2')::uuid, qid, 'FULL OUTER JOIN', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q008-o3')::uuid, qid, 'CROSS JOIN', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q009')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.relational_model', 'In the relational model, what does a tuple correspond to?', -1.0, 30, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.relational_model', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q009-o0')::uuid, qid, 'A column', false, null, 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q009-o1')::uuid, qid, 'A row', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q009-o2')::uuid, qid, 'A table', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q009-o3')::uuid, qid, 'A constraint', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q010')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.complexity', 'for (i=0;i<n;i++) for (j=1;j<n;j*=2) — what is the time complexity?', 0.2, 50, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.complexity', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q010-o0')::uuid, qid, 'O(n^2)', false, 'dsa.m01', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q010-o1')::uuid, qid, 'O(n log n)', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q010-o2')::uuid, qid, 'O(n)', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q010-o3')::uuid, qid, 'O(log n)', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q011')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.complexity', 'What is the time complexity of accessing an element by index in an array?', -1.1, 25, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.complexity', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q011-o0')::uuid, qid, 'O(n)', false, null, 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q011-o1')::uuid, qid, 'O(1)', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q011-o2')::uuid, qid, 'O(log n)', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q011-o3')::uuid, qid, 'O(n log n)', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q012')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.sorting', 'What is the worst-case time complexity of quicksort?', -0.2, 35, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.sorting', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q012-o0')::uuid, qid, 'O(n log n)', false, 'dsa.m06', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q012-o1')::uuid, qid, 'O(n^2)', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q012-o2')::uuid, qid, 'O(n)', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q012-o3')::uuid, qid, 'O(log n)', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q013')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.sorting', 'Which sorting algorithm guarantees O(n log n) in the worst case?', -0.1, 35, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.sorting', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q013-o0')::uuid, qid, 'Quicksort', false, 'dsa.m06', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q013-o1')::uuid, qid, 'Merge sort', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q013-o2')::uuid, qid, 'Insertion sort', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q013-o3')::uuid, qid, 'Bubble sort', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q014')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.heaps', 'What is the time complexity of building a heap from an unsorted array of n elements?', 0.6, 45, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.heaps', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q014-o0')::uuid, qid, 'O(n log n)', false, 'dsa.m02', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q014-o1')::uuid, qid, 'O(n)', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q014-o2')::uuid, qid, 'O(log n)', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q014-o3')::uuid, qid, 'O(n^2)', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q015')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.heaps', 'What does peek() return on a min-heap?', -0.9, 25, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.heaps', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q015-o0')::uuid, qid, 'The largest element', false, null, 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q015-o1')::uuid, qid, 'The smallest element', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q015-o2')::uuid, qid, 'The median element', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q015-o3')::uuid, qid, 'The most recently inserted element', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q016')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.binary_search', 'Binary search is run on an unsorted array. What happens?', -0.4, 40, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.binary_search', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q016-o0')::uuid, qid, 'It still works, just slower', false, 'dsa.m03', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q016-o1')::uuid, qid, 'It may return a wrong result', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q016-o2')::uuid, qid, 'It throws an error', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q016-o3')::uuid, qid, 'It degrades to O(n)', false, 'dsa.m03', 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q017')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.bfs', 'Which data structure does BFS use to hold the frontier?', -0.6, 30, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.bfs', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q017-o0')::uuid, qid, 'Stack', false, 'dsa.m04', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q017-o1')::uuid, qid, 'Queue', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q017-o2')::uuid, qid, 'Priority queue', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q017-o3')::uuid, qid, 'Hash set', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q018')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.dfs', 'Recursive DFS implicitly uses which structure?', -0.3, 35, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.dfs', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q018-o0')::uuid, qid, 'The heap', false, null, 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q018-o1')::uuid, qid, 'The call stack', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q018-o2')::uuid, qid, 'A queue', false, 'dsa.m04', 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q018-o3')::uuid, qid, 'A set', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q019')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.dijkstra', 'Why does Dijkstra fail on graphs with negative edge weights?', 0.7, 60, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.dijkstra', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q019-o0')::uuid, qid, 'It cannot represent negative numbers', false, 'dsa.m05', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q019-o1')::uuid, qid, 'A settled node is never revisited, so a later cheaper path is missed', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q019-o2')::uuid, qid, 'The priority queue overflows', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q019-o3')::uuid, qid, 'It does not fail; it is simply slower', false, 'dsa.m05', 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q020')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.recursion', 'What happens when a recursive function has no reachable base case?', -0.7, 30, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.recursion', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q020-o0')::uuid, qid, 'It returns zero', false, 'dsa.m07', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q020-o1')::uuid, qid, 'It recurses until the stack overflows', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q020-o2')::uuid, qid, 'The compiler rejects it', false, 'dsa.m07', 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q020-o3')::uuid, qid, 'It runs in constant time', false, null, 3)
  on conflict (option_id) do nothing;

end $$;

insert into exam_profiles (exam_id, name, description) values
  ('tcs_nqt', 'TCS NQT', 'National Qualifier Test'),
  ('infosys_se', 'Infosys SE', 'Systems Engineer'),
  ('amazon_sde1', 'Amazon SDE-1', 'Software Development Engineer I')
on conflict (exam_id) do nothing;
'@

Write-ProjectFile 'supabase\migrations\003_typing_telemetry.sql' @'
-- =====================================================================
-- 003_typing_telemetry.sql
-- Keystroke-derived focus signal for the coding section.
--
-- Stores AGGREGATES PER WINDOW ONLY. No keystrokes, no code content.
-- Gated behind profiles.tracking_opt_in like all attention data.
-- =====================================================================

create table typing_windows (
  window_id            bigserial primary key,
  session_id           uuid references study_sessions(session_id) on delete cascade,
  student_id           uuid not null references profiles(student_id) on delete cascade,
  minutes_into_session numeric not null,
  window_seconds       int     not null default 120,

  chars_typed          int     not null default 0,
  mean_iki_ms          numeric,          -- inter-key interval, pauses excluded
  sd_iki_ms            numeric,          -- rhythm consistency; rises with fatigue
  backspace_rate       numeric,          -- corrections per char
  pauses_over_2s       int     not null default 0,
  longest_pause_ms     int,
  mean_burst_len       numeric,          -- chars per uninterrupted run

  -- Pauses classified by how they END, which separates thinking from
  -- disengagement far better than pause length does.
  pauses_thinking      int     not null default 0,
  pauses_lost          int     not null default 0,

  run_attempts         int     not null default 0,
  run_failures         int     not null default 0,

  focus_index          numeric,          -- filled by the Python job
  created_at           timestamptz not null default now()
);
create index on typing_windows(student_id, created_at desc);
create index on typing_windows(session_id);

-- Per-student typing baseline. Needs ~3 sessions before it means anything;
-- until then focus_index stays null and the UI reports nothing.
create table typing_baseline (
  student_id      uuid primary key references profiles(student_id) on delete cascade,
  mean_iki_ms     numeric,
  sd_iki_ms       numeric,
  backspace_rate  numeric,
  mean_burst_len  numeric,
  sample_windows  int not null default 0,
  updated_at      timestamptz not null default now()
);

alter table typing_windows  enable row level security;
alter table typing_baseline enable row level security;

create policy own_typing_windows on typing_windows for all to authenticated
  using (student_id = auth.uid()) with check (student_id = auth.uid());
create policy own_typing_baseline on typing_baseline for all to authenticated
  using (student_id = auth.uid()) with check (student_id = auth.uid());

-- Coding problems are content, not student data: readable by any signed-in user.
create table coding_problems (
  problem_id   text primary key,
  concept_id   text references concepts(concept_id) on delete set null,
  title        text not null,
  prompt       text not null,
  starter_code text not null,
  difficulty   numeric not null default 0,
  language     text not null default 'javascript',
  is_active    boolean not null default true
);

create table coding_tests (
  test_id     bigserial primary key,
  problem_id  text not null references coding_problems(problem_id) on delete cascade,
  input_json  text not null,
  expect_json text not null,
  is_hidden   boolean not null default false,
  ordinal     int not null default 0
);

alter table coding_problems enable row level security;
alter table coding_tests    enable row level security;
create policy read_problems on coding_problems for select to authenticated using (true);
create policy read_tests    on coding_tests    for select to authenticated using (true);

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty) values
('cp.two_sum', 'dsa.arrays', 'Two Sum',
 'Return the indices of the two numbers in nums that add up to target. Exactly one solution exists. Return them as an array, smaller index first.',
 'function solve(nums, target) {\n  // your code here\n}', -0.3),
('cp.binary_search', 'dsa.binary_search', 'Binary Search',
 'Return the index of target in the sorted array nums, or -1 if it is not present. Must run in O(log n).',
 'function solve(nums, target) {\n  // your code here\n}', 0.0),
('cp.kth_largest', 'dsa.heaps', 'Kth Largest Element',
 'Return the kth largest element in nums. Duplicates count separately, so [3,2,3,1] with k=2 gives 3.',
 'function solve(nums, k) {\n  // your code here\n}', 0.5)
on conflict (problem_id) do nothing;

insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal) values
('cp.two_sum', '[[2,7,11,15],9]', '[0,1]', false, 0),
('cp.two_sum', '[[3,2,4],6]', '[1,2]', false, 1),
('cp.two_sum', '[[3,3],6]', '[0,1]', true, 2),
('cp.binary_search', '[[-1,0,3,5,9,12],9]', '4', false, 0),
('cp.binary_search', '[[-1,0,3,5,9,12],2]', '-1', false, 1),
('cp.binary_search', '[[5],5]', '0', true, 2),
('cp.kth_largest', '[[3,2,1,5,6,4],2]', '5', false, 0),
('cp.kth_largest', '[[3,2,3,1,2,4,5,5,6],4]', '4', false, 1),
('cp.kth_largest', '[[1],1]', '1', true, 2);
'@

Write-ProjectFile 'supabase\migrations\004_content_expansion.sql' @'
-- =====================================================================
-- 004_content_expansion.sql
-- Fixes literal \n in starter_code (Postgres needs E-strings), adds a
-- language column, and expands the bank:
--   +32 concepts, +32 edges, +23 misconceptions,
--   +53 questions, +9 coding problems.
-- Idempotent: safe to re-run.
-- =====================================================================

insert into subjects (subject_id, name, description, is_authored) values
  ('cn', 'Computer Networks', 'OSI model through HTTP', true),
  ('os', 'Operating Systems', 'Processes through file systems', true)
on conflict (subject_id) do nothing;

insert into concepts (concept_id, subject_id, name, level) values
  ('cn.osi_model', 'cn', 'OSI model', 0),
  ('cn.ip_addressing', 'cn', 'IP addressing', 0),
  ('cn.subnetting', 'cn', 'Subnetting', 1),
  ('cn.switching', 'cn', 'Switching and MAC', 1),
  ('cn.routing', 'cn', 'Routing basics', 2),
  ('cn.transport', 'cn', 'Transport layer', 1),
  ('cn.tcp_basics', 'cn', 'TCP fundamentals', 2),
  ('cn.udp', 'cn', 'UDP', 2),
  ('cn.tcp_flow', 'cn', 'TCP flow control', 3),
  ('cn.tcp_congestion', 'cn', 'TCP congestion control', 3),
  ('cn.dns', 'cn', 'DNS', 2),
  ('cn.http', 'cn', 'HTTP', 3),
  ('os.process', 'os', 'Processes', 0),
  ('os.thread', 'os', 'Threads', 1),
  ('os.scheduling', 'os', 'CPU scheduling', 2),
  ('os.sync', 'os', 'Synchronization', 2),
  ('os.deadlock', 'os', 'Deadlock', 3),
  ('os.memory', 'os', 'Memory management', 1),
  ('os.paging', 'os', 'Paging', 2),
  ('os.virtual_memory', 'os', 'Virtual memory', 3),
  ('os.page_replacement', 'os', 'Page replacement', 4),
  ('os.filesystem', 'os', 'File systems', 2),
  ('dsa.hashing', 'dsa', 'Hashing', 1),
  ('dsa.two_pointers', 'dsa', 'Two pointers', 2),
  ('dsa.sliding_window', 'dsa', 'Sliding window', 3),
  ('dsa.dp_1d', 'dsa', 'Dynamic programming (1D)', 4),
  ('dsa.trees', 'dsa', 'Trees', 3),
  ('dsa.bst', 'dsa', 'Binary search trees', 4),
  ('dbms.transactions', 'dbms', 'Transactions and ACID', 3),
  ('dbms.indexing', 'dbms', 'Indexing', 3),
  ('dbms.bcnf', 'dbms', 'BCNF', 5),
  ('dbms.sql_aggregate', 'dbms', 'SQL aggregation', 2)
on conflict (concept_id) do nothing;

insert into prerequisites (parent_id, child_id, weight) values
  ('cn.osi_model', 'cn.transport', 0.8),
  ('cn.ip_addressing', 'cn.subnetting', 0.9),
  ('cn.ip_addressing', 'cn.routing', 0.8),
  ('cn.osi_model', 'cn.switching', 0.6),
  ('cn.switching', 'cn.routing', 0.6),
  ('cn.transport', 'cn.tcp_basics', 0.9),
  ('cn.transport', 'cn.udp', 0.8),
  ('cn.tcp_basics', 'cn.tcp_flow', 0.9),
  ('cn.tcp_flow', 'cn.tcp_congestion', 0.85),
  ('cn.tcp_basics', 'cn.tcp_congestion', 0.7),
  ('cn.ip_addressing', 'cn.dns', 0.6),
  ('cn.tcp_basics', 'cn.http', 0.7),
  ('cn.dns', 'cn.http', 0.5),
  ('os.process', 'os.thread', 0.9),
  ('os.process', 'os.scheduling', 0.8),
  ('os.thread', 'os.sync', 0.9),
  ('os.sync', 'os.deadlock', 0.85),
  ('os.memory', 'os.paging', 0.9),
  ('os.paging', 'os.virtual_memory', 0.9),
  ('os.virtual_memory', 'os.page_replacement', 0.9),
  ('os.memory', 'os.filesystem', 0.5),
  ('dsa.arrays', 'dsa.hashing', 0.7),
  ('dsa.arrays', 'dsa.two_pointers', 0.8),
  ('dsa.two_pointers', 'dsa.sliding_window', 0.85),
  ('dsa.recursion', 'dsa.dp_1d', 0.85),
  ('dsa.recursion', 'dsa.trees', 0.8),
  ('dsa.trees', 'dsa.bst', 0.9),
  ('dsa.sorting', 'dsa.bst', 0.5),
  ('dbms.relational_model', 'dbms.transactions', 0.6),
  ('dbms.keys', 'dbms.indexing', 0.7),
  ('dbms.normalization_3nf', 'dbms.bcnf', 0.9),
  ('dbms.joins', 'dbms.sql_aggregate', 0.7)
on conflict (parent_id, child_id) do nothing;

insert into misconceptions (misconception_id, concept_id, label, remediation_note) values
  ('cn.m01', 'cn.subnetting', 'Counts host bits from the wrong end', 'Host bits are the low-order bits. /26 leaves 6 host bits, so 62 usable addresses.'),
  ('cn.m02', 'cn.subnetting', 'Forgets network and broadcast are unreserved', 'Usable hosts are 2^h minus 2, never 2^h.'),
  ('cn.m03', 'cn.tcp_flow', 'Confuses flow control with congestion control', 'Flow control protects the receiver. Congestion control protects the network.'),
  ('cn.m04', 'cn.tcp_congestion', 'Thinks slow start is linear', 'Slow start doubles cwnd per RTT. It is exponential despite the name.'),
  ('cn.m05', 'cn.udp', 'Believes UDP guarantees ordering', 'UDP has no ordering, no retransmission, and no delivery guarantee.'),
  ('cn.m06', 'cn.osi_model', 'Places TCP at the network layer', 'TCP is layer 4. IP is layer 3.'),
  ('cn.m07', 'cn.dns', 'Thinks DNS runs only over TCP', 'DNS uses UDP for standard queries and TCP for zone transfers or large responses.'),
  ('cn.m08', 'cn.http', 'Assumes HTTP is stateful', 'HTTP is stateless. State comes from cookies, tokens, or sessions layered on top.'),
  ('os.m01', 'os.thread', 'Thinks threads have separate address spaces', 'Threads share the address space. Processes do not.'),
  ('os.m02', 'os.scheduling', 'Believes SJF is always optimal in practice', 'SJF minimises average waiting time but requires knowing burst lengths in advance.'),
  ('os.m03', 'os.deadlock', 'Thinks removing any one condition is impossible', 'Breaking any one of the four Coffman conditions prevents deadlock.'),
  ('os.m04', 'os.sync', 'Confuses a mutex with a semaphore', 'A mutex has ownership. A counting semaphore does not.'),
  ('os.m05', 'os.paging', 'Believes paging causes external fragmentation', 'Paging eliminates external fragmentation and introduces internal fragmentation.'),
  ('os.m06', 'os.page_replacement', 'Assumes more frames always mean fewer faults', 'Belady anomaly: FIFO can fault more with more frames.'),
  ('os.m07', 'os.virtual_memory', 'Thinks thrashing means the disk has failed', 'Thrashing is excessive paging because the working set exceeds available frames.'),
  ('dsa.m08', 'dsa.hashing', 'Assumes hash lookup is always O(1)', 'Worst case is O(n) when every key collides into one bucket.'),
  ('dsa.m09', 'dsa.sliding_window', 'Applies the window to arrays with negatives', 'A shrinking window needs monotonic sums, which negatives break.'),
  ('dsa.m10', 'dsa.dp_1d', 'Confuses memoization with tabulation', 'Both cache subproblems; one is top-down recursive, the other bottom-up iterative.'),
  ('dsa.m11', 'dsa.bst', 'Thinks BST operations are always O(log n)', 'Unbalanced BSTs degrade to O(n). Only balanced trees guarantee log n.'),
  ('dbms.m06', 'dbms.transactions', 'Thinks isolation prevents all anomalies by default', 'Isolation level decides which anomalies are prevented. READ COMMITTED still allows non-repeatable reads.'),
  ('dbms.m07', 'dbms.indexing', 'Believes an index always speeds up a query', 'Indexes cost writes and are ignored when selectivity is poor.'),
  ('dbms.m08', 'dbms.bcnf', 'Thinks 3NF and BCNF are the same', 'They differ only when candidate keys overlap.'),
  ('dbms.m09', 'dbms.sql_aggregate', 'Uses WHERE to filter aggregates', 'WHERE filters rows before grouping. HAVING filters after.')
on conflict (misconception_id) do nothing;

insert into bkt_params (concept_id, p_init, p_transit, p_slip, p_guess)
select concept_id, 0.15, 0.15, 0.10, 0.25 from concepts
on conflict (concept_id) do nothing;

do $$
declare qid uuid;
begin
  qid := md5('x2-q001')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.osi_model', 'At which OSI layer does TCP operate?', -0.6, 30, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.osi_model', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q001-o0')::uuid, qid, 'Layer 3, network', false, 'cn.m06', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q001-o1')::uuid, qid, 'Layer 4, transport', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q001-o2')::uuid, qid, 'Layer 5, session', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q001-o3')::uuid, qid, 'Layer 2, data link', false, 'cn.m06', 3) on conflict (option_id) do nothing;

  qid := md5('x2-q002')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.osi_model', 'Which layer is responsible for routing packets between networks?', -0.5, 32, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.osi_model', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q002-o0')::uuid, qid, 'Transport', false, 'cn.m06', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q002-o1')::uuid, qid, 'Network', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q002-o2')::uuid, qid, 'Data link', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q002-o3')::uuid, qid, 'Session', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q003')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.ip_addressing', 'How many bits are in an IPv4 address?', -1.1, 20, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.ip_addressing', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q003-o0')::uuid, qid, '64', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q003-o1')::uuid, qid, '32', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q003-o2')::uuid, qid, '128', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q003-o3')::uuid, qid, '16', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q004')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.subnetting', 'How many usable host addresses does a /26 subnet provide?', 0.3, 60, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.subnetting', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q004-o0')::uuid, qid, '64', false, 'cn.m02', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q004-o1')::uuid, qid, '62', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q004-o2')::uuid, qid, '30', false, 'cn.m01', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q004-o3')::uuid, qid, '126', false, 'cn.m01', 3) on conflict (option_id) do nothing;

  qid := md5('x2-q005')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.subnetting', 'What is the subnet mask for a /27 network?', 0.2, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.subnetting', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q005-o0')::uuid, qid, '255.255.255.192', false, 'cn.m01', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q005-o1')::uuid, qid, '255.255.255.224', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q005-o2')::uuid, qid, '255.255.255.240', false, 'cn.m01', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q005-o3')::uuid, qid, '255.255.255.128', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q006')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.subnetting', 'A /30 subnet is commonly used for point-to-point links. Why?', 0.5, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.subnetting', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q006-o0')::uuid, qid, 'It provides 4 usable addresses', false, 'cn.m02', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q006-o1')::uuid, qid, 'It provides exactly 2 usable addresses', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q006-o2')::uuid, qid, 'It provides 8 usable addresses', false, 'cn.m02', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q006-o3')::uuid, qid, 'It has no broadcast address', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q007')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.tcp_basics', 'How many messages are exchanged in the TCP three-way handshake?', -0.7, 25, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.tcp_basics', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q007-o0')::uuid, qid, 'Two', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q007-o1')::uuid, qid, 'Three', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q007-o2')::uuid, qid, 'Four', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q007-o3')::uuid, qid, 'One', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q008')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.tcp_basics', 'Which TCP mechanism detects a lost segment without waiting for a timeout?', 0.4, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.tcp_basics', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q008-o0')::uuid, qid, 'Slow start', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q008-o1')::uuid, qid, 'Three duplicate ACKs', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q008-o2')::uuid, qid, 'Nagle algorithm', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q008-o3')::uuid, qid, 'Window scaling', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q009')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.tcp_flow', 'What does the TCP receive window advertise?', 0.2, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.tcp_flow', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q009-o0')::uuid, qid, 'How congested the network path is', false, 'cn.m03', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q009-o1')::uuid, qid, 'How much buffer space the receiver has free', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q009-o2')::uuid, qid, 'The maximum segment size', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q009-o3')::uuid, qid, 'The round-trip time estimate', false, 'cn.m03', 3) on conflict (option_id) do nothing;

  qid := md5('x2-q010')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.tcp_flow', 'Flow control exists to protect which party?', 0.0, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.tcp_flow', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q010-o0')::uuid, qid, 'The intermediate routers', false, 'cn.m03', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q010-o1')::uuid, qid, 'The receiver', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q010-o2')::uuid, qid, 'The sender', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q010-o3')::uuid, qid, 'The DNS resolver', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q011')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.tcp_congestion', 'How does the congestion window grow during slow start?', 0.5, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.tcp_congestion', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q011-o0')::uuid, qid, 'Linearly, one MSS per RTT', false, 'cn.m04', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q011-o1')::uuid, qid, 'Exponentially, doubling each RTT', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q011-o2')::uuid, qid, 'It stays constant', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q011-o3')::uuid, qid, 'It halves each RTT', false, 'cn.m04', 3) on conflict (option_id) do nothing;

  qid := md5('x2-q012')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.tcp_congestion', 'What happens to cwnd on a timeout in TCP Reno?', 0.7, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.tcp_congestion', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q012-o0')::uuid, qid, 'It doubles', false, 'cn.m04', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q012-o1')::uuid, qid, 'It drops to one MSS and slow start restarts', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q012-o2')::uuid, qid, 'It stays the same', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q012-o3')::uuid, qid, 'It grows linearly', false, 'cn.m04', 3) on conflict (option_id) do nothing;

  qid := md5('x2-q013')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.udp', 'Which guarantee does UDP provide?', -0.4, 35, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.udp', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q013-o0')::uuid, qid, 'In-order delivery', false, 'cn.m05', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q013-o1')::uuid, qid, 'None of these', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q013-o2')::uuid, qid, 'Retransmission of lost packets', false, 'cn.m05', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q013-o3')::uuid, qid, 'Flow control', false, 'cn.m05', 3) on conflict (option_id) do nothing;

  qid := md5('x2-q014')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.udp', 'Why is UDP preferred for live video streaming?', 0.1, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.udp', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q014-o0')::uuid, qid, 'It guarantees ordering', false, 'cn.m05', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q014-o1')::uuid, qid, 'Retransmitting a late frame is worse than dropping it', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q014-o2')::uuid, qid, 'It encrypts by default', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q014-o3')::uuid, qid, 'It uses fewer ports', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q015')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.dns', 'Which transport protocol does a standard DNS query use?', 0.0, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.dns', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q015-o0')::uuid, qid, 'TCP only', false, 'cn.m07', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q015-o1')::uuid, qid, 'UDP, falling back to TCP for large responses', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q015-o2')::uuid, qid, 'ICMP', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q015-o3')::uuid, qid, 'HTTP', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q016')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.dns', 'What does a DNS A record map?', -0.8, 25, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.dns', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q016-o0')::uuid, qid, 'A domain to a mail server', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q016-o1')::uuid, qid, 'A domain to an IPv4 address', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q016-o2')::uuid, qid, 'A domain to another domain', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q016-o3')::uuid, qid, 'A domain to an IPv6 address', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q017')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.http', 'Why is HTTP described as stateless?', 0.1, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.http', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q017-o0')::uuid, qid, 'It cannot send data', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q017-o1')::uuid, qid, 'Each request is independent; the server keeps no inherent memory of prior ones', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q017-o2')::uuid, qid, 'It has no status codes', false, 'cn.m08', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q017-o3')::uuid, qid, 'It requires cookies to function', false, 'cn.m08', 3) on conflict (option_id) do nothing;

  qid := md5('x2-q018')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.http', 'Which HTTP status code family indicates a client error?', -0.6, 30, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.http', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q018-o0')::uuid, qid, '3xx', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q018-o1')::uuid, qid, '4xx', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q018-o2')::uuid, qid, '5xx', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q018-o3')::uuid, qid, '2xx', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q019')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.routing', 'What does a routing table entry with the longest prefix match determine?', 0.4, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.routing', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q019-o0')::uuid, qid, 'The slowest path', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q019-o1')::uuid, qid, 'The most specific matching route', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q019-o2')::uuid, qid, 'The default gateway only', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q019-o3')::uuid, qid, 'The MAC address', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q020')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.switching', 'At which layer does an Ethernet switch primarily operate?', -0.3, 30, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.switching', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q020-o0')::uuid, qid, 'Layer 3', false, 'cn.m06', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q020-o1')::uuid, qid, 'Layer 2', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q020-o2')::uuid, qid, 'Layer 4', false, 'cn.m06', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q020-o3')::uuid, qid, 'Layer 1', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q021')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.process', 'What is the main difference between a process and a program?', -0.7, 35, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.process', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q021-o0')::uuid, qid, 'There is none', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q021-o1')::uuid, qid, 'A process is a program in execution with its own state', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q021-o2')::uuid, qid, 'A program is faster', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q021-o3')::uuid, qid, 'A process has no memory', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q022')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.thread', 'Which resource is shared between threads of the same process?', -0.2, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.thread', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q022-o0')::uuid, qid, 'The stack', false, 'os.m01', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q022-o1')::uuid, qid, 'The heap and address space', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q022-o2')::uuid, qid, 'The program counter', false, 'os.m01', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q022-o3')::uuid, qid, 'The register set', false, 'os.m01', 3) on conflict (option_id) do nothing;

  qid := md5('x2-q023')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.thread', 'What is the main advantage of threads over processes for concurrency?', 0.0, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.thread', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q023-o0')::uuid, qid, 'Threads have isolated memory', false, 'os.m01', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q023-o1')::uuid, qid, 'Context switching and communication are cheaper', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q023-o2')::uuid, qid, 'Threads cannot deadlock', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q023-o3')::uuid, qid, 'Threads never share data', false, 'os.m01', 3) on conflict (option_id) do nothing;

  qid := md5('x2-q024')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.scheduling', 'Which scheduling algorithm minimises average waiting time in theory?', 0.2, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.scheduling', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q024-o0')::uuid, qid, 'First come first served', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q024-o1')::uuid, qid, 'Shortest job first', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q024-o2')::uuid, qid, 'Round robin', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q024-o3')::uuid, qid, 'Priority with aging', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q025')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.scheduling', 'Why is SJF hard to use in a real operating system?', 0.5, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.scheduling', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q025-o0')::uuid, qid, 'It is too slow to compute', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q025-o1')::uuid, qid, 'Future burst lengths are not known in advance', true, 'os.m02', 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q025-o2')::uuid, qid, 'It causes deadlock', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q025-o3')::uuid, qid, 'It requires more memory', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q026')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.scheduling', 'What problem does a very small round-robin time quantum cause?', 0.4, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.scheduling', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q026-o0')::uuid, qid, 'Starvation of short jobs', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q026-o1')::uuid, qid, 'Excessive context-switch overhead', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q026-o2')::uuid, qid, 'Deadlock', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q026-o3')::uuid, qid, 'Memory fragmentation', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q027')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.deadlock', 'How many Coffman conditions must hold simultaneously for deadlock?', -0.1, 35, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.deadlock', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q027-o0')::uuid, qid, 'Two', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q027-o1')::uuid, qid, 'Four', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q027-o2')::uuid, qid, 'Three', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q027-o3')::uuid, qid, 'Five', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q028')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.deadlock', 'Which is NOT one of the four necessary conditions for deadlock?', 0.3, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.deadlock', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q028-o0')::uuid, qid, 'Mutual exclusion', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q028-o1')::uuid, qid, 'Preemption of held resources', true, 'os.m03', 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q028-o2')::uuid, qid, 'Hold and wait', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q028-o3')::uuid, qid, 'Circular wait', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q029')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.sync', 'What distinguishes a mutex from a binary semaphore?', 0.4, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.sync', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q029-o0')::uuid, qid, 'Nothing, they are identical', false, 'os.m04', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q029-o1')::uuid, qid, 'A mutex has an owner and only the owner may release it', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q029-o2')::uuid, qid, 'A mutex counts to more than one', false, 'os.m04', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q029-o3')::uuid, qid, 'A semaphore cannot block', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q030')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.sync', 'What is a race condition?', -0.3, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.sync', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q030-o0')::uuid, qid, 'Two processes competing for CPU time', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q030-o1')::uuid, qid, 'Output depending on the unpredictable ordering of concurrent accesses', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q030-o2')::uuid, qid, 'A deadlock between two threads', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q030-o3')::uuid, qid, 'A scheduling algorithm', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q031')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.paging', 'Which type of fragmentation does paging introduce?', 0.2, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.paging', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q031-o0')::uuid, qid, 'External fragmentation', false, 'os.m05', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q031-o1')::uuid, qid, 'Internal fragmentation', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q031-o2')::uuid, qid, 'Both equally', false, 'os.m05', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q031-o3')::uuid, qid, 'Neither', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q032')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.paging', 'What does the TLB cache?', 0.3, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.paging', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q032-o0')::uuid, qid, 'Recently used data blocks', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q032-o1')::uuid, qid, 'Recent page-number to frame-number translations', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q032-o2')::uuid, qid, 'Free frame lists', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q032-o3')::uuid, qid, 'Disk sectors', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q033')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.virtual_memory', 'What is thrashing?', 0.4, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.virtual_memory', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q033-o0')::uuid, qid, 'A failing disk drive', false, 'os.m07', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q033-o1')::uuid, qid, 'Spending more time paging than executing', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q033-o2')::uuid, qid, 'A deadlock in the page table', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q033-o3')::uuid, qid, 'Excessive context switching', false, 'os.m07', 3) on conflict (option_id) do nothing;

  qid := md5('x2-q034')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.page_replacement', 'Which algorithm can exhibit Belady anomaly?', 0.6, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.page_replacement', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q034-o0')::uuid, qid, 'LRU', false, 'os.m06', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q034-o1')::uuid, qid, 'FIFO', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q034-o2')::uuid, qid, 'Optimal', false, 'os.m06', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q034-o3')::uuid, qid, 'Clock', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q035')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.page_replacement', 'What does the optimal page replacement algorithm require?', 0.5, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.page_replacement', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q035-o0')::uuid, qid, 'The least recently used page', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q035-o1')::uuid, qid, 'Knowledge of future references', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q035-o2')::uuid, qid, 'A larger TLB', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q035-o3')::uuid, qid, 'More frames', false, 'os.m06', 3) on conflict (option_id) do nothing;

  qid := md5('x2-q036')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.filesystem', 'What does an inode store?', 0.1, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.filesystem', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q036-o0')::uuid, qid, 'The file name', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q036-o1')::uuid, qid, 'File metadata and pointers to data blocks', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q036-o2')::uuid, qid, 'The directory tree', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q036-o3')::uuid, qid, 'The file contents only', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q037')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.hashing', 'What is the worst-case lookup time in a hash table with chaining?', 0.4, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.hashing', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q037-o0')::uuid, qid, 'O(1) always', false, 'dsa.m08', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q037-o1')::uuid, qid, 'O(n)', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q037-o2')::uuid, qid, 'O(log n)', false, 'dsa.m08', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q037-o3')::uuid, qid, 'O(n log n)', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q038')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.hashing', 'What is a load factor in a hash table?', 0.0, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.hashing', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q038-o0')::uuid, qid, 'The number of collisions', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q038-o1')::uuid, qid, 'Entries divided by buckets', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q038-o2')::uuid, qid, 'The size of each key', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q038-o3')::uuid, qid, 'The rehash threshold only', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q039')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.two_pointers', 'On which kind of input does the two-pointer technique for pair sums require sorted data?', 0.2, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.two_pointers', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q039-o0')::uuid, qid, 'Only on linked lists', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q039-o1')::uuid, qid, 'On arrays where pointers converge from both ends', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q039-o2')::uuid, qid, 'Never', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q039-o3')::uuid, qid, 'Only on trees', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q040')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.sliding_window', 'Why does the shrinking sliding window fail on arrays containing negatives?', 0.7, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.sliding_window', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q040-o0')::uuid, qid, 'Negatives cannot be summed', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q040-o1')::uuid, qid, 'The window sum is no longer monotonic as the window grows', true, 'dsa.m09', 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q040-o2')::uuid, qid, 'It becomes O(n^2)', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q040-o3')::uuid, qid, 'It requires sorting first', false, 'dsa.m09', 3) on conflict (option_id) do nothing;

  qid := md5('x2-q041')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.dp_1d', 'What distinguishes memoization from tabulation?', 0.3, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.dp_1d', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q041-o0')::uuid, qid, 'Nothing, they are the same', false, 'dsa.m10', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q041-o1')::uuid, qid, 'Memoization is top-down recursive; tabulation is bottom-up iterative', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q041-o2')::uuid, qid, 'Memoization uses less memory always', false, 'dsa.m10', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q041-o3')::uuid, qid, 'Tabulation cannot handle overlapping subproblems', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q042')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.dp_1d', 'What are the two properties a problem needs for dynamic programming?', 0.4, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.dp_1d', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q042-o0')::uuid, qid, 'Sorting and searching', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q042-o1')::uuid, qid, 'Optimal substructure and overlapping subproblems', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q042-o2')::uuid, qid, 'Recursion and iteration', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q042-o3')::uuid, qid, 'Greedy choice and sorting', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q043')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.trees', 'What is the height of a complete binary tree with n nodes?', 0.3, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.trees', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q043-o0')::uuid, qid, 'O(n)', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q043-o1')::uuid, qid, 'O(log n)', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q043-o2')::uuid, qid, 'O(n log n)', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q043-o3')::uuid, qid, 'O(1)', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q044')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.bst', 'What is the worst-case time for search in an unbalanced BST?', 0.2, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.bst', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q044-o0')::uuid, qid, 'O(log n)', false, 'dsa.m11', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q044-o1')::uuid, qid, 'O(n)', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q044-o2')::uuid, qid, 'O(1)', false, 'dsa.m11', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q044-o3')::uuid, qid, 'O(n log n)', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q045')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.bst', 'An in-order traversal of a BST produces what?', -0.4, 35, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.bst', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q045-o0')::uuid, qid, 'Nodes in insertion order', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q045-o1')::uuid, qid, 'Nodes in sorted ascending order', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q045-o2')::uuid, qid, 'Nodes in reverse order', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q045-o3')::uuid, qid, 'Nodes level by level', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q046')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.transactions', 'What does the I in ACID stand for?', -0.8, 25, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.transactions', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q046-o0')::uuid, qid, 'Integrity', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q046-o1')::uuid, qid, 'Isolation', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q046-o2')::uuid, qid, 'Indexing', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q046-o3')::uuid, qid, 'Immutability', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q047')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.transactions', 'Which anomaly does READ COMMITTED still permit?', 0.6, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.transactions', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q047-o0')::uuid, qid, 'Dirty reads', false, 'dbms.m06', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q047-o1')::uuid, qid, 'Non-repeatable reads', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q047-o2')::uuid, qid, 'None of them', false, 'dbms.m06', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q047-o3')::uuid, qid, 'Lost updates only', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q048')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.indexing', 'When is an index likely to be ignored by the query planner?', 0.5, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.indexing', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q048-o0')::uuid, qid, 'When the table is small or selectivity is poor', true, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q048-o1')::uuid, qid, 'When the column is a primary key', false, 'dbms.m07', 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q048-o2')::uuid, qid, 'When the table has many rows', false, 'dbms.m07', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q048-o3')::uuid, qid, 'When the index is unique', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q049')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.indexing', 'What is the main cost of adding an index?', 0.3, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.indexing', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q049-o0')::uuid, qid, 'Slower reads', false, 'dbms.m07', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q049-o1')::uuid, qid, 'Slower writes and extra storage', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q049-o2')::uuid, qid, 'Loss of referential integrity', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q049-o3')::uuid, qid, 'It breaks joins', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q050')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.bcnf', 'When does a relation in 3NF fail to be in BCNF?', 0.8, 60, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.bcnf', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q050-o0')::uuid, qid, 'When it has a single candidate key', false, 'dbms.m08', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q050-o1')::uuid, qid, 'When a non-trivial FD has a determinant that is not a superkey', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q050-o2')::uuid, qid, 'Never; they are equivalent', false, 'dbms.m08', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q050-o3')::uuid, qid, 'When it has no foreign keys', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q051')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.sql_aggregate', 'Which clause filters rows AFTER grouping?', 0.0, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.sql_aggregate', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q051-o0')::uuid, qid, 'WHERE', false, 'dbms.m09', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q051-o1')::uuid, qid, 'HAVING', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q051-o2')::uuid, qid, 'ORDER BY', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q051-o3')::uuid, qid, 'LIMIT', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q052')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.sql_aggregate', 'What does COUNT(column) ignore that COUNT(*) does not?', 0.3, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.sql_aggregate', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q052-o0')::uuid, qid, 'Duplicate values', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q052-o1')::uuid, qid, 'NULL values in that column', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q052-o2')::uuid, qid, 'Zero values', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q052-o3')::uuid, qid, 'Empty strings', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q053')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.sql_aggregate', 'A query groups by department and selects employee_name without aggregation. What happens in strict SQL?', 0.5, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.sql_aggregate', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q053-o0')::uuid, qid, 'It returns the first name per group', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q053-o1')::uuid, qid, 'It is rejected because the column is neither grouped nor aggregated', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q053-o2')::uuid, qid, 'It returns NULL', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q053-o3')::uuid, qid, 'It groups by name too', false, 'dbms.m09', 3) on conflict (option_id) do nothing;

end $$;

-- Language column, so the editor can state what it executes.
alter table coding_problems add column if not exists language_label text not null default 'JavaScript';

-- Fix the existing rows: standard SQL literals stored a literal backslash-n.
update coding_problems set starter_code = replace(starter_code, '\n', chr(10)) where starter_code like '%\n%';

-- New problems. E-strings interpret \n as a real newline.
insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, language, language_label) values
  ('cp.reverse_string', 'dsa.arrays', 'Reverse a String', 'Return the input string reversed.', E'function solve(s) {
  // your code here
}', -0.8, 'javascript', 'JavaScript')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.reverse_string', '["hello"]', '"olleh"', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.reverse_string' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.reverse_string', '["a"]', '"a"', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.reverse_string' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.reverse_string', '[""]', '""', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.reverse_string' and ordinal=2);

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, language, language_label) values
  ('cp.max_subarray', 'dsa.dp_1d', 'Maximum Subarray', 'Return the largest sum of any contiguous subarray. Kadane algorithm runs in O(n).', E'function solve(nums) {
  // your code here
}', 0.4, 'javascript', 'JavaScript')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.max_subarray', '[[-2,1,-3,4,-1,2,1,-5,4]]', '6', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.max_subarray' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.max_subarray', '[[1]]', '1', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.max_subarray' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.max_subarray', '[[-1,-2,-3]]', '-1', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.max_subarray' and ordinal=2);

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, language, language_label) values
  ('cp.valid_parens', 'dsa.recursion', 'Valid Parentheses', 'Return true if every bracket in s is closed by the same type in the correct order.', E'function solve(s) {
  // your code here
}', 0.0, 'javascript', 'JavaScript')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.valid_parens', '["()[]{}"]', 'true', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.valid_parens' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.valid_parens', '["(]"]', 'false', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.valid_parens' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.valid_parens', '["([)]"]', 'false', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.valid_parens' and ordinal=2);

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, language, language_label) values
  ('cp.first_unique', 'dsa.hashing', 'First Unique Character', 'Return the index of the first non-repeating character in s, or -1 if none exists.', E'function solve(s) {
  // your code here
}', 0.1, 'javascript', 'JavaScript')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.first_unique', '["leetcode"]', '0', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.first_unique' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.first_unique', '["loveleetcode"]', '2', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.first_unique' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.first_unique', '["aabb"]', '-1', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.first_unique' and ordinal=2);

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, language, language_label) values
  ('cp.move_zeroes', 'dsa.two_pointers', 'Move Zeroes', 'Move all zeroes to the end of nums while keeping the relative order of the other elements. Return the array.', E'function solve(nums) {
  // your code here
}', 0.0, 'javascript', 'JavaScript')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.move_zeroes', '[[0,1,0,3,12]]', '[1,3,12,0,0]', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.move_zeroes' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.move_zeroes', '[[0]]', '[0]', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.move_zeroes' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.move_zeroes', '[[1,2,3]]', '[1,2,3]', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.move_zeroes' and ordinal=2);

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, language, language_label) values
  ('cp.max_window_sum', 'dsa.sliding_window', 'Maximum Window Sum', 'Return the maximum sum of any contiguous subarray of exactly length k.', E'function solve(nums, k) {
  // your code here
}', 0.3, 'javascript', 'JavaScript')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.max_window_sum', '[[2,1,5,1,3,2],3]', '9', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.max_window_sum' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.max_window_sum', '[[1,2],2]', '3', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.max_window_sum' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.max_window_sum', '[[5,5,5],1]', '5', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.max_window_sum' and ordinal=2);

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, language, language_label) values
  ('cp.fib_memo', 'dsa.dp_1d', 'Fibonacci with Memoization', 'Return the nth Fibonacci number with fib(0)=0 and fib(1)=1. Naive recursion will time out for large n.', E'function solve(n) {
  // your code here
}', 0.2, 'javascript', 'JavaScript')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.fib_memo', '[10]', '55', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.fib_memo' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.fib_memo', '[0]', '0', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.fib_memo' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.fib_memo', '[30]', '832040', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.fib_memo' and ordinal=2);

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, language, language_label) values
  ('cp.merge_sorted', 'dsa.sorting', 'Merge Two Sorted Arrays', 'Merge two sorted arrays into one sorted array. Do it in O(n+m) without calling sort.', E'function solve(a, b) {
  // your code here
}', 0.1, 'javascript', 'JavaScript')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.merge_sorted', '[[1,3,5],[2,4,6]]', '[1,2,3,4,5,6]', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.merge_sorted' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.merge_sorted', '[[],[1]]', '[1]', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.merge_sorted' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.merge_sorted', '[[1,1],[1]]', '[1,1,1]', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.merge_sorted' and ordinal=2);

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, language, language_label) values
  ('cp.bst_valid', 'dsa.bst', 'Validate BST Array', 'Given the in-order traversal of a tree as an array, return true if it could come from a valid BST (strictly increasing).', E'function solve(inorder) {
  // your code here
}', 0.3, 'javascript', 'JavaScript')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.bst_valid', '[[1,2,3,4]]', 'true', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.bst_valid' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.bst_valid', '[[1,3,2]]', 'false', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.bst_valid' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.bst_valid', '[[5]]', 'true', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.bst_valid' and ordinal=2);
'@

Write-ProjectFile 'supabase\migrations\005_multi_language.sql' @'
-- =====================================================================
-- 005_multi_language.sql
-- Per-language starter code, so the editor can offer a real choice.
-- JavaScript runs in-browser via Function; Python runs via Pyodide,
-- loaded on demand from a CDN the first time it is selected.
-- Idempotent.
-- =====================================================================

create table if not exists problem_starters (
  problem_id   text not null references coding_problems(problem_id) on delete cascade,
  language     text not null,          -- javascript | python
  label        text not null,          -- JavaScript | Python
  starter_code text not null,
  is_runnable  boolean not null default true,
  primary key (problem_id, language)
);

alter table problem_starters enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'problem_starters') then
    create policy read_starters on problem_starters for select to authenticated using (true);
  end if;
end $$;

-- JavaScript starters come from the existing rows.
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
select problem_id, 'javascript', 'JavaScript',
       replace(starter_code, '\n', chr(10)), true
  from coding_problems
on conflict (problem_id, language) do nothing;

-- Python starters.
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.two_sum', 'python', 'Python', E'def solve(nums, target):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.two_sum')
on conflict (problem_id, language) do nothing;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.binary_search', 'python', 'Python', E'def solve(nums, target):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.binary_search')
on conflict (problem_id, language) do nothing;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.kth_largest', 'python', 'Python', E'def solve(nums, k):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.kth_largest')
on conflict (problem_id, language) do nothing;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.reverse_string', 'python', 'Python', E'def solve(s):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.reverse_string')
on conflict (problem_id, language) do nothing;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.max_subarray', 'python', 'Python', E'def solve(nums):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.max_subarray')
on conflict (problem_id, language) do nothing;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.valid_parens', 'python', 'Python', E'def solve(s):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.valid_parens')
on conflict (problem_id, language) do nothing;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.first_unique', 'python', 'Python', E'def solve(s):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.first_unique')
on conflict (problem_id, language) do nothing;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.move_zeroes', 'python', 'Python', E'def solve(nums):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.move_zeroes')
on conflict (problem_id, language) do nothing;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.max_window_sum', 'python', 'Python', E'def solve(nums, k):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.max_window_sum')
on conflict (problem_id, language) do nothing;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.fib_memo', 'python', 'Python', E'def solve(n):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.fib_memo')
on conflict (problem_id, language) do nothing;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.merge_sorted', 'python', 'Python', E'def solve(a, b):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.merge_sorted')
on conflict (problem_id, language) do nothing;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.bst_valid', 'python', 'Python', E'def solve(inorder):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.bst_valid')
on conflict (problem_id, language) do nothing;

-- Repair any remaining literal backslash-n.
update problem_starters set starter_code = replace(starter_code, '\n', chr(10))
  where starter_code like '%\n%';
'@

Write-ProjectFile 'supabase\migrations\006_cpp_java.sql' @'
-- =====================================================================
-- 006_cpp_java.sql
-- Replaces JavaScript with C++ and Java, the languages actually used in
-- placement rounds. Python stays because it runs client-side via Pyodide
-- and therefore still works without a network connection.
--
-- C++ and Java execute through a remote judge, so each problem now
-- carries a type signature the harness generator uses to build main().
-- Idempotent.
-- =====================================================================

alter table coding_problems add column if not exists signature text;

-- Type signatures, used to generate the driver for compiled languages.
update coding_problems set signature = 'ints,int->ints' where problem_id = 'cp.two_sum';
update coding_problems set signature = 'ints,int->int' where problem_id = 'cp.binary_search';
update coding_problems set signature = 'ints,int->int' where problem_id = 'cp.kth_largest';
update coding_problems set signature = 'str->str' where problem_id = 'cp.reverse_string';
update coding_problems set signature = 'ints->int' where problem_id = 'cp.max_subarray';
update coding_problems set signature = 'str->bool' where problem_id = 'cp.valid_parens';
update coding_problems set signature = 'str->int' where problem_id = 'cp.first_unique';
update coding_problems set signature = 'ints->ints' where problem_id = 'cp.move_zeroes';
update coding_problems set signature = 'ints,int->int' where problem_id = 'cp.max_window_sum';
update coding_problems set signature = 'int->int' where problem_id = 'cp.fib_memo';
update coding_problems set signature = 'ints,ints->ints' where problem_id = 'cp.merge_sorted';
update coding_problems set signature = 'ints->bool' where problem_id = 'cp.bst_valid';

-- JavaScript is no longer offered.
delete from problem_starters where language = 'javascript';

insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.two_sum', 'cpp', 'C++', E'vector<int> solve(vector<int>& nums, int target) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.two_sum')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.two_sum', 'java', 'Java', E'static int[] solve(int[] nums, int target) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.two_sum')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.two_sum', 'python', 'Python', E'def solve(nums, target):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.two_sum')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;

insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.binary_search', 'cpp', 'C++', E'int solve(vector<int>& nums, int target) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.binary_search')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.binary_search', 'java', 'Java', E'static int solve(int[] nums, int target) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.binary_search')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.binary_search', 'python', 'Python', E'def solve(nums, target):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.binary_search')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;

insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.kth_largest', 'cpp', 'C++', E'int solve(vector<int>& nums, int k) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.kth_largest')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.kth_largest', 'java', 'Java', E'static int solve(int[] nums, int k) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.kth_largest')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.kth_largest', 'python', 'Python', E'def solve(nums, k):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.kth_largest')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;

insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.reverse_string', 'cpp', 'C++', E'string solve(string& s) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.reverse_string')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.reverse_string', 'java', 'Java', E'static String solve(String s) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.reverse_string')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.reverse_string', 'python', 'Python', E'def solve(s):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.reverse_string')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;

insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.max_subarray', 'cpp', 'C++', E'int solve(vector<int>& nums) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.max_subarray')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.max_subarray', 'java', 'Java', E'static int solve(int[] nums) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.max_subarray')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.max_subarray', 'python', 'Python', E'def solve(nums):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.max_subarray')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;

insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.valid_parens', 'cpp', 'C++', E'bool solve(string& s) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.valid_parens')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.valid_parens', 'java', 'Java', E'static boolean solve(String s) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.valid_parens')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.valid_parens', 'python', 'Python', E'def solve(s):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.valid_parens')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;

insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.first_unique', 'cpp', 'C++', E'int solve(string& s) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.first_unique')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.first_unique', 'java', 'Java', E'static int solve(String s) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.first_unique')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.first_unique', 'python', 'Python', E'def solve(s):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.first_unique')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;

insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.move_zeroes', 'cpp', 'C++', E'vector<int> solve(vector<int>& nums) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.move_zeroes')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.move_zeroes', 'java', 'Java', E'static int[] solve(int[] nums) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.move_zeroes')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.move_zeroes', 'python', 'Python', E'def solve(nums):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.move_zeroes')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;

insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.max_window_sum', 'cpp', 'C++', E'int solve(vector<int>& nums, int k) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.max_window_sum')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.max_window_sum', 'java', 'Java', E'static int solve(int[] nums, int k) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.max_window_sum')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.max_window_sum', 'python', 'Python', E'def solve(nums, k):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.max_window_sum')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;

insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.fib_memo', 'cpp', 'C++', E'int solve(int n) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.fib_memo')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.fib_memo', 'java', 'Java', E'static int solve(int n) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.fib_memo')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.fib_memo', 'python', 'Python', E'def solve(n):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.fib_memo')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;

insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.merge_sorted', 'cpp', 'C++', E'vector<int> solve(vector<int>& a, vector<int>& b) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.merge_sorted')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.merge_sorted', 'java', 'Java', E'static int[] solve(int[] a, int[] b) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.merge_sorted')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.merge_sorted', 'python', 'Python', E'def solve(a, b):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.merge_sorted')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;

insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.bst_valid', 'cpp', 'C++', E'bool solve(vector<int>& inorder) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.bst_valid')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.bst_valid', 'java', 'Java', E'static boolean solve(int[] inorder) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.bst_valid')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.bst_valid', 'python', 'Python', E'def solve(inorder):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.bst_valid')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;

update coding_problems set language = 'cpp', language_label = 'C++';
'@

Write-ProjectFile 'supabase\migrations\007_content_expansion_2.sql' @'
-- =====================================================================
-- 007_content_expansion_2.sql
-- Aptitude and logical reasoning (placement-critical), plus more depth
-- across the existing subjects. +16 concepts, +14 edges,
-- +11 misconceptions, +59 questions, +12 coding problems.
-- Idempotent.
-- =====================================================================

insert into subjects (subject_id, name, description, is_authored) values
  ('apt', 'Quantitative Aptitude', 'Number systems through probability', true),
  ('lr', 'Logical Reasoning', 'Series through data sufficiency', true)
on conflict (subject_id) do nothing;

insert into concepts (concept_id, subject_id, name, level) values
  ('apt.number_system', 'apt', 'Number systems', 0),
  ('apt.percentages', 'apt', 'Percentages', 0),
  ('apt.ratios', 'apt', 'Ratio and proportion', 1),
  ('apt.averages', 'apt', 'Averages', 1),
  ('apt.profit_loss', 'apt', 'Profit and loss', 2),
  ('apt.si_ci', 'apt', 'Simple and compound interest', 2),
  ('apt.time_work', 'apt', 'Time and work', 2),
  ('apt.time_speed', 'apt', 'Time speed distance', 2),
  ('apt.permutations', 'apt', 'Permutations and combinations', 3),
  ('apt.probability', 'apt', 'Probability', 4),
  ('lr.series', 'lr', 'Number and letter series', 0),
  ('lr.coding', 'lr', 'Coding decoding', 1),
  ('lr.blood_relations', 'lr', 'Blood relations', 1),
  ('lr.syllogism', 'lr', 'Syllogisms', 2),
  ('lr.seating', 'lr', 'Seating arrangement', 3),
  ('lr.data_suff', 'lr', 'Data sufficiency', 3)
on conflict (concept_id) do nothing;

insert into prerequisites (parent_id, child_id, weight) values
  ('apt.number_system', 'apt.percentages', 0.6),
  ('apt.percentages', 'apt.ratios', 0.7),
  ('apt.ratios', 'apt.averages', 0.6),
  ('apt.percentages', 'apt.profit_loss', 0.9),
  ('apt.percentages', 'apt.si_ci', 0.85),
  ('apt.ratios', 'apt.time_work', 0.8),
  ('apt.ratios', 'apt.time_speed', 0.8),
  ('apt.number_system', 'apt.permutations', 0.7),
  ('apt.permutations', 'apt.probability', 0.9),
  ('lr.series', 'lr.coding', 0.5),
  ('lr.series', 'lr.blood_relations', 0.4),
  ('lr.coding', 'lr.syllogism', 0.4),
  ('lr.blood_relations', 'lr.seating', 0.6),
  ('lr.syllogism', 'lr.data_suff', 0.6)
on conflict (parent_id, child_id) do nothing;

insert into misconceptions (misconception_id, concept_id, label, remediation_note) values
  ('apt.m01', 'apt.percentages', 'Treats successive percentage changes as additive', '20% up then 20% down is not zero; it is a 4% net loss.'),
  ('apt.m02', 'apt.profit_loss', 'Computes profit percent on selling price', 'Profit percent is always on cost price unless stated otherwise.'),
  ('apt.m03', 'apt.si_ci', 'Applies the simple interest formula to compound problems', 'CI compounds on the accumulated amount, not the principal alone.'),
  ('apt.m04', 'apt.time_work', 'Adds days instead of adding rates', 'Two people finishing in 6 and 12 days work at 1/6 + 1/12 per day.'),
  ('apt.m05', 'apt.time_speed', 'Averages two speeds arithmetically', 'Equal distances need the harmonic mean, not the arithmetic mean.'),
  ('apt.m06', 'apt.permutations', 'Confuses permutation with combination', 'Order matters in a permutation and does not in a combination.'),
  ('apt.m07', 'apt.probability', 'Adds probabilities of non-mutually-exclusive events', 'P(A or B) needs the intersection subtracted.'),
  ('apt.m08', 'apt.averages', 'Averages the averages of unequal groups', 'Weight by group size, or the result is wrong.'),
  ('lr.m01', 'lr.syllogism', 'Accepts a conclusion that only seems plausible', 'Only what follows necessarily from the premises counts.'),
  ('lr.m02', 'lr.blood_relations', 'Assumes gender from a relation word', 'Cousin, child and spouse do not fix gender.'),
  ('lr.m03', 'lr.data_suff', 'Solves the problem instead of testing sufficiency', 'The question is whether the data suffices, not what the answer is.')
on conflict (misconception_id) do nothing;

insert into bkt_params (concept_id, p_init, p_transit, p_slip, p_guess)
select concept_id, 0.15, 0.15, 0.10, 0.25 from concepts
on conflict (concept_id) do nothing;

do $$
declare qid uuid;
begin
  qid := md5('x3-q001')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.percentages', 'A price rises 20% then falls 20%. What is the net change?', 0.2, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.percentages', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q001-o0')::uuid, qid, 'No change', false, 'apt.m01', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q001-o1')::uuid, qid, '4% decrease', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q001-o2')::uuid, qid, '4% increase', false, 'apt.m01', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q001-o3')::uuid, qid, '40% decrease', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q002')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.percentages', 'If 40% of a number is 96, what is the number?', -0.6, 35, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.percentages', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q002-o0')::uuid, qid, '240', true, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q002-o1')::uuid, qid, '38.4', false, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q002-o2')::uuid, qid, '384', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q002-o3')::uuid, qid, '120', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q003')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.percentages', 'A student scores 60 out of 80. What percentage is that?', -1.0, 25, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.percentages', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q003-o0')::uuid, qid, '80%', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q003-o1')::uuid, qid, '75%', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q003-o2')::uuid, qid, '70%', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q003-o3')::uuid, qid, '65%', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q004')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.profit_loss', 'An item costs 400 and sells for 500. What is the profit percent?', -0.3, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.profit_loss', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q004-o0')::uuid, qid, '20%', false, 'apt.m02', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q004-o1')::uuid, qid, '25%', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q004-o2')::uuid, qid, 'ADD 100%', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q004-o3')::uuid, qid, '80%', false, 'apt.m02', 3) on conflict (option_id) do nothing;

  qid := md5('x3-q005')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.profit_loss', 'A shopkeeper sells at 10% loss. If cost is 250, what is the selling price?', -0.2, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.profit_loss', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q005-o0')::uuid, qid, '275', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q005-o1')::uuid, qid, '225', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q005-o2')::uuid, qid, '240', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q005-o3')::uuid, qid, '230', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q006')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.profit_loss', 'Two articles are sold at 1200 each, one at 20% profit and one at 20% loss. What is the net result?', 0.7, 70, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.profit_loss', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q006-o0')::uuid, qid, 'No profit no loss', false, 'apt.m01', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q006-o1')::uuid, qid, 'Loss of 100', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q006-o2')::uuid, qid, 'Profit of 100', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q006-o3')::uuid, qid, 'Loss of 200', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q007')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.si_ci', 'What is the simple interest on 5000 at 8% for 3 years?', -0.5, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.si_ci', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q007-o0')::uuid, qid, '1200', true, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q007-o1')::uuid, qid, '1300', false, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q007-o2')::uuid, qid, '400', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q007-o3')::uuid, qid, '1500', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q008')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.si_ci', 'What is the compound interest on 10000 at 10% for 2 years?', 0.3, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.si_ci', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q008-o0')::uuid, qid, '2000', false, 'apt.m03', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q008-o1')::uuid, qid, '2100', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q008-o2')::uuid, qid, '1000', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q008-o3')::uuid, qid, '2200', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q009')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.si_ci', 'At what rate does a sum double in 8 years under simple interest?', 0.4, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.si_ci', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q009-o0')::uuid, qid, '8%', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q009-o1')::uuid, qid, '12.5%', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q009-o2')::uuid, qid, '10%', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q009-o3')::uuid, qid, '16%', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q010')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.time_work', 'A finishes a job in 6 days, B in 12. Working together, how long?', 0.0, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.time_work', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q010-o0')::uuid, qid, '18 days', false, 'apt.m04', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q010-o1')::uuid, qid, '4 days', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q010-o2')::uuid, qid, '9 days', false, 'apt.m04', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q010-o3')::uuid, qid, '3 days', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q011')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.time_work', '12 workers finish a task in 10 days. How long for 15 workers?', 0.1, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.time_work', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q011-o0')::uuid, qid, '12.5 days', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q011-o1')::uuid, qid, '8 days', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q011-o2')::uuid, qid, '7 days', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q011-o3')::uuid, qid, '6 days', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q012')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.time_speed', 'A car covers half a journey at 40 kmph and half at 60 kmph. What is the average speed?', 0.5, 60, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.time_speed', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q012-o0')::uuid, qid, '50 kmph', false, 'apt.m05', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q012-o1')::uuid, qid, '48 kmph', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q012-o2')::uuid, qid, '45 kmph', false, 'apt.m05', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q012-o3')::uuid, qid, '52 kmph', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q013')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.time_speed', 'A train 200m long crosses a pole in 10 seconds. What is its speed?', 0.1, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.time_speed', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q013-o0')::uuid, qid, '20 m/s', true, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q013-o1')::uuid, qid, '10 m/s', false, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q013-o2')::uuid, qid, '40 m/s', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q013-o3')::uuid, qid, '2 m/s', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q014')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.time_speed', 'Two trains 120m and 180m long move toward each other at 20 and 30 m/s. Time to cross?', 0.6, 65, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.time_speed', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q014-o0')::uuid, qid, '10 s', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q014-o1')::uuid, qid, '6 s', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q014-o2')::uuid, qid, '12 s', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q014-o3')::uuid, qid, '5 s', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q015')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.averages', 'The average of 5 numbers is 20. If one number 30 is removed, what is the new average?', 0.2, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.averages', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q015-o0')::uuid, qid, '20', false, 'apt.m08', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q015-o1')::uuid, qid, '17.5', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q015-o2')::uuid, qid, '15', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q015-o3')::uuid, qid, '22.5', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q016')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.averages', 'Class A has 20 students averaging 60, class B has 30 averaging 70. Combined average?', 0.4, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.averages', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q016-o0')::uuid, qid, '65', false, 'apt.m08', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q016-o1')::uuid, qid, '66', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q016-o2')::uuid, qid, '64', false, 'apt.m08', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q016-o3')::uuid, qid, '68', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q017')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.ratios', 'If a:b = 2:3 and b:c = 4:5, what is a:c?', 0.3, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.ratios', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q017-o0')::uuid, qid, '2:5', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q017-o1')::uuid, qid, '8:15', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q017-o2')::uuid, qid, '6:5', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q017-o3')::uuid, qid, '1:2', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q018')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.ratios', 'Divide 600 between two people in the ratio 2:3. What is the larger share?', -0.4, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.ratios', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q018-o0')::uuid, qid, '240', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q018-o1')::uuid, qid, '360', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q018-o2')::uuid, qid, '300', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q018-o3')::uuid, qid, '400', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q019')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.number_system', 'What is the remainder when 2^10 is divided by 7?', 0.6, 60, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.number_system', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q019-o0')::uuid, qid, '1', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q019-o1')::uuid, qid, '2', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q019-o2')::uuid, qid, '4', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q019-o3')::uuid, qid, '0', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q020')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.number_system', 'How many factors does 36 have?', 0.2, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.number_system', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q020-o0')::uuid, qid, '6', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q020-o1')::uuid, qid, '9', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q020-o2')::uuid, qid, '12', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q020-o3')::uuid, qid, '8', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q021')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.number_system', 'What is the LCM of 12 and 18?', -0.6, 35, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.number_system', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q021-o0')::uuid, qid, '6', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q021-o1')::uuid, qid, '36', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q021-o2')::uuid, qid, '72', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q021-o3')::uuid, qid, '216', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q022')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.permutations', 'How many ways can 5 people be seated in a row?', -0.2, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.permutations', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q022-o0')::uuid, qid, '25', false, 'apt.m06', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q022-o1')::uuid, qid, '120', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q022-o2')::uuid, qid, '5', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q022-o3')::uuid, qid, '10', false, 'apt.m06', 3) on conflict (option_id) do nothing;

  qid := md5('x3-q023')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.permutations', 'How many ways can 3 people be chosen from 8?', 0.2, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.permutations', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q023-o0')::uuid, qid, '336', false, 'apt.m06', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q023-o1')::uuid, qid, '56', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q023-o2')::uuid, qid, '24', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q023-o3')::uuid, qid, '512', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q024')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.permutations', 'How many 3-letter words can be formed from the letters of DELHI without repetition?', 0.4, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.permutations', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q024-o0')::uuid, qid, '10', false, 'apt.m06', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q024-o1')::uuid, qid, '60', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q024-o2')::uuid, qid, '125', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q024-o3')::uuid, qid, '15', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q025')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.probability', 'Two dice are rolled. What is the probability the sum is 7?', 0.3, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.probability', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q025-o0')::uuid, qid, '1/12', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q025-o1')::uuid, qid, '1/6', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q025-o2')::uuid, qid, '7/36', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q025-o3')::uuid, qid, '1/9', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q026')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.probability', 'A card is drawn from a standard deck. P(king or heart)?', 0.5, 60, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.probability', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q026-o0')::uuid, qid, '17/52', false, 'apt.m07', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q026-o1')::uuid, qid, '16/52', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q026-o2')::uuid, qid, '13/52', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q026-o3')::uuid, qid, '4/52', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q027')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.probability', 'A bag has 3 red and 5 blue balls. Two are drawn without replacement. P(both red)?', 0.6, 65, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.probability', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q027-o0')::uuid, qid, '9/64', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q027-o1')::uuid, qid, '3/28', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q027-o2')::uuid, qid, '1/4', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q027-o3')::uuid, qid, '6/56', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q028')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'lr.series', 'What comes next: 2, 6, 12, 20, 30, ?', 0.1, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'lr.series', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q028-o0')::uuid, qid, '40', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q028-o1')::uuid, qid, '42', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q028-o2')::uuid, qid, '36', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q028-o3')::uuid, qid, '44', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q029')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'lr.series', 'What comes next: 1, 4, 9, 16, 25, ?', -0.7, 30, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'lr.series', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q029-o0')::uuid, qid, '30', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q029-o1')::uuid, qid, '36', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q029-o2')::uuid, qid, '35', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q029-o3')::uuid, qid, '49', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q030')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'lr.series', 'What comes next: A, C, F, J, ?', 0.5, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'lr.series', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q030-o0')::uuid, qid, 'M', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q030-o1')::uuid, qid, 'O', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q030-o2')::uuid, qid, 'N', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q030-o3')::uuid, qid, 'P', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q031')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'lr.coding', 'If CAT is coded as DBU, how is DOG coded?', 0.0, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'lr.coding', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q031-o0')::uuid, qid, 'EPH', true, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q031-o1')::uuid, qid, 'CNF', false, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q031-o2')::uuid, qid, 'EPI', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q031-o3')::uuid, qid, 'DPH', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q032')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'lr.coding', 'If MONDAY is 123456, what is DAY?', -0.2, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'lr.coding', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q032-o0')::uuid, qid, '456', true, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q032-o1')::uuid, qid, '465', false, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q032-o2')::uuid, qid, '546', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q032-o3')::uuid, qid, '654', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q033')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'lr.blood_relations', 'Pointing to a man, a woman says "his mother is the only daughter of my mother". How is she related to him?', 0.5, 65, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'lr.blood_relations', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q033-o0')::uuid, qid, 'Sister', false, 'lr.m02', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q033-o1')::uuid, qid, 'Mother', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q033-o2')::uuid, qid, 'Aunt', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q033-o3')::uuid, qid, 'Grandmother', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q034')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'lr.blood_relations', 'A is B brother. B is C mother. What is A to C?', 0.1, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'lr.blood_relations', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q034-o0')::uuid, qid, 'Father', false, 'lr.m02', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q034-o1')::uuid, qid, 'Uncle', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q034-o2')::uuid, qid, 'Brother', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q034-o3')::uuid, qid, 'Cannot be determined', false, 'lr.m02', 3) on conflict (option_id) do nothing;

  qid := md5('x3-q035')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'lr.syllogism', 'All cats are animals. Some animals are wild. Does it follow that some cats are wild?', 0.4, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'lr.syllogism', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q035-o0')::uuid, qid, 'Yes, it follows', false, 'lr.m01', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q035-o1')::uuid, qid, 'No, it does not follow', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q035-o2')::uuid, qid, 'Only if all animals are wild', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q035-o3')::uuid, qid, 'It follows probabilistically', false, 'lr.m01', 3) on conflict (option_id) do nothing;

  qid := md5('x3-q036')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'lr.syllogism', 'All roses are flowers. All flowers need water. Does it follow that all roses need water?', -0.3, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'lr.syllogism', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q036-o0')::uuid, qid, 'No', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q036-o1')::uuid, qid, 'Yes', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q036-o2')::uuid, qid, 'Only some roses', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q036-o3')::uuid, qid, 'Cannot be determined', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q037')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'lr.data_suff', 'Is x greater than 5? (1) x is greater than 3. (2) x squared equals 49.', 0.6, 70, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'lr.data_suff', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q037-o0')::uuid, qid, 'Statement 1 alone is sufficient', false, 'lr.m03', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q037-o1')::uuid, qid, 'Statement 2 alone is sufficient', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q037-o2')::uuid, qid, 'Both together are needed', false, 'lr.m03', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q037-o3')::uuid, qid, 'Neither is sufficient', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q038')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'lr.seating', 'Five people sit in a row. A is at one end, B is next to A. How many positions can C take?', 0.5, 60, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'lr.seating', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q038-o0')::uuid, qid, '2', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q038-o1')::uuid, qid, '3', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q038-o2')::uuid, qid, '4', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q038-o3')::uuid, qid, '1', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q039')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.transactions', 'What does a dirty read mean?', 0.4, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.transactions', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q039-o0')::uuid, qid, 'Reading from a corrupted disk', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q039-o1')::uuid, qid, 'Reading data written by an uncommitted transaction', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q039-o2')::uuid, qid, 'Reading the same row twice', false, 'dbms.m06', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q039-o3')::uuid, qid, 'Reading a deleted row', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q040')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.indexing', 'Which index structure suits range queries best?', 0.4, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.indexing', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q040-o0')::uuid, qid, 'Hash index', false, 'dbms.m07', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q040-o1')::uuid, qid, 'B+ tree index', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q040-o2')::uuid, qid, 'Bitmap index', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q040-o3')::uuid, qid, 'No index', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q041')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.joins', 'What does a CROSS JOIN of a 4-row and 3-row table return?', 0.2, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.joins', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q041-o0')::uuid, qid, '7 rows', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q041-o1')::uuid, qid, '12 rows', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q041-o2')::uuid, qid, '4 rows', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q041-o3')::uuid, qid, '3 rows', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q042')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.keys', 'What does a composite key mean?', -0.2, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.keys', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q042-o0')::uuid, qid, 'A key copied from another table', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q042-o1')::uuid, qid, 'A primary key made of two or more attributes', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q042-o2')::uuid, qid, 'A key that can be null', false, 'dbms.m02', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q042-o3')::uuid, qid, 'An index on two columns', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q043')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.sql_aggregate', 'What does GROUP BY do before HAVING runs?', 0.2, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.sql_aggregate', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q043-o0')::uuid, qid, 'Sorts the rows', false, 'dbms.m09', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q043-o1')::uuid, qid, 'Partitions rows into groups', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q043-o2')::uuid, qid, 'Filters individual rows', false, 'dbms.m09', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q043-o3')::uuid, qid, 'Joins the tables', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q044')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.hashing', 'What does open addressing resolve?', 0.3, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.hashing', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q044-o0')::uuid, qid, 'Slow hashing', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q044-o1')::uuid, qid, 'Collisions, without a separate chain', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q044-o2')::uuid, qid, 'Memory leaks', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q044-o3')::uuid, qid, 'Poor hash functions', false, 'dsa.m08', 3) on conflict (option_id) do nothing;

  qid := md5('x3-q045')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.dp_1d', 'What is the time complexity of the standard 0/1 knapsack DP?', 0.5, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.dp_1d', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q045-o0')::uuid, qid, 'O(n)', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q045-o1')::uuid, qid, 'O(n * W)', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q045-o2')::uuid, qid, 'O(2^n)', false, 'dsa.m10', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q045-o3')::uuid, qid, 'O(n log n)', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q046')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.trees', 'How many nodes at most can a binary tree of height h have?', 0.3, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.trees', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q046-o0')::uuid, qid, '2h', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q046-o1')::uuid, qid, '2^(h+1) - 1', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q046-o2')::uuid, qid, 'h^2', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q046-o3')::uuid, qid, '2^h', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q047')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.bst', 'What does deleting a node with two children in a BST require?', 0.5, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.bst', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q047-o0')::uuid, qid, 'Deleting the whole subtree', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q047-o1')::uuid, qid, 'Replacing it with its in-order successor', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q047-o2')::uuid, qid, 'Replacing it with its parent', false, 'dsa.m11', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q047-o3')::uuid, qid, 'Nothing, BSTs cannot delete', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q048')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.sliding_window', 'What is the time complexity of the fixed-size sliding window maximum using a deque?', 0.6, 60, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.sliding_window', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q048-o0')::uuid, qid, 'O(n*k)', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q048-o1')::uuid, qid, 'O(n)', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q048-o2')::uuid, qid, 'O(n log n)', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q048-o3')::uuid, qid, 'O(k^2)', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q049')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.two_pointers', 'In the container-with-most-water problem, which pointer should move?', 0.6, 60, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.two_pointers', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q049-o0')::uuid, qid, 'Always the left pointer', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q049-o1')::uuid, qid, 'The one at the shorter line', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q049-o2')::uuid, qid, 'Always the right pointer', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q049-o3')::uuid, qid, 'Both simultaneously', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q050')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.http', 'What is the main improvement of HTTP/2 over HTTP/1.1?', 0.4, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.http', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q050-o0')::uuid, qid, 'Encryption by default', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q050-o1')::uuid, qid, 'Multiplexing over one connection', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q050-o2')::uuid, qid, 'Statefulness', false, 'cn.m08', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q050-o3')::uuid, qid, 'Larger headers', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q051')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.tcp_basics', 'What is the purpose of the TCP sequence number?', 0.2, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.tcp_basics', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q051-o0')::uuid, qid, 'Identify the sender', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q051-o1')::uuid, qid, 'Order bytes and detect loss', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q051-o2')::uuid, qid, 'Encrypt the payload', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q051-o3')::uuid, qid, 'Select the port', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q052')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.routing', 'What is the difference between a router and a switch?', 0.1, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.routing', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q052-o0')::uuid, qid, 'None, they are the same', false, 'cn.m06', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q052-o1')::uuid, qid, 'A router forwards between networks; a switch within one', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q052-o2')::uuid, qid, 'A switch is faster only', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q052-o3')::uuid, qid, 'A router works at layer 2', false, 'cn.m06', 3) on conflict (option_id) do nothing;

  qid := md5('x3-q053')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.dns', 'What is DNS recursion?', 0.5, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.dns', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q053-o0')::uuid, qid, 'A domain pointing to itself', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q053-o1')::uuid, qid, 'A resolver querying other servers on the client behalf', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q053-o2')::uuid, qid, 'Caching a record twice', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q053-o3')::uuid, qid, 'A loop in the zone file', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q054')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.subnetting', 'How many /28 subnets fit inside a /24?', 0.6, 65, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.subnetting', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q054-o0')::uuid, qid, '4', false, 'cn.m01', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q054-o1')::uuid, qid, '16', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q054-o2')::uuid, qid, '8', false, 'cn.m01', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q054-o3')::uuid, qid, '32', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q055')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.scheduling', 'What is convoy effect in FCFS scheduling?', 0.5, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.scheduling', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q055-o0')::uuid, qid, 'Processes arriving together', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q055-o1')::uuid, qid, 'Short processes waiting behind one long process', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q055-o2')::uuid, qid, 'Deadlock between two processes', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q055-o3')::uuid, qid, 'Excessive context switching', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q056')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.sync', 'What problem does the producer-consumer pattern illustrate?', 0.3, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.sync', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q056-o0')::uuid, qid, 'CPU scheduling', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q056-o1')::uuid, qid, 'Bounded-buffer synchronization', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q056-o2')::uuid, qid, 'Memory paging', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q056-o3')::uuid, qid, 'Disk scheduling', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q057')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.memory', 'What is the difference between internal and external fragmentation?', 0.4, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.memory', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q057-o0')::uuid, qid, 'They are the same', false, 'os.m05', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q057-o1')::uuid, qid, 'Internal is unused space inside an allocation; external is between them', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q057-o2')::uuid, qid, 'Internal happens only in segmentation', false, 'os.m05', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q057-o3')::uuid, qid, 'External occurs only with paging', false, 'os.m05', 3) on conflict (option_id) do nothing;

  qid := md5('x3-q058')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.filesystem', 'What is a hard link?', 0.4, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.filesystem', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q058-o0')::uuid, qid, 'A shortcut file containing a path', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q058-o1')::uuid, qid, 'A second directory entry pointing at the same inode', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q058-o2')::uuid, qid, 'A backup copy', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q058-o3')::uuid, qid, 'A symbolic reference across filesystems', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q059')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.process', 'What does fork() return in the child process?', 0.3, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.process', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q059-o0')::uuid, qid, 'The child PID', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q059-o1')::uuid, qid, 'Zero', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q059-o2')::uuid, qid, 'Negative one', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q059-o3')::uuid, qid, 'The parent PID', false, null, 3) on conflict (option_id) do nothing;

end $$;

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, signature, language, language_label) values
  ('cp.fizzbuzz', 'apt.number_system', 'FizzBuzz Count', 'Return how many numbers from 1 to n are divisible by 3 or 5.', E'int solve(int n) {
    // your code here
}', -0.7, 'ints->int', 'cpp', 'C++')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.fizzbuzz', '[15]', '7', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.fizzbuzz' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.fizzbuzz', '[1]', '0', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.fizzbuzz' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.fizzbuzz', '[100]', '47', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.fizzbuzz' and ordinal=2);
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.fizzbuzz', 'cpp', 'C++', E'int solve(int n) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.fizzbuzz')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.fizzbuzz', 'java', 'Java', E'static int solve(int n) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.fizzbuzz')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.fizzbuzz', 'python', 'Python', E'def solve(n):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.fizzbuzz')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, signature, language, language_label) values
  ('cp.gcd', 'apt.number_system', 'Greatest Common Divisor', 'Return the GCD of a and b using the Euclidean algorithm.', E'int solve(int a, int b) {
    // your code here
}', -0.4, 'int,int->int', 'cpp', 'C++')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.gcd', '[12,18]', '6', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.gcd' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.gcd', '[7,13]', '1', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.gcd' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.gcd', '[100,75]', '25', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.gcd' and ordinal=2);
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.gcd', 'cpp', 'C++', E'int solve(int a, int b) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.gcd')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.gcd', 'java', 'Java', E'static int solve(int a, int b) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.gcd')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.gcd', 'python', 'Python', E'def solve(a, b):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.gcd')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, signature, language, language_label) values
  ('cp.prime_count', 'apt.number_system', 'Count Primes', 'Return how many primes are strictly less than n. Sieve of Eratosthenes runs in O(n log log n).', E'int solve(int n) {
    // your code here
}', 0.3, 'int->int', 'cpp', 'C++')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.prime_count', '[10]', '4', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.prime_count' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.prime_count', '[2]', '0', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.prime_count' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.prime_count', '[100]', '25', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.prime_count' and ordinal=2);
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.prime_count', 'cpp', 'C++', E'int solve(int n) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.prime_count')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.prime_count', 'java', 'Java', E'static int solve(int n) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.prime_count')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.prime_count', 'python', 'Python', E'def solve(n):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.prime_count')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, signature, language, language_label) values
  ('cp.second_largest', 'dsa.arrays', 'Second Largest', 'Return the second largest distinct value in nums, or -1 if there is none.', E'int solve(vector<int>& nums) {
    // your code here
}', -0.2, 'ints->int', 'cpp', 'C++')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.second_largest', '[[3,1,4,1,5]]', '4', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.second_largest' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.second_largest', '[[2,2]]', '-1', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.second_largest' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.second_largest', '[[9,8,7]]', '8', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.second_largest' and ordinal=2);
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.second_largest', 'cpp', 'C++', E'int solve(vector<int>& nums) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.second_largest')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.second_largest', 'java', 'Java', E'static int solve(int[] nums) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.second_largest')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.second_largest', 'python', 'Python', E'def solve(nums):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.second_largest')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, signature, language, language_label) values
  ('cp.rotate_array', 'dsa.arrays', 'Rotate Array', 'Rotate nums right by k steps and return it.', E'vector<int> solve(vector<int>& nums, int k) {
    // your code here
}', 0.2, 'ints,int->ints', 'cpp', 'C++')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.rotate_array', '[[1,2,3,4,5],2]', '[4,5,1,2,3]', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.rotate_array' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.rotate_array', '[[1],3]', '[1]', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.rotate_array' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.rotate_array', '[[1,2],1]', '[2,1]', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.rotate_array' and ordinal=2);
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.rotate_array', 'cpp', 'C++', E'vector<int> solve(vector<int>& nums, int k) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.rotate_array')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.rotate_array', 'java', 'Java', E'static int[] solve(int[] nums, int k) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.rotate_array')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.rotate_array', 'python', 'Python', E'def solve(nums, k):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.rotate_array')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, signature, language, language_label) values
  ('cp.majority', 'dsa.hashing', 'Majority Element', 'Return the element appearing more than n/2 times. It is guaranteed to exist.', E'int solve(vector<int>& nums) {
    // your code here
}', 0.1, 'ints->int', 'cpp', 'C++')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.majority', '[[3,2,3]]', '3', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.majority' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.majority', '[[1]]', '1', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.majority' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.majority', '[[2,2,1,1,1,2,2]]', '2', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.majority' and ordinal=2);
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.majority', 'cpp', 'C++', E'int solve(vector<int>& nums) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.majority')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.majority', 'java', 'Java', E'static int solve(int[] nums) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.majority')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.majority', 'python', 'Python', E'def solve(nums):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.majority')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, signature, language, language_label) values
  ('cp.anagram', 'dsa.hashing', 'Valid Anagram', 'Return true if t is an anagram of s.', E'bool solve(string& s, string& t) {
    // your code here
}', -0.3, 'str,str->bool', 'cpp', 'C++')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.anagram', '["anagram","nagaram"]', 'true', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.anagram' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.anagram', '["rat","car"]', 'false', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.anagram' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.anagram', '["a","a"]', 'true', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.anagram' and ordinal=2);
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.anagram', 'cpp', 'C++', E'bool solve(string& s, string& t) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.anagram')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.anagram', 'java', 'Java', E'static boolean solve(String s, String t) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.anagram')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.anagram', 'python', 'Python', E'def solve(s, t):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.anagram')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, signature, language, language_label) values
  ('cp.longest_unique', 'dsa.sliding_window', 'Longest Unique Substring', 'Return the length of the longest substring without repeating characters.', E'int solve(string& s) {
    // your code here
}', 0.5, 'str->int', 'cpp', 'C++')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.longest_unique', '["abcabcbb"]', '3', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.longest_unique' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.longest_unique', '["bbbbb"]', '1', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.longest_unique' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.longest_unique', '["pwwkew"]', '3', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.longest_unique' and ordinal=2);
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.longest_unique', 'cpp', 'C++', E'int solve(string& s) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.longest_unique')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.longest_unique', 'java', 'Java', E'static int solve(String s) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.longest_unique')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.longest_unique', 'python', 'Python', E'def solve(s):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.longest_unique')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, signature, language, language_label) values
  ('cp.climb_stairs', 'dsa.dp_1d', 'Climbing Stairs', 'You can climb 1 or 2 steps at a time. Return the number of distinct ways to reach step n.', E'int solve(int n) {
    // your code here
}', 0.0, 'int->int', 'cpp', 'C++')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.climb_stairs', '[3]', '3', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.climb_stairs' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.climb_stairs', '[1]', '1', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.climb_stairs' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.climb_stairs', '[10]', '89', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.climb_stairs' and ordinal=2);
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.climb_stairs', 'cpp', 'C++', E'int solve(int n) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.climb_stairs')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.climb_stairs', 'java', 'Java', E'static int solve(int n) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.climb_stairs')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.climb_stairs', 'python', 'Python', E'def solve(n):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.climb_stairs')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, signature, language, language_label) values
  ('cp.coin_change', 'dsa.dp_1d', 'Coin Change', 'Return the fewest coins summing to amount, or -1 if impossible.', E'int solve(vector<int>& coins, int amount) {
    // your code here
}', 0.7, 'ints,int->int', 'cpp', 'C++')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.coin_change', '[[1,2,5],11]', '3', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.coin_change' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.coin_change', '[[2],3]', '-1', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.coin_change' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.coin_change', '[[1],0]', '0', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.coin_change' and ordinal=2);
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.coin_change', 'cpp', 'C++', E'int solve(vector<int>& coins, int amount) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.coin_change')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.coin_change', 'java', 'Java', E'static int solve(int[] coins, int amount) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.coin_change')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.coin_change', 'python', 'Python', E'def solve(coins, amount):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.coin_change')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, signature, language, language_label) values
  ('cp.matrix_spiral', 'dsa.arrays', 'Row Sums', 'Given a flat array representing an n by n matrix in row-major order, return the sum of each row.', E'vector<int> solve(vector<int>& flat, int n) {
    // your code here
}', 0.3, 'ints,int->ints', 'cpp', 'C++')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.matrix_spiral', '[[1,2,3,4],2]', '[3,7]', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.matrix_spiral' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.matrix_spiral', '[[5],1]', '[5]', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.matrix_spiral' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.matrix_spiral', '[[1,1,1,1,1,1,1,1,1],3]', '[3,3,3]', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.matrix_spiral' and ordinal=2);
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.matrix_spiral', 'cpp', 'C++', E'vector<int> solve(vector<int>& flat, int n) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.matrix_spiral')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.matrix_spiral', 'java', 'Java', E'static int[] solve(int[] flat, int n) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.matrix_spiral')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.matrix_spiral', 'python', 'Python', E'def solve(flat, n):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.matrix_spiral')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, signature, language, language_label) values
  ('cp.balanced_split', 'dsa.two_pointers', 'Equilibrium Index', 'Return the smallest index where the sum of elements to the left equals the sum to the right, or -1.', E'int solve(vector<int>& nums) {
    // your code here
}', 0.4, 'ints->int', 'cpp', 'C++')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.balanced_split', '[[1,7,3,6,5,6]]', '3', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.balanced_split' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.balanced_split', '[[1,2,3]]', '-1', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.balanced_split' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.balanced_split', '[[1]]', '0', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.balanced_split' and ordinal=2);
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.balanced_split', 'cpp', 'C++', E'int solve(vector<int>& nums) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.balanced_split')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.balanced_split', 'java', 'Java', E'static int solve(int[] nums) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.balanced_split')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.balanced_split', 'python', 'Python', E'def solve(nums):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.balanced_split')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
'@

Write-ProjectFile 'web\.env.local.example' @'
# Copy to .env.local and fill in from Supabase -> Project Settings -> API
NEXT_PUBLIC_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_anon_public_key

# Server-only. Needed later for grading attempts. NEVER prefix with NEXT_PUBLIC_.
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
'@

Write-ProjectFile 'web\src\app\api\attempt\route.ts' @'
import { createClient } from '@/lib/supabase/server'
import { NextResponse } from 'next/server'

/**
 * Grading runs server-side because the browser must never see is_correct
 * before answering. The client sends what it chose; the server decides.
 * The Postgres trigger on `attempts` then updates mastery automatically.
 */
export async function POST(request: Request) {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) {
    return NextResponse.json({ error: 'Not signed in' }, { status: 401 })
  }

  const body = await request.json()
  const { questionId, optionId, confidence, timeTakenSec, sessionId, minutesIntoSession } = body

  if (!questionId || !optionId || !confidence) {
    return NextResponse.json({ error: 'Missing fields' }, { status: 400 })
  }

  const { data: option } = await supabase
    .from('options')
    .select('option_id, question_id, is_correct, misconception_id')
    .eq('option_id', optionId)
    .single()

  if (!option || option.question_id !== questionId) {
    return NextResponse.json({ error: 'Unknown option' }, { status: 400 })
  }

  const { data: question } = await supabase
    .from('questions')
    .select('median_time_sec, primary_concept_id')
    .eq('question_id', questionId)
    .single()

  const median = question?.median_time_sec ?? 45
  const ratio = timeTakenSec / median

  // Rule-based error typing. Replaced by a fitted classifier once
  // several hundred hand-labelled attempts exist.
  let errorType: string
  if (ratio < 0.2) {
    errorType = option.is_correct ? 'guess' : 'careless'
  } else if (option.is_correct) {
    errorType = confidence === 3 ? 'mastered' : 'uncertain_correct'
  } else if (option.misconception_id) {
    errorType = 'misconception'
  } else {
    errorType = 'procedural_slip'
  }

  const { error } = await supabase.from('attempts').insert({
    student_id: user.id,
    question_id: questionId,
    chosen_option_id: optionId,
    session_id: sessionId ?? null,
    is_correct: option.is_correct,
    confidence,
    time_taken_sec: Math.round(timeTakenSec),
    minutes_into_session: minutesIntoSession ?? null,
    error_type: errorType,
  })

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  let misconception = null
  if (option.misconception_id) {
    const { data: m } = await supabase
      .from('misconceptions')
      .select('label, remediation_note')
      .eq('misconception_id', option.misconception_id)
      .single()
    misconception = m
  }

  const { data: correctOption } = await supabase
    .from('options')
    .select('body')
    .eq('question_id', questionId)
    .eq('is_correct', true)
    .single()

  return NextResponse.json({
    isCorrect: option.is_correct,
    errorType,
    misconception,
    correctAnswer: correctOption?.body ?? null,
    concept: question?.primary_concept_id ?? null,
  })
}
'@

Write-ProjectFile 'web\src\app\api\run\route.ts' @'
import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

/**
 * Remote execution for compiled languages.
 *
 * C++ and Java cannot run in a browser at any sane weight, so they go to a
 * public judge. Python deliberately does NOT come through here: it runs
 * client-side via Pyodide, which keeps the coding section usable when the
 * network is unavailable.
 *
 * The student writes only a `solve` function. main() is generated here from
 * the problem's type signature, so they never hand-write I/O parsing.
 */

const PISTON = 'https://emkc.org/api/v2/piston/execute'

const VERSIONS: Record<string, { language: string; version: string; filename: string }> = {
  cpp: { language: 'c++', version: '10.2.0', filename: 'main.cpp' },
  java: { language: 'java', version: '15.0.2', filename: 'Main.java' },
}

type Sig = { params: string[]; ret: string }

function parseSignature(sig: string): Sig | null {
  const [lhs, ret] = sig.split('->')
  if (!lhs || !ret) return null
  return { params: lhs.split(',').filter(Boolean), ret }
}

/* ---------------- literal builders ---------------- */

function cppLiteral(type: string, v: unknown): string {
  if (type === 'ints') return `{${(v as number[]).join(',')}}`
  if (type === 'str') return JSON.stringify(v)
  if (type === 'bool') return v ? 'true' : 'false'
  return String(v)
}

function javaLiteral(type: string, v: unknown): string {
  if (type === 'ints') return `new int[]{${(v as number[]).join(',')}}`
  if (type === 'str') return JSON.stringify(v)
  if (type === 'bool') return v ? 'true' : 'false'
  return String(v)
}

/* ---------------- harness generation ---------------- */

function buildCpp(userCode: string, sig: Sig, cases: unknown[][]): string {
  const decls: string[] = []
  const calls: string[] = []

  cases.forEach((args, i) => {
    const names: string[] = []
    args.forEach((a, j) => {
      const t = sig.params[j]
      const name = `a${i}_${j}`
      names.push(name)
      const cppType = t === 'ints' ? 'vector<int>' : t === 'str' ? 'string' : t === 'bool' ? 'bool' : 'int'
      decls.push(`    ${cppType} ${name} = ${cppLiteral(t, a)};`)
    })
    calls.push(`    emit(solve(${names.join(', ')}));`)
  })

  return `#include <bits/stdc++.h>
using namespace std;

${userCode}

static void emit(int v){ cout << v << "\\n"; }
static void emit(bool v){ cout << (v ? "true" : "false") << "\\n"; }
static void emit(const string& v){ cout << "\\"" << v << "\\"" << "\\n"; }
static void emit(const vector<int>& v){
    cout << "[";
    for (size_t i = 0; i < v.size(); i++) { if (i) cout << ","; cout << v[i]; }
    cout << "]\\n";
}

int main(){
    ios::sync_with_stdio(false);
${decls.join('\n')}
${calls.join('\n')}
    return 0;
}
`
}

function buildJava(userCode: string, sig: Sig, cases: unknown[][]): string {
  const calls: string[] = []

  cases.forEach((args) => {
    const lits = args.map((a, j) => javaLiteral(sig.params[j], a))
    calls.push(`        emit(solve(${lits.join(', ')}));`)
  })

  return `import java.util.*;

public class Main {
${userCode
  .split('\n')
  .map((l) => (l.trim() ? '    ' + l : l))
  .join('\n')}

    static void emit(int v){ System.out.println(v); }
    static void emit(boolean v){ System.out.println(v ? "true" : "false"); }
    static void emit(String v){ System.out.println("\\"" + v + "\\""); }
    static void emit(int[] v){
        StringBuilder sb = new StringBuilder("[");
        for (int i = 0; i < v.length; i++) { if (i > 0) sb.append(","); sb.append(v[i]); }
        sb.append("]");
        System.out.println(sb.toString());
    }

    public static void main(String[] args){
${calls.join('\n')}
    }
}
`
}

export async function POST(request: Request) {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Not signed in' }, { status: 401 })

  const { problemId, language, code } = await request.json()

  const target = VERSIONS[language]
  if (!target) {
    return NextResponse.json(
      { error: `${language} is not executed on the server.` },
      { status: 400 }
    )
  }

  const { data: problem } = await supabase
    .from('coding_problems')
    .select('signature, coding_tests ( input_json, expect_json, is_hidden, ordinal )')
    .eq('problem_id', problemId)
    .single()

  if (!problem?.signature) {
    return NextResponse.json(
      { error: 'This problem has no type signature. Run migration 006.' },
      { status: 400 }
    )
  }

  const sig = parseSignature(problem.signature)
  if (!sig) return NextResponse.json({ error: 'Malformed signature.' }, { status: 500 })

  const tests = (problem.coding_tests ?? []).sort((a, b) => a.ordinal - b.ordinal)
  const cases = tests.map((t) => JSON.parse(t.input_json) as unknown[])

  const source =
    language === 'cpp' ? buildCpp(code, sig, cases) : buildJava(code, sig, cases)

  let payload: { run?: { stdout?: string; stderr?: string }; compile?: { stderr?: string } }
  try {
    const res = await fetch(PISTON, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        language: target.language,
        version: target.version,
        files: [{ name: target.filename, content: source }],
        compile_timeout: 10000,
        run_timeout: 5000,
      }),
    })
    if (!res.ok) {
      return NextResponse.json(
        { error: `Judge returned ${res.status}. It may be rate limited; wait a moment.` },
        { status: 502 }
      )
    }
    payload = await res.json()
  } catch {
    return NextResponse.json(
      { error: 'Could not reach the execution service. Python still runs offline.' },
      { status: 502 }
    )
  }

  const compileErr = payload.compile?.stderr?.trim()
  if (compileErr) {
    return NextResponse.json({ results: [], error: compileErr.slice(0, 800) })
  }

  const runErr = payload.run?.stderr?.trim()
  const lines = (payload.run?.stdout ?? '').split('\n').filter((l) => l.length > 0)

  if (lines.length === 0 && runErr) {
    return NextResponse.json({ results: [], error: runErr.slice(0, 800) })
  }

  const results = tests.map((t, i) => {
    const got = lines[i] ?? 'no output'
    return {
      ordinal: t.ordinal,
      hidden: t.is_hidden,
      passed: got === t.expect_json,
      got,
      want: t.expect_json,
    }
  })

  return NextResponse.json({ results, error: runErr ? runErr.slice(0, 400) : null })
}
'@

Write-ProjectFile 'web\src\app\auth\callback\route.ts' @'
import { createClient } from '@/lib/supabase/server'
import { NextResponse } from 'next/server'

// Handles the redirect after a confirmation email is clicked.
export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url)
  const code = searchParams.get('code')
  const next = searchParams.get('next') ?? '/dashboard'

  if (code) {
    const supabase = await createClient()
    const { error } = await supabase.auth.exchangeCodeForSession(code)
    if (!error) {
      return NextResponse.redirect(`${origin}${next}`)
    }
  }

  return NextResponse.redirect(`${origin}/login?error=confirmation_failed`)
}
'@

Write-ProjectFile 'web\src\app\dashboard\diagnosis\page.tsx' @'
import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import PageHead from '@/components/dashboard/PageHead'
import EmptyState from '@/components/dashboard/EmptyState'
import { getAnalytics } from '@/lib/analytics'

const LABELS: Record<string, string> = {
  misconception: 'Misconception',
  procedural_slip: 'Procedural slip',
  careless: 'Careless',
  guess: 'Guess',
  uncertain_correct: 'Uncertain correct',
  mastered: 'Mastered',
}

const TONE: Record<string, string> = {
  misconception: 'bg-alarm',
  procedural_slip: 'bg-amber',
  careless: 'bg-blueprint',
  guess: 'bg-faint',
}

export default async function DiagnosisPage() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const a = await getAnalytics(user.id)
  const d = a.diagnosis

  if (d.total === 0) {
    return (
      <main className="px-6 lg:px-10 py-8 pb-20">
        <PageHead
          eyebrow="DIAGNOSIS"
          title="Nothing to diagnose yet."
          lede="This page reads your own attempts. Answer some questions and it fills in."
        />
        <div className="max-w-lg">
          <EmptyState
            title="Start with the placement test"
            body="Twenty questions across the concept graph, with confidence declared before each answer."
          />
        </div>
      </main>
    )
  }

  const cells = [
    { label: 'SURE + WRONG', n: d.sureWrong, title: 'Confidently wrong', note: 'Held beliefs, not slips. Highest priority.', bg: 'bg-alarm-wash', accent: 'text-alarm' },
    { label: 'UNSURE + WRONG', n: d.unsureWrong, title: 'Known gaps', note: 'You already suspected these.', bg: 'bg-card', accent: 'text-ink' },
    { label: 'UNSURE + CORRECT', n: d.unsureCorrect, title: 'Probably guessed', note: 'Credited at reduced weight.', bg: 'bg-card', accent: 'text-ink' },
    { label: 'SURE + CORRECT', n: d.sureCorrect, title: 'Mastered', note: 'Moved to review.', bg: 'bg-card', accent: 'text-mastery' },
  ]

  const wrongTotal = d.errorMix.reduce((x, e) => x + e.n, 0)
  const misconceptions = d.errorMix.find((e) => e.kind === 'misconception')?.n ?? 0

  return (
    <main className="px-6 lg:px-10 py-8 pb-20">
      <PageHead
        eyebrow="DIAGNOSIS"
        title="What you believe, and how firmly."
        lede={`${d.total} attempts recorded. Correctness alone would tell you ${d.sureCorrect + d.unsureCorrect} out of ${d.total}. This is the rest of it.`}
      />

      <div className="grid xl:grid-cols-12 gap-7">
        <div className="xl:col-span-7 space-y-7">
          <section>
            <p className="font-mono text-[11px] eyebrow text-faint mb-5">
              CONFIDENCE &times; CORRECTNESS
            </p>
            <div className="grid sm:grid-cols-2 gap-px bg-rule border border-rule">
              {cells.map((c) => (
                <div key={c.label} className={`${c.bg} px-6 py-6`}>
                  <div className="flex items-start justify-between gap-3 mb-4">
                    <p className={`font-mono text-[10px] eyebrow ${c.accent}`}>{c.label}</p>
                    <span className={`font-display font-extrabold text-2xl tight ${c.accent}`}>
                      {c.n}
                    </span>
                  </div>
                  <p className={`font-display font-semibold text-lg tight ${c.accent}`}>
                    {c.title}
                  </p>
                  <p className="text-sm text-soft mt-1.5 leading-relaxed">{c.note}</p>
                </div>
              ))}
            </div>
          </section>

          {wrongTotal > 0 && (
            <section className="border border-rule bg-card">
              <div className="border-b border-rule px-6 py-3">
                <p className="font-mono text-[10px] eyebrow text-faint">
                  HOW THE WRONG ANSWERS WENT WRONG
                </p>
              </div>
              <div className="px-6 py-6">
                <div className="flex h-3 border border-rule mb-5">
                  {d.errorMix.map((e) => (
                    <div
                      key={e.kind}
                      className={TONE[e.kind] ?? 'bg-faint'}
                      style={{ width: `${(e.n / wrongTotal) * 100}%` }}
                      title={`${LABELS[e.kind] ?? e.kind}: ${e.n}`}
                    />
                  ))}
                </div>
                <dl className="grid grid-cols-2 sm:grid-cols-4 gap-4">
                  {d.errorMix.map((e) => (
                    <div key={e.kind}>
                      <div className="flex items-center gap-2 mb-1">
                        <span className={`w-2 h-2 ${TONE[e.kind] ?? 'bg-faint'}`} />
                        <dt className="font-mono text-[10px] text-faint">
                          {LABELS[e.kind] ?? e.kind}
                        </dt>
                      </div>
                      <dd className="font-mono text-sm">{e.n}</dd>
                    </div>
                  ))}
                </dl>
                {misconceptions > 0 && (
                  <p className="text-sm text-soft mt-6 leading-relaxed">
                    {misconceptions} of your {wrongTotal} wrong answers map to a named
                    misconception rather than a slip. Those are the ones re-teaching fixes
                    and more practice does not.
                  </p>
                )}
              </div>
            </section>
          )}
        </div>

        <div className="xl:col-span-5">
          <section className="border border-rule bg-card">
            <div className="border-b border-rule px-5 py-3">
              <p className="font-mono text-[10px] eyebrow text-faint">NAMED BELIEFS</p>
            </div>
            {a.fixFirst.length === 0 ? (
              <div className="px-5 py-5">
                <p className="text-xs text-soft leading-relaxed">
                  None diagnosed yet. A belief is named when a wrong answer matches a
                  distractor tagged to a specific misconception.
                </p>
              </div>
            ) : (
              <ol className="divide-y divide-rule">
                {a.fixFirst.map((f, i) => (
                  <li key={f.belief} className="px-5 py-4">
                    <div className="flex items-baseline justify-between gap-3 mb-1.5">
                      <span className="font-mono text-[11px]">
                        <span className="text-faint mr-2">
                          {String(i + 1).padStart(2, '0')}
                        </span>
                        {f.concept}
                      </span>
                      <span className="font-mono text-[10px] text-amber">{f.times}x</span>
                    </div>
                    <p className="text-xs text-soft leading-relaxed">{f.belief}</p>
                  </li>
                ))}
              </ol>
            )}
          </section>
        </div>
      </div>
    </main>
  )
}
'@

Write-ProjectFile 'web\src\app\dashboard\layout.tsx' @'
import AppShell from '@/components/AppShell'

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  return <AppShell>{children}</AppShell>
}
'@

Write-ProjectFile 'web\src\app\dashboard\map\page.tsx' @'
import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import PageHead from '@/components/dashboard/PageHead'
import ConceptMap from '@/components/dashboard/ConceptMap'

export default async function MapPage() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const [{ data: concepts }, { data: prereqs }, { data: mastery }, { data: subjects }] =
    await Promise.all([
      supabase.from('concepts').select('concept_id, name, subject_id, level'),
      supabase.from('prerequisites').select('parent_id, child_id, weight'),
      supabase
        .from('mastery')
        .select('concept_id, mastery_prob, observation_count')
        .eq('student_id', user.id),
      supabase.from('subjects').select('subject_id, name'),
    ])

  return (
    <main className="px-6 lg:px-10 py-8 pb-20">
      <PageHead
        eyebrow="CONCEPT MAP"
        title="Everything you know, and what it rests on."
        lede="Node colour is your current mastery. Grey means unobserved. Edges run from prerequisite upward to dependent."
      />
      <ConceptMap
        concepts={concepts ?? []}
        prereqs={prereqs ?? []}
        mastery={mastery ?? []}
        subjects={subjects ?? []}
      />
    </main>
  )
}
'@

Write-ProjectFile 'web\src\app\dashboard\page.tsx' @'
import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import Link from 'next/link'

import DiagnosisBanner from '@/components/dashboard/DiagnosisBanner'
import StatStrip from '@/components/dashboard/StatStrip'
import MasteryBySubject from '@/components/dashboard/MasteryBySubject'
import FixFirstQueue from '@/components/dashboard/FixFirstQueue'
import EmptyState from '@/components/dashboard/EmptyState'
import MasteryBar from '@/components/dashboard/MasteryBar'
import { getAnalytics } from '@/lib/analytics'

export default async function DashboardPage() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: profile } = await supabase
    .from('profiles')
    .select('display_name')
    .eq('student_id', user.id)
    .single()

  const a = await getAnalytics(user.id)
  const name = profile?.display_name ?? 'Student'

  if (a.attemptCount === 0) {
    return (
      <main className="px-6 lg:px-10 py-8 pb-20">
        <p className="font-mono text-[11px] eyebrow text-faint mb-4">TODAY</p>
        <h1 className="font-display font-extrabold text-3xl tight leading-tight">
          Nothing recorded yet, {name.split(' ')[0]}.
        </h1>
        <p className="mt-3 text-soft leading-relaxed max-w-lg">
          Everything here is computed from your own answers. There is no sample mode
          and no placeholder data, so the dashboard stays empty until you start.
        </p>
        <div className="mt-9 max-w-lg">
          <EmptyState
            title="Twenty questions, twelve minutes"
            body="Declare confidence before each answer. What comes back is a map of what you believe and how firmly, not a score."
          />
        </div>
      </main>
    )
  }

  return (
    <main className="px-6 lg:px-10 py-8 pb-20">
      <div className="flex flex-wrap items-center justify-between gap-4 mb-7">
        <div>
          <p className="font-mono text-[11px] eyebrow text-faint mb-2">TODAY</p>
          <p className="font-mono text-xs text-soft">
            Computed from {a.attemptCount} of your own attempts
          </p>
        </div>
        <div className="flex flex-wrap gap-3">
          <Link
            href="/study"
            className="font-mono text-xs border border-ink px-5 py-2.5 hover:bg-ink hover:text-paper transition-colors"
          >
            Study
          </Link>
          <Link
            href="/study/placement"
            className="font-mono text-xs bg-ink text-paper px-5 py-2.5 hover:bg-blueprint transition-colors"
          >
            Take a test
          </Link>
        </div>
      </div>

      <div className="grid xl:grid-cols-12 gap-7">
        <div className="xl:col-span-8 space-y-7">
          <DiagnosisBanner
            name={name}
            rootCause={a.rootCause}
            confidentlyWrong={a.diagnosis.sureWrong}
          />
          <StatStrip
            attemptCount={a.attemptCount}
            focusHalfLife={a.focusHalfLife}
            sessionsTracked={a.sessionsTracked}
            activeMinutes={a.activeMinutes}
            namedBeliefs={a.fixFirst.length}
          />

          {a.thinEstimate && (
            <div className="border-l-2 border-amber bg-amber-wash px-5 py-4">
              <p className="font-mono text-[10px] eyebrow text-amber mb-2">
                ESTIMATES ARE PROVISIONAL
              </p>
              <p className="text-xs text-soft leading-relaxed">
                Median {a.medianObservations} observation
                {a.medianObservations === 1 ? '' : 's'} per concept. At this depth a
                mastery number is close to &ldquo;did you get that one question
                right&rdquo; and will swing on the next answer. It settles from about
                four attempts per concept.
              </p>
            </div>
          )}

          <section>
            <p className="font-mono text-[11px] eyebrow text-faint mb-5">WEAKEST RIGHT NOW</p>
            {a.weakest.length === 0 ? (
              <EmptyState
                title="No mastery estimates yet"
                body="These appear as soon as attempts are recorded against a concept."
              />
            ) : (
              <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-px bg-rule border border-rule">
                {a.weakest.map((w) => (
                  <Link
                    key={w.conceptId}
                    href={`/study/session?concept=${encodeURIComponent(w.conceptId)}`}
                    className="bg-card px-5 py-5 hover:bg-paper transition-colors"
                  >
                    <p className="font-mono text-[10px] text-faint mb-2">
                      {w.subjectId.toUpperCase()}
                    </p>
                    <p className="font-mono text-sm">{w.name}</p>
                    <div className="mt-3">
                      <MasteryBar mastery={w.mastery} observations={w.observations} />
                    </div>
                  </Link>
                ))}
              </div>
            )}
          </section>
        </div>

        <div className="xl:col-span-4 space-y-7">
          <FixFirstQueue items={a.fixFirst} />
          <MasteryBySubject subjects={a.subjects} />

          <div className="border-l-2 border-blueprint bg-blue-wash px-5 py-4">
            <p className="font-mono text-[10px] eyebrow text-blueprint mb-2">
              NOT YET COMPUTED
            </p>
            <p className="text-xs text-soft leading-relaxed">
              Forgetting curves, focus half-life, and the generated timetable need the
              Python fitter and about five tracked sessions. Nothing here is
              placeholder &mdash; those panels stay empty until the numbers are real.
            </p>
          </div>
        </div>
      </div>
    </main>
  )
}
'@

Write-ProjectFile 'web\src\app\dashboard\plan\page.tsx' @'
import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import Link from 'next/link'
import PageHead from '@/components/dashboard/PageHead'
import { getAnalytics } from '@/lib/analytics'

export default async function PlanPage() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: plan } = await supabase
    .from('study_plans')
    .select('plan_id, generated_at, plan_items ( concept_id, scheduled_for, allocated_minutes, priority_score, reason )')
    .eq('student_id', user.id)
    .eq('is_current', true)
    .order('generated_at', { ascending: false })
    .limit(1)
    .maybeSingle()

  const a = await getAnalytics(user.id)

  if (!plan) {
    return (
      <main className="px-6 lg:px-10 py-8 pb-20">
        <PageHead
          eyebrow="PLAN"
          title="No plan generated yet."
          lede="The scheduler needs three things: your mastery estimates, a fitted forgetting curve, and a measured focus half-life. You have the first."
        />

        <div className="grid md:grid-cols-3 gap-px bg-rule border border-rule max-w-3xl">
          {[
            ['MASTERY ESTIMATES', a.attemptCount > 0 ? 'READY' : 'MISSING',
             `${a.attemptCount} attempts recorded`, a.attemptCount > 0],
            ['FORGETTING CURVE', 'MISSING',
             'Needs the Python fitter and repeat reviews', false],
            ['FOCUS HALF-LIFE', 'MISSING',
             `Needs 5 tracked sessions (${a.sessionsTracked} so far)`, false],
          ].map(([label, status, note, ok]) => (
            <div key={String(label)} className="bg-card px-5 py-5">
              <p className="font-mono text-[10px] eyebrow text-faint mb-3">{label}</p>
              <p
                className={`font-mono text-sm ${ok ? 'text-mastery' : 'text-faint'}`}
              >
                {status}
              </p>
              <p className="text-xs text-soft mt-2 leading-relaxed">{note}</p>
            </div>
          ))}
        </div>

        <p className="text-soft mt-8 max-w-lg leading-relaxed">
          Until then, work from the weakest concepts on your dashboard. Those are
          computed from real data and are already correctly ordered by the graph.
        </p>

        <Link
          href="/study"
          className="inline-block mt-6 font-mono text-sm border border-ink px-6 py-3 hover:bg-ink hover:text-paper transition-colors"
        >
          Go to study
        </Link>
      </main>
    )
  }

  return (
    <main className="px-6 lg:px-10 py-8 pb-20">
      <PageHead
        eyebrow="PLAN"
        title="Your current week."
        lede={`Generated ${new Date(plan.generated_at).toLocaleString('en-IN')}.`}
      />
      <div className="space-y-3 max-w-3xl">
        {(plan.plan_items ?? []).map((it, i) => (
          <div key={i} className="paper-card pl-7 pr-5 py-4">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <p className="font-mono text-[10px] text-faint mb-1.5">
                  {it.scheduled_for}
                </p>
                <p className="font-display font-semibold text-base tight">
                  {it.concept_id}
                </p>
              </div>
              <span className="font-mono text-[10px] text-amber shrink-0">
                {it.allocated_minutes} MIN
              </span>
            </div>
          </div>
        ))}
      </div>
    </main>
  )
}
'@

Write-ProjectFile 'web\src\app\dashboard\settings\page.tsx' @'
import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import PageHead from '@/components/dashboard/PageHead'
import SettingsForm from '@/components/dashboard/SettingsForm'

export default async function SettingsPage() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  const { data: profile } = await supabase
    .from('profiles')
    .select('display_name, weekly_minutes, tracking_opt_in, target_exam_id')
    .eq('student_id', user.id)
    .single()

  return (
    <main className="px-6 lg:px-10 py-8 pb-20">
      <PageHead
        eyebrow="SETTINGS"
        title="What we track, and what we do with it."
        lede="Attention tracking is off unless you turn it on. Without it the planner falls back to fixed 25-minute blocks instead of blocks sized to you."
      />
      <SettingsForm
        email={user.email ?? ''}
        displayName={profile?.display_name ?? ''}
        weeklyMinutes={profile?.weekly_minutes ?? 300}
        trackingOptIn={profile?.tracking_opt_in ?? false}
        targetExamId={profile?.target_exam_id ?? null}
      />
    </main>
  )
}
'@

Write-ProjectFile 'web\src\app\dashboard\simulate\page.tsx' @'
import PageHead from '@/components/dashboard/PageHead'
import Simulator from '@/components/dashboard/Simulator'

export default function SimulatePage() {
  return (
    <main className="px-6 lg:px-10 py-8 pb-20">
      <PageHead
        eyebrow="SIMULATE"
        title="Spend the hours before you spend them."
        lede="Move hours between subjects and watch the projected score move. The model runs forward through your mastery estimates and forgetting curves, so the answer is not linear."
      />
      <Simulator />
    </main>
  )
}
'@

Write-ProjectFile 'web\src\app\globals.css' @'
@import "tailwindcss";

/* Tailwind v4 uses CSS-first config. If create-next-app gave you Tailwind v3
   instead (you'll have a tailwind.config.ts already), delete this @theme block
   and use the tailwind.config.ts included alongside this file. */
@theme {
  --color-paper:     #F2F4F1;
  --color-grid:      #DCE4DB;
  --color-rule:      #C8D2C7;
  --color-card:      #FBFBF8;
  --color-ink:       #141A17;
  --color-soft:      #4A554E;
  --color-faint:     #7C877F;
  --color-blueprint: #1B4D8F;
  --color-amber:     #B8721A;
  --color-alarm:     #9E2B2B;
  --color-mastery:   #2E6B4F;

  --color-alarm-wash: #F6E5E4;
  --color-amber-wash: #F7EEDC;
  --color-blue-wash:  #F4F7FB;

  --font-display: var(--font-archivo), sans-serif;
  --font-body:    var(--font-plex-sans), sans-serif;
  --font-mono:    var(--font-plex-mono), monospace;
}

body {
  background-color: var(--color-paper);
  background-image:
    linear-gradient(var(--color-grid) 1px, transparent 1px),
    linear-gradient(90deg, var(--color-grid) 1px, transparent 1px);
  background-size: 32px 32px;
  background-position: -1px -1px;
}

.rule    { border-top: 1px solid var(--color-rule); }
.eyebrow { letter-spacing: 0.18em; }
.tight   { letter-spacing: -0.03em; }

.trace-edge { stroke-dasharray: 200; stroke-dashoffset: 200; animation: draw .7s ease forwards; }
.trace-node { opacity: 0; animation: pop .45s ease forwards; }

@keyframes draw { to { stroke-dashoffset: 0; } }
@keyframes pop  { from { opacity: 0; transform: translateY(6px); } to { opacity: 1; transform: none; } }

.d1 { animation-delay: .15s }  .d2 { animation-delay: .55s }
.d3 { animation-delay: .95s }  .d4 { animation-delay: 1.35s }
.d5 { animation-delay: 1.75s } .d6 { animation-delay: 2.15s }

.paper-card {
  position: relative;
  background: var(--color-card);
  box-shadow:
    0 1px 0 var(--color-rule),
    0 2px 0 var(--color-card),
    0 3px 0 var(--color-rule),
    0 8px 14px -8px rgba(20, 26, 23, .28);
}
.paper-card::before {
  content: ''; position: absolute; left: 0; top: 0; bottom: 0;
  width: 3px; background: var(--color-amber);
}

.layer { transition: transform .35s ease; }
.stack:hover .l1 { transform: translate(-10px, -10px); }
.stack:hover .l3 { transform: translate(10px, 10px); }

a:focus-visible, button:focus-visible {
  outline: 2px solid var(--color-blueprint);
  outline-offset: 3px;
}

@media (prefers-reduced-motion: reduce) {
  .trace-edge, .trace-node { animation: none; stroke-dashoffset: 0; opacity: 1; }
  .layer { transition: none; }
}

/* Scroll scene: the pinned section needs a scroll anchor that doesn't
   fight the sticky header. */
html { scroll-behavior: smooth; scroll-padding-top: 4rem; }

@media (prefers-reduced-motion: reduce) {
  html { scroll-behavior: auto; }
}
'@

Write-ProjectFile 'web\src\app\layout.tsx' @'
import type { Metadata } from 'next'
import { Archivo, IBM_Plex_Sans, IBM_Plex_Mono } from 'next/font/google'
import './globals.css'

const archivo = Archivo({
  subsets: ['latin'],
  weight: ['400', '600', '800'],
  variable: '--font-archivo',
  display: 'swap',
})

const plexSans = IBM_Plex_Sans({
  subsets: ['latin'],
  weight: ['400', '500'],
  variable: '--font-plex-sans',
  display: 'swap',
})

const plexMono = IBM_Plex_Mono({
  subsets: ['latin'],
  weight: ['400', '500'],
  variable: '--font-plex-mono',
  display: 'swap',
})

export const metadata: Metadata = {
  title: 'Diagnostic \u2014 adaptive learning that finds the root cause',
  description:
    'Most study apps flag the topic you failed. This one traces the failure down your prerequisite graph and names the concept that actually caused it.',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html
      lang="en"
      className={`${archivo.variable} ${plexSans.variable} ${plexMono.variable}`}
    >
      <body className="font-body text-ink antialiased">{children}</body>
    </html>
  )
}
'@

Write-ProjectFile 'web\src\app\login\page.tsx' @'
'use client'

import { Suspense, useState } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/client'
import AuthShell from '@/components/AuthShell'

export default function LoginPage() {
  return (
    <Suspense fallback={null}>
      <LoginForm />
    </Suspense>
  )
}

function LoginForm() {
  const router = useRouter()
  const params = useSearchParams()
  const supabase = createClient()

  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(
    params.get('error') === 'confirmation_failed'
      ? 'That confirmation link is invalid or has expired. Try logging in, or sign up again.'
      : null
  )

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    setBusy(true)

    const { error } = await supabase.auth.signInWithPassword({ email, password })
    setBusy(false)

    if (error) {
      setError(
        error.message === 'Invalid login credentials'
          ? 'That email and password do not match an account.'
          : error.message
      )
      return
    }

    router.push(params.get('next') ?? '/dashboard')
    router.refresh()
  }

  return (
    <AuthShell
      eyebrow="LOG IN"
      title={<>Pick up where the model left off.</>}
      aside={<Aside />}
    >
      <form onSubmit={handleSubmit} className="space-y-5">
        <label className="block">
          <span className="font-mono text-[10px] eyebrow text-faint">EMAIL</span>
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            autoComplete="email"
            required
            className="mt-2 w-full bg-card border border-rule px-4 py-3 text-sm placeholder:text-faint focus:border-ink focus:outline-none transition-colors"
            placeholder="you@kiit.ac.in"
          />
        </label>

        <label className="block">
          <span className="font-mono text-[10px] eyebrow text-faint">PASSWORD</span>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            autoComplete="current-password"
            required
            className="mt-2 w-full bg-card border border-rule px-4 py-3 text-sm placeholder:text-faint focus:border-ink focus:outline-none transition-colors"
            placeholder="Your password"
          />
        </label>

        {error && (
          <div className="border-l-2 border-alarm bg-alarm-wash px-4 py-3">
            <p className="font-mono text-[10px] eyebrow text-alarm mb-1">COULD NOT LOG IN</p>
            <p className="text-sm text-alarm">{error}</p>
          </div>
        )}

        <button
          type="submit"
          disabled={busy}
          className="w-full font-mono text-sm bg-ink text-paper py-3.5 hover:bg-blueprint transition-colors disabled:opacity-50"
        >
          {busy ? 'Checking\u2026' : 'Log in'}
        </button>
      </form>

      <p className="font-mono text-xs text-faint mt-7">
        No account yet?{' '}
        <Link href="/signup" className="text-ink border-b border-rule hover:border-ink">
          Create one
        </Link>
      </p>
    </AuthShell>
  )
}

function Aside() {
  return (
    <>
      <p className="font-mono text-[11px] eyebrow text-paper/50 mb-7">SINCE YOU WERE LAST HERE</p>
      <div className="space-y-px bg-paper/10 border border-paper/10">
        {[
          ['CONCEPTS DECAYING', '4', 'Retention dropped below 0.75 while you were away.'],
          ['OPEN ROOT CAUSES', '2', 'Still explaining most of your recent failures.'],
          ['PLAN STATUS', 'STALE', 'Regenerates the moment you log in.'],
        ].map(([label, value, note]) => (
          <div key={label} className="bg-ink px-6 py-5">
            <div className="flex items-baseline justify-between gap-4">
              <span className="font-mono text-[10px] eyebrow text-paper/50">{label}</span>
              <span className="font-display font-extrabold text-2xl text-amber tight">{value}</span>
            </div>
            <p className="text-sm text-paper/60 mt-1.5">{note}</p>
          </div>
        ))}
      </div>
      <p className="font-mono text-[10px] text-paper/40 mt-6">
        Sample figures. Yours load after login.
      </p>
    </>
  )
}
'@

Write-ProjectFile 'web\src\app\page.tsx' @'
import SiteNav from '@/components/SiteNav'
import Hero from '@/components/Hero'
import TheGap from '@/components/TheGap'
import Pipeline from '@/components/Pipeline'
import ScrollScene from '@/components/ScrollScene'
import DiagnosisGrid from '@/components/DiagnosisGrid'
import TakeTest from '@/components/TakeTest'
import AttentionModel from '@/components/AttentionModel'
import ExamTargets from '@/components/ExamTargets'
import CallToAction from '@/components/CallToAction'
import SiteFooter from '@/components/SiteFooter'
import Reveal from '@/components/Reveal'

export default function Home() {
  return (
    <>
      <SiteNav />
      <main>
        <Hero />
        <Reveal><TheGap /></Reveal>
        <Reveal><Pipeline /></Reveal>
        <ScrollScene />
        <Reveal><DiagnosisGrid /></Reveal>
        <TakeTest />
        <Reveal><AttentionModel /></Reveal>
        <Reveal><ExamTargets /></Reveal>
        <CallToAction />
      </main>
      <SiteFooter />
    </>
  )
}
'@

Write-ProjectFile 'web\src\app\signup\page.tsx' @'
'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/client'
import AuthShell from '@/components/AuthShell'

export default function SignupPage() {
  const router = useRouter()
  const supabase = createClient()

  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [sent, setSent] = useState(false)

  const weak = password.length > 0 && password.length < 8

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)

    if (password.length < 8) {
      setError('Password must be at least 8 characters.')
      return
    }

    setBusy(true)
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: { display_name: name },
        emailRedirectTo: `${location.origin}/auth/callback`,
      },
    })
    setBusy(false)

    if (error) {
      setError(error.message)
      return
    }

    // If email confirmation is on, there is no session yet.
    if (data.session) {
      router.push('/dashboard')
      router.refresh()
    } else {
      setSent(true)
    }
  }

  if (sent) {
    return (
      <AuthShell
        eyebrow="CHECK YOUR EMAIL"
        title={<>One more step.</>}
        aside={<Aside />}
      >
        <p className="text-soft leading-relaxed">
          We sent a confirmation link to <span className="text-ink">{email}</span>.
          Open it and you will land straight on your placement test.
        </p>
        <p className="font-mono text-xs text-faint mt-6">
          Nothing arrived? Check spam, then{' '}
          <button
            onClick={() => setSent(false)}
            className="text-ink border-b border-rule hover:border-ink"
          >
            try a different address
          </button>
          .
        </p>
      </AuthShell>
    )
  }

  return (
    <AuthShell
      eyebrow="CREATE ACCOUNT"
      title={<>Find out what you&rsquo;re confidently wrong about.</>}
      aside={<Aside />}
    >
      <form onSubmit={handleSubmit} className="space-y-5">
        <Field
          label="NAME"
          type="text"
          value={name}
          onChange={setName}
          placeholder="Your name"
          autoComplete="name"
          required
        />
        <Field
          label="EMAIL"
          type="email"
          value={email}
          onChange={setEmail}
          placeholder="you@kiit.ac.in"
          autoComplete="email"
          required
        />
        <div>
          <Field
            label="PASSWORD"
            type="password"
            value={password}
            onChange={setPassword}
            placeholder="At least 8 characters"
            autoComplete="new-password"
            required
          />
          {weak && (
            <p className="font-mono text-[10px] text-amber mt-2">
              {8 - password.length} more character{8 - password.length === 1 ? '' : 's'} needed
            </p>
          )}
        </div>

        {error && (
          <div className="border-l-2 border-alarm bg-alarm-wash px-4 py-3">
            <p className="font-mono text-[10px] eyebrow text-alarm mb-1">COULD NOT SIGN UP</p>
            <p className="text-sm text-alarm">{error}</p>
          </div>
        )}

        <button
          type="submit"
          disabled={busy}
          className="w-full font-mono text-sm bg-ink text-paper py-3.5 hover:bg-blueprint transition-colors disabled:opacity-50"
        >
          {busy ? 'Creating account\u2026' : 'Create account'}
        </button>
      </form>

      <p className="font-mono text-xs text-faint mt-7">
        Already have one?{' '}
        <Link href="/login" className="text-ink border-b border-rule hover:border-ink">
          Log in
        </Link>
      </p>
    </AuthShell>
  )
}

function Aside() {
  return (
    <>
      <p className="font-mono text-[11px] eyebrow text-paper/50 mb-6">WHAT HAPPENS NEXT</p>
      <ol className="space-y-6">
        {[
          ['01', 'Twenty questions, twelve minutes', 'Adaptive, spread across the concept graph. Confidence declared before each answer.'],
          ['02', 'A diagnosis, not a score', 'Which beliefs are wrong, which answers you guessed, and the root concepts underneath both.'],
          ['03', 'Week one, generated', 'Blocks sized to your attention span, ordered so nothing arrives before its prerequisites.'],
        ].map(([n, h, b]) => (
          <li key={n} className="flex gap-5">
            <span className="font-mono text-xs text-amber pt-1">{n}</span>
            <div>
              <p className="font-display font-semibold text-lg tight">{h}</p>
              <p className="text-sm text-paper/60 mt-1.5 leading-relaxed">{b}</p>
            </div>
          </li>
        ))}
      </ol>
    </>
  )
}

function Field({
  label,
  type,
  value,
  onChange,
  placeholder,
  autoComplete,
  required,
}: {
  label: string
  type: string
  value: string
  onChange: (v: string) => void
  placeholder?: string
  autoComplete?: string
  required?: boolean
}) {
  return (
    <label className="block">
      <span className="font-mono text-[10px] eyebrow text-faint">{label}</span>
      <input
        type={type}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        autoComplete={autoComplete}
        required={required}
        className="mt-2 w-full bg-card border border-rule px-4 py-3 text-sm placeholder:text-faint focus:border-ink focus:outline-none transition-colors"
      />
    </label>
  )
}
'@

Write-ProjectFile 'web\src\app\study\code\page.tsx' @'
import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import CodeRunner from '@/components/study/CodeRunner'

export default async function CodePage() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: profile } = await supabase
    .from('profiles')
    .select('tracking_opt_in')
    .eq('student_id', user.id)
    .single()

  const { data: problems } = await supabase
    .from('coding_problems')
    .select('problem_id, title, prompt, starter_code, difficulty, concept_id, language_label, coding_tests ( test_id, input_json, expect_json, is_hidden, ordinal ), problem_starters ( language, label, starter_code, is_runnable )')
    .eq('is_active', true)
    .order('difficulty', { ascending: true })

  if (!problems || problems.length === 0) {
    return (
      <main className="px-6 lg:px-10 py-16">
        <p className="font-mono text-[11px] eyebrow text-alarm mb-4">NO PROBLEMS</p>
        <h1 className="font-display font-extrabold text-2xl tight">
          Run migrations 003, 004 and 005 first.
        </h1>
        <p className="mt-4 text-soft max-w-md leading-relaxed">
          Migration 003 creates the telemetry tables, 004 adds the problems, and 005 adds the per-language starter code.
        </p>
      </main>
    )
  }

  return (
    <CodeRunner
      problems={JSON.parse(JSON.stringify(problems))}
      trackingOptIn={profile?.tracking_opt_in ?? false}
    />
  )
}
'@

Write-ProjectFile 'web\src\app\study\layout.tsx' @'
import AppShell from '@/components/AppShell'

export default function StudyLayout({ children }: { children: React.ReactNode }) {
  return <AppShell>{children}</AppShell>
}
'@

Write-ProjectFile 'web\src\app\study\page.tsx' @'
import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import Link from 'next/link'
import MasteryBar from '@/components/dashboard/MasteryBar'

export default async function StudyHub() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { count: attempts } = await supabase
    .from('attempts')
    .select('*', { count: 'exact', head: true })
    .eq('student_id', user.id)

  const { data: weakest } = await supabase
    .from('mastery')
    .select('concept_id, mastery_prob, observation_count, concepts:concept_id ( name, subject_id )')
    .eq('student_id', user.id)
    .order('mastery_prob', { ascending: true })
    .limit(4)

  return (
    <main className="px-6 lg:px-10 py-8 pb-20">
      <p className="font-mono text-[11px] eyebrow text-faint mb-4">STUDY</p>
      <h1 className="font-display font-extrabold text-3xl tight leading-tight">
        Pick how you want to work.
      </h1>
      <p className="mt-3 text-soft leading-relaxed max-w-xl">
        {attempts
          ? `${attempts} attempts recorded so far.`
          : 'Nothing recorded yet. Start with the placement test.'}
      </p>

      <div className="grid md:grid-cols-3 gap-px bg-rule border border-rule mt-9">
        <Link href="/study/placement" className="bg-card px-6 py-7 hover:bg-paper transition-colors">
          <p className="font-mono text-[10px] eyebrow text-blueprint mb-4">DIAGNOSTIC</p>
          <p className="font-display font-semibold text-lg tight">Placement test</p>
          <p className="text-sm text-soft mt-2 leading-relaxed">
            Twenty questions across the graph. Re-take any time to re-estimate.
          </p>
          <p className="font-mono text-[10px] text-faint mt-4">~12 min</p>
        </Link>

        <Link href="/study/session" className="bg-card px-6 py-7 hover:bg-paper transition-colors">
          <p className="font-mono text-[10px] eyebrow text-amber mb-4">PRACTICE</p>
          <p className="font-display font-semibold text-lg tight">Concept drill</p>
          <p className="text-sm text-soft mt-2 leading-relaxed">
            Questions from one concept, in a short focused block.
          </p>
          <p className="font-mono text-[10px] text-faint mt-4">22 min block</p>
        </Link>

        <Link href="/study/code" className="bg-card px-6 py-7 hover:bg-paper transition-colors">
          <p className="font-mono text-[10px] eyebrow text-mastery mb-4">CODING</p>
          <p className="font-display font-semibold text-lg tight">Code practice</p>
          <p className="text-sm text-soft mt-2 leading-relaxed">
            Write and run solutions. Typing rhythm feeds the attention model.
          </p>
          <p className="font-mono text-[10px] text-faint mt-4">Open-ended</p>
        </Link>
      </div>

      {weakest && weakest.length > 0 && (
        <section className="mt-12">
          <p className="font-mono text-[11px] eyebrow text-faint mb-5">WEAKEST RIGHT NOW</p>
          <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-px bg-rule border border-rule">
            {weakest.map((w) => {
              const c = w.concepts as unknown as { name: string; subject_id: string } | null
              return (
                <Link
                  key={w.concept_id}
                  href={`/study/session?concept=${w.concept_id}`}
                  className="bg-card px-5 py-5 hover:bg-paper transition-colors"
                >
                  <p className="font-mono text-[10px] text-faint mb-2">
                    {c?.subject_id?.toUpperCase()}
                  </p>
                  <p className="font-mono text-sm">{c?.name ?? w.concept_id}</p>
                  <div className="mt-3">
                    <MasteryBar
                      mastery={Number(w.mastery_prob)}
                      observations={Number(w.observation_count ?? 0)}
                    />
                  </div>
                </Link>
              )
            })}
          </div>
        </section>
      )}
    </main>
  )
}
'@

Write-ProjectFile 'web\src\app\study\placement\page.tsx' @'
import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import PlacementRunner from '@/components/study/PlacementRunner'

type PoolItem = {
  difficulty: number
  concepts: { subject_id: string } | null
}

/** Even coverage across subjects, then across easy/medium/hard within each. */
function stratifiedSample<T extends PoolItem>(pool: T[], want: number): T[] {
  const bySubject = new Map<string, T[]>()
  for (const q of pool) {
    const key = q.concepts?.subject_id ?? 'unknown'
    const list = bySubject.get(key) ?? []
    list.push(q)
    bySubject.set(key, list)
  }

  const subjects = [...bySubject.keys()]
  const perSubject = Math.max(1, Math.floor(want / Math.max(1, subjects.length)))
  const picked: T[] = []

  for (const subject of subjects) {
    const items = bySubject.get(subject)!
    const bands: T[][] = [[], [], []]
    for (const q of items) {
      const d = Number(q.difficulty)
      bands[d < -0.3 ? 0 : d < 0.4 ? 1 : 2].push(q)
    }
    for (const band of bands) {
      const take = Math.ceil(perSubject / 3)
      picked.push(...shuffle(band).slice(0, take))
    }
  }

  // Top up from whatever is left if the strata came up short.
  const chosen = new Set(picked)
  const rest = shuffle(pool.filter((q) => !chosen.has(q)))
  while (picked.length < want && rest.length) picked.push(rest.pop()!)

  return shuffle(picked).slice(0, want)
}

function shuffle<T>(arr: T[]): T[] {
  const a = [...arr]
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1))
    ;[a[i], a[j]] = [a[j], a[i]]
  }
  return a
}

export default async function PlacementPage() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: profile } = await supabase
    .from('profiles')
    .select('tracking_opt_in')
    .eq('student_id', user.id)
    .single()

  // Stratified sample, not the 20 easiest.
  //
  // Ordering by difficulty and taking the first 20 served an identical test
  // every sitting: the same questions, the same failures, the same diagnosis,
  // and entire subjects never sampled at all. This draws across subjects and
  // difficulty bands, and reshuffles on every attempt.
  const { data: pool } = await supabase
    .from('questions')
    .select(`
      question_id, stem, difficulty, median_time_sec, primary_concept_id,
      concepts:primary_concept_id ( name, subject_id ),
      options ( option_id, body, ordinal )
    `)
    .eq('is_active', true)
    .limit(400)

  const questions = pool ? stratifiedSample(pool, 20) : []

  if (questions.length === 0) {
    return (
      <main className="min-h-screen flex items-center justify-center px-6">
        <div className="max-w-md">
          <p className="font-mono text-[11px] eyebrow text-alarm mb-4">NO QUESTIONS</p>
          <h1 className="font-display font-extrabold text-2xl tight">
            The content bank is empty.
          </h1>
          <p className="mt-4 text-soft leading-relaxed">
            Run <span className="font-mono text-xs">002_seed_starter_content.sql</span> in
            the Supabase SQL editor, then reload.
          </p>
        </div>
      </main>
    )
  }

  return (
    <PlacementRunner
      questions={JSON.parse(JSON.stringify(questions))}
      trackingOptIn={profile?.tracking_opt_in ?? false}
    />
  )
}
'@

Write-ProjectFile 'web\src\app\study\session\page.tsx' @'
import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import Link from 'next/link'
import PlacementRunner from '@/components/study/PlacementRunner'

export default async function SessionPage({
  searchParams,
}: {
  searchParams: Promise<{ concept?: string; minutes?: string }>
}) {
  const params = await searchParams
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: profile } = await supabase
    .from('profiles')
    .select('tracking_opt_in')
    .eq('student_id', user.id)
    .single()

  // Roughly one question per 90 seconds of block time.
  const minutes = Number(params.minutes ?? 22)
  const want = Math.max(5, Math.min(20, Math.round((minutes * 60) / 90)))

  let query = supabase
    .from('questions')
    .select(`
      question_id, stem, difficulty, median_time_sec, primary_concept_id,
      concepts:primary_concept_id ( name, subject_id ),
      options ( option_id, body, ordinal )
    `)
    .eq('is_active', true)
    .limit(Math.max(want * 3, 30))

  if (params.concept) {
    query = query.eq('primary_concept_id', params.concept)
  }

  const { data: rows } = await query

  // Shuffle so repeat drills on the same concept are not identical.
  const questions = rows
    ? [...rows].sort(() => Math.random() - 0.5).slice(0, want)
    : []

  if (questions.length === 0) {
    return (
      <main className="px-6 lg:px-10 py-16">
        <p className="font-mono text-[11px] eyebrow text-amber mb-4">NOTHING TO SERVE</p>
        <h1 className="font-display font-extrabold text-2xl tight max-w-lg">
          No questions authored for this concept yet.
        </h1>
        <p className="mt-4 text-soft max-w-md leading-relaxed">
          The starter bank covers 16 concepts. Everything else is waiting on the
          content track.
        </p>
        <Link
          href="/study"
          className="inline-block mt-8 font-mono text-sm border border-ink px-6 py-3 hover:bg-ink hover:text-paper transition-colors"
        >
          Back to study
        </Link>
      </main>
    )
  }

  return (
    <PlacementRunner
      questions={JSON.parse(JSON.stringify(questions))}
      trackingOptIn={profile?.tracking_opt_in ?? false}
    />
  )
}
'@

Write-ProjectFile 'web\src\components\AppShell.tsx' @'
import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import SideRail from '@/components/dashboard/SideRail'
import LogoutButton from '@/components/LogoutButton'

/**
 * One shell for every signed-in page, so the rail is always present and
 * there is never a screen you cannot navigate out of.
 */
export default async function AppShell({ children }: { children: React.ReactNode }) {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: profile } = await supabase
    .from('profiles')
    .select('display_name')
    .eq('student_id', user.id)
    .single()

  const name = profile?.display_name ?? user.email?.split('@')[0] ?? 'Student'

  return (
    <div className="min-h-screen">
      <SideRail name={name} />
      <div className="lg:pl-56">
        <header className="border-b border-rule bg-paper/90 backdrop-blur sticky top-0 z-30">
          <div className="px-6 lg:px-10 h-14 flex items-center justify-between">
            <p className="font-mono text-[10px] eyebrow text-faint">
              {new Date().toLocaleDateString('en-IN', {
                weekday: 'long',
                day: 'numeric',
                month: 'short',
              })}
            </p>
            <LogoutButton />
          </div>
        </header>
        {children}
      </div>
    </div>
  )
}
'@

Write-ProjectFile 'web\src\components\AttentionModel.tsx' @'
const blocks = [
  {
    when: '09:10 \u2014 09:32 \u00b7 NEW MATERIAL',
    title: 'Sorting basics',
    why: 'Root cause of 6 Dijkstra failures. Placed early, attention is highest.',
    minutes: '22 MIN',
    tilt: '-rotate-[0.4deg]',
  },
  {
    when: '09:37 \u2014 09:59 \u00b7 CONTRAST DRILL',
    title: 'BFS vs DFS ordering',
    why: 'You\u2019ve confused these four times. Interleaved, not blocked.',
    minutes: '22 MIN',
    tilt: 'rotate-[0.3deg]',
  },
  {
    when: '21:15 \u2014 21:27 \u00b7 REVIEW',
    title: 'Normalization \u2014 3NF',
    why: 'Retention drops below 0.75 tomorrow. Night slot: review, not new learning.',
    minutes: '12 MIN',
    tilt: '-rotate-[0.2deg]',
  },
]

export default function AttentionModel() {
  return (
    <section id="focus" className="rule">
      <div className="mx-auto max-w-6xl px-6 py-20">
        <div className="grid md:grid-cols-12 gap-14 items-start">
          <div className="md:col-span-5">
            <p className="font-mono text-[11px] eyebrow text-faint mb-6">ATTENTION MODEL</p>
            <h2 className="font-display font-extrabold text-3xl md:text-4xl tight leading-tight">
              Your focus half-life<br />is 23 minutes.
            </h2>
            <p className="mt-6 text-soft leading-relaxed">
              Measured from tab switches, idle gaps, response-time drift, and the point where your
              accuracy starts falling inside a session. Nobody&rsquo;s attention is 60 minutes long
              just because the timetable says so.
            </p>

            <div className="mt-9 border border-rule bg-card p-6">
              <p className="font-mono text-[10px] eyebrow text-faint mb-4">ACCURACY WITHIN A SESSION</p>
              <svg
                viewBox="0 0 300 110"
                className="w-full"
                role="img"
                aria-label="Accuracy decaying over minutes into a session, with a cutoff marked at 23 minutes."
              >
                <line x1="26" y1="92" x2="290" y2="92" stroke="#C8D2C7" />
                <line x1="26" y1="8" x2="26" y2="92" stroke="#C8D2C7" />
                <path d="M26 22 C 90 26, 130 44, 170 62 S 240 88, 290 96" fill="none" stroke="#1B4D8F" strokeWidth="2" />
                <line x1="152" y1="8" x2="152" y2="92" stroke="#B8721A" strokeWidth="1" strokeDasharray="3 3" />
                <text x="158" y="18" fontFamily="var(--font-plex-mono)" fontSize="9" fill="#B8721A">23 min &mdash; cutoff</text>
                <text x="26" y="106" fontFamily="var(--font-plex-mono)" fontSize="9" fill="#7C877F">0</text>
                <text x="270" y="106" fontFamily="var(--font-plex-mono)" fontSize="9" fill="#7C877F">45 min</text>
              </svg>
            </div>
          </div>

          <div className="md:col-span-7">
            <p className="font-mono text-[10px] eyebrow text-faint mb-6">TUESDAY &mdash; GENERATED FROM YOUR CURVE</p>
            <div className="space-y-4">
              {blocks.map((b) => (
                <div key={b.title} className={`paper-card pl-7 pr-6 py-5 ${b.tilt}`}>
                  <div className="flex items-start justify-between gap-4">
                    <div>
                      <p className="font-mono text-[10px] text-faint mb-1.5">{b.when}</p>
                      <p className="font-display font-semibold text-lg tight">{b.title}</p>
                      <p className="text-sm text-soft mt-1">{b.why}</p>
                    </div>
                    <span className="font-mono text-[10px] text-amber whitespace-nowrap">{b.minutes}</span>
                  </div>
                </div>
              ))}
            </div>
            <p className="font-mono text-[11px] text-faint mt-6">
              Every block links to the trace that produced it.
            </p>
          </div>
        </div>
      </div>
    </section>
  )
}
'@

Write-ProjectFile 'web\src\components\AuthShell.tsx' @'
import Link from 'next/link'

export default function AuthShell({
  eyebrow,
  title,
  children,
  aside,
}: {
  eyebrow: string
  title: React.ReactNode
  children: React.ReactNode
  aside: React.ReactNode
}) {
  return (
    <div className="min-h-screen grid lg:grid-cols-2">
      {/* Form side */}
      <div className="flex flex-col px-6 py-10 sm:px-12 lg:px-16">
        <Link href="/" className="font-display font-extrabold text-lg tight w-fit">
          DIAGNOSTIC
        </Link>

        <div className="flex-1 flex items-center">
          <div className="w-full max-w-sm py-12">
            <p className="font-mono text-[11px] eyebrow text-blueprint mb-5">{eyebrow}</p>
            <h1 className="font-display font-extrabold text-3xl sm:text-4xl tight leading-[1.1] mb-9">
              {title}
            </h1>
            {children}
          </div>
        </div>

        <p className="font-mono text-[10px] text-faint">
          Major project &middot; KIIT &middot; Group 82
        </p>
      </div>

      {/* Context side */}
      <div className="hidden lg:flex bg-ink text-paper items-center px-16">
        <div className="max-w-md">{aside}</div>
      </div>
    </div>
  )
}
'@

Write-ProjectFile 'web\src\components\CallToAction.tsx' @'
import Link from 'next/link'

export default function CallToAction() {
  return (
    <section className="rule bg-ink text-paper">
      <div className="mx-auto max-w-6xl px-6 py-24 text-center">
        <p className="font-mono text-[11px] eyebrow text-paper/50 mb-7">TWENTY QUESTIONS, TWELVE MINUTES</p>
        <h2 className="font-display font-extrabold text-3xl md:text-5xl tight leading-tight max-w-3xl mx-auto">
          Find out what you&rsquo;re<br />confidently wrong about.
        </h2>
        <p className="mt-7 text-paper/70 max-w-lg mx-auto leading-relaxed">
          The placement test maps you onto the concept graph and generates your first week.
          No score at the end &mdash; a diagnosis.
        </p>
        <Link
          href="/signup"
          className="inline-block mt-10 font-mono text-sm bg-paper text-ink px-8 py-4 hover:bg-amber hover:text-paper transition-colors"
        >
          Start the test
        </Link>
      </div>
    </section>
  )
}
'@

Write-ProjectFile 'web\src\components\DiagnosisGrid.tsx' @'
const cells = [
  {
    label: 'SURE + CORRECT',
    title: 'Mastered',
    note: 'Scheduled for review, not practice.',
    bg: 'bg-card',
    labelColor: 'text-faint',
    titleColor: 'text-mastery',
    noteColor: 'text-soft',
  },
  {
    label: 'SURE + WRONG',
    title: 'Fix this first',
    note: 'A belief, not a slip. Highest priority.',
    bg: 'bg-alarm-wash',
    labelColor: 'text-alarm',
    titleColor: 'text-alarm',
    noteColor: 'text-alarm/80',
  },
  {
    label: 'UNSURE + CORRECT',
    title: 'Probably guessed',
    note: 'Credited less. Re-tested sooner.',
    bg: 'bg-card',
    labelColor: 'text-faint',
    titleColor: 'text-ink',
    noteColor: 'text-soft',
  },
  {
    label: 'UNSURE + WRONG',
    title: 'Known gap',
    note: 'You already knew. Straightforward to close.',
    bg: 'bg-card',
    labelColor: 'text-faint',
    titleColor: 'text-ink',
    noteColor: 'text-soft',
  },
]

export default function DiagnosisGrid() {
  return (
    <section className="rule">
      <div className="mx-auto max-w-6xl px-6 py-20">
        <div className="grid md:grid-cols-12 gap-12">
          <div className="md:col-span-5">
            <p className="font-mono text-[11px] eyebrow text-faint mb-6">CONFIDENCE &times; CORRECTNESS</p>
            <h2 className="font-display font-extrabold text-3xl md:text-4xl tight leading-tight">
              Right and wrong<br />is two states.<br />This is four.
            </h2>
            <p className="mt-6 text-soft leading-relaxed">
              You declare confidence before you answer. That one extra tap separates a lucky guess
              from real mastery &mdash; and finds the beliefs you hold firmly and wrongly, which are
              the most expensive thing in your head.
            </p>
          </div>

          <div className="md:col-span-7 grid grid-cols-2 gap-px bg-rule border border-rule">
            {cells.map((c) => (
              <div key={c.label} className={`${c.bg} p-6 min-h-[150px] flex flex-col justify-between`}>
                <p className={`font-mono text-[10px] eyebrow ${c.labelColor}`}>{c.label}</p>
                <div>
                  <p className={`font-display font-semibold text-lg ${c.titleColor}`}>{c.title}</p>
                  <p className={`text-sm mt-1 ${c.noteColor}`}>{c.note}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  )
}
'@

Write-ProjectFile 'web\src\components\ExamTargets.tsx' @'
// NOTE: these section weights are placeholders for layout only.
// Replace with real weights from actual papers before showing this publicly.
const targets = [
  {
    name: 'TCS NQT',
    split: ['Aptitude 40% \u00b7 Verbal 20%', 'Programming logic 25% \u00b7 DBMS 15%'],
  },
  {
    name: 'Infosys SE',
    split: ['Reasoning 35% \u00b7 Aptitude 30%', 'Pseudocode 25% \u00b7 Verbal 10%'],
  },
  {
    name: 'Amazon SDE-1',
    split: ['DSA 60% \u00b7 System design 15%', 'OS 15% \u00b7 DBMS 10%'],
  },
  {
    name: 'Semester exams',
    split: ['Weighted by your syllabus', 'and time to the exam date'],
  },
]

export default function ExamTargets() {
  return (
    <section id="exams" className="rule">
      <div className="mx-auto max-w-6xl px-6 py-20">
        <div className="flex flex-wrap items-end justify-between gap-6 mb-10">
          <div>
            <p className="font-mono text-[11px] eyebrow text-faint mb-5">PLACEMENT MODE</p>
            <h2 className="font-display font-extrabold text-3xl md:text-4xl tight leading-tight max-w-xl">
              Same engine.<br />Different weights.
            </h2>
          </div>
          <p className="text-soft max-w-md leading-relaxed">
            Pick a target and every topic gets reweighted by how much that company actually tests it.
            Your semester prep and your placement prep stop competing for the same hours.
          </p>
        </div>

        <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-px bg-rule border border-rule">
          {targets.map((t) => (
            <div key={t.name} className="bg-paper p-6">
              <p className="font-display font-semibold text-lg tight mb-3">{t.name}</p>
              <p className="font-mono text-xs text-soft leading-relaxed">
                {t.split[0]}
                <br />
                {t.split[1]}
              </p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
'@

Write-ProjectFile 'web\src\components\Hero.tsx' @'
import Link from 'next/link'

export default function Hero() {
  return (
    <section className="mx-auto max-w-6xl px-6 pt-16 pb-20 md:pt-24 md:pb-28">
      <div className="grid md:grid-cols-12 gap-12 items-center">
        <div className="md:col-span-6">
          <p className="font-mono text-[11px] eyebrow text-blueprint mb-6">ROOT-CAUSE DIAGNOSIS</p>
          <h1 className="font-display font-extrabold tight text-4xl sm:text-5xl lg:text-[3.4rem] leading-[1.05]">
            You&rsquo;re not bad at<br />Dijkstra. You&rsquo;re bad<br />at sorting.
          </h1>
          <p className="mt-7 text-lg text-soft max-w-md leading-relaxed">
            Most study apps flag the topic you failed. This one traces the failure down your
            prerequisite graph and names the concept that actually caused it.
          </p>
          <div className="mt-9 flex flex-wrap items-center gap-4">
            <Link
              href="/signup"
              className="font-mono text-sm bg-ink text-paper px-7 py-3.5 hover:bg-blueprint transition-colors"
            >
              Take the placement test
            </Link>
            <Link
              href="#how"
              className="font-mono text-sm text-soft border-b border-rule pb-0.5 hover:text-ink hover:border-ink"
            >
              See how it works
            </Link>
          </div>
        </div>

        <div className="md:col-span-6">
          <div className="border border-rule bg-card p-6">
            <div className="flex items-center justify-between mb-5">
              <span className="font-mono text-[10px] eyebrow text-faint">LIVE TRACE &mdash; ATTEMPT #4127</span>
              <span className="font-mono text-[10px] text-alarm">6 / 8 FAILED</span>
            </div>
            <BlameTrace />
          </div>
        </div>
      </div>
    </section>
  )
}

function BlameTrace() {
  return (
    <svg
      viewBox="0 0 420 330"
      className="w-full"
      role="img"
      aria-label="A failure on Dijkstra distributing blame to three prerequisites, with sorting basics identified as the root cause."
    >
      <g className="trace-node d1">
        <rect x="130" y="8" width="160" height="52" fill="#F6E5E4" stroke="#9E2B2B" strokeWidth="1" />
        <text x="210" y="30" textAnchor="middle" fontFamily="var(--font-plex-mono)" fontSize="13" fill="#9E2B2B">Dijkstra</text>
        <text x="210" y="47" textAnchor="middle" fontFamily="var(--font-plex-mono)" fontSize="10" fill="#9E2B2B">failed</text>
      </g>

      <line className="trace-edge d2" x1="180" y1="60" x2="72" y2="112" stroke="#7C877F" strokeWidth="1" />
      <line className="trace-edge d2" x1="210" y1="60" x2="210" y2="112" stroke="#B8721A" strokeWidth="2" />
      <line className="trace-edge d2" x1="240" y1="60" x2="348" y2="112" stroke="#7C877F" strokeWidth="1" />

      <g className="trace-node d3">
        <rect x="8" y="114" width="128" height="52" fill="#FBFBF8" stroke="#C8D2C7" />
        <text x="72" y="136" textAnchor="middle" fontFamily="var(--font-plex-mono)" fontSize="11" fill="#4A554E">Adjacency list</text>
        <text x="72" y="153" textAnchor="middle" fontFamily="var(--font-plex-mono)" fontSize="10" fill="#7C877F">blame 18%</text>
      </g>
      <g className="trace-node d3">
        <rect x="146" y="114" width="128" height="52" fill="#FBFBF8" stroke="#B8721A" />
        <text x="210" y="136" textAnchor="middle" fontFamily="var(--font-plex-mono)" fontSize="11" fill="#141A17">Priority queue</text>
        <text x="210" y="153" textAnchor="middle" fontFamily="var(--font-plex-mono)" fontSize="10" fill="#B8721A">blame 62%</text>
      </g>
      <g className="trace-node d3">
        <rect x="284" y="114" width="128" height="52" fill="#FBFBF8" stroke="#C8D2C7" />
        <text x="348" y="136" textAnchor="middle" fontFamily="var(--font-plex-mono)" fontSize="11" fill="#4A554E">BFS traversal</text>
        <text x="348" y="153" textAnchor="middle" fontFamily="var(--font-plex-mono)" fontSize="10" fill="#7C877F">blame 20%</text>
      </g>

      <line className="trace-edge d4" x1="210" y1="166" x2="210" y2="218" stroke="#B8721A" strokeWidth="2" />

      <g className="trace-node d5">
        <rect x="130" y="220" width="160" height="56" fill="#F7EEDC" stroke="#B8721A" strokeWidth="2" />
        <text x="210" y="243" textAnchor="middle" fontFamily="var(--font-plex-mono)" fontSize="13" fill="#B8721A">Sorting basics</text>
        <text x="210" y="261" textAnchor="middle" fontFamily="var(--font-plex-mono)" fontSize="10" fill="#B8721A">mastery 0.31 &mdash; root cause</text>
      </g>

      <g className="trace-node d6">
        <text x="210" y="305" textAnchor="middle" fontFamily="var(--font-plex-mono)" fontSize="11" fill="#4A554E">Start two levels down.</text>
      </g>
    </svg>
  )
}
'@

Write-ProjectFile 'web\src\components\LogoutButton.tsx' @'
'use client'

import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'

export default function LogoutButton() {
  const router = useRouter()
  const supabase = createClient()

  async function logout() {
    await supabase.auth.signOut()
    router.push('/login')
    router.refresh()
  }

  return (
    <button
      onClick={logout}
      className="font-mono text-xs border border-ink px-4 py-2 hover:bg-ink hover:text-paper transition-colors"
    >
      Log out
    </button>
  )
}
'@

Write-ProjectFile 'web\src\components\Pipeline.tsx' @'
const stages = [
  {
    index: '01 / RECORD',
    title: 'Every answer, in detail',
    body: 'Which distractor you chose, the confidence you declared before answering, your response time against the median, and a one-line explanation of your reasoning.',
  },
  {
    index: '02 / DIAGNOSE',
    title: 'Named misconceptions',
    body: 'Wrong options map to specific false beliefs, not just to topics. Failures then propagate down the prerequisite graph until they reach something you genuinely don\u2019t know.',
  },
  {
    index: '03 / SCHEDULE',
    title: 'Two curves, one plan',
    body: 'How fast you forget each concept, and how long you can hold attention in one sitting. Your timetable is the intersection of both.',
  },
  {
    index: '04 / ADAPT',
    title: 'Re-fit continuously',
    body: 'Every attempt updates the model. Blocks that stop producing learning get cut short rather than ground through.',
  },
]

export default function Pipeline() {
  return (
    <section id="how" className="rule">
      <div className="mx-auto max-w-6xl px-6 py-20">
        <p className="font-mono text-[11px] eyebrow text-faint mb-12">THE PIPELINE</p>
        <div className="grid md:grid-cols-4 gap-px bg-rule border border-rule">
          {stages.map((s) => (
            <div key={s.index} className="bg-paper p-7">
              <p className="font-mono text-xs text-blueprint mb-4">{s.index}</p>
              <h3 className="font-display font-semibold text-lg mb-3 tight">{s.title}</h3>
              <p className="text-sm text-soft leading-relaxed">{s.body}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
'@

Write-ProjectFile 'web\src\components\Reveal.tsx' @'
'use client'

import { useEffect, useRef, useState } from 'react'

export default function Reveal({
  children,
  delay = 0,
  className = '',
}: {
  children: React.ReactNode
  delay?: number
  className?: string
}) {
  const ref = useRef<HTMLDivElement>(null)
  const [shown, setShown] = useState(false)

  useEffect(() => {
    const el = ref.current
    if (!el) return

    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      setShown(true)
      return
    }

    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setShown(true)
          io.disconnect()
        }
      },
      { threshold: 0.15, rootMargin: '0px 0px -60px 0px' }
    )

    io.observe(el)
    return () => io.disconnect()
  }, [])

  return (
    <div
      ref={ref}
      className={`transition-all duration-700 ease-out ${
        shown ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-6'
      } ${className}`}
      style={{ transitionDelay: `${delay}ms` }}
    >
      {children}
    </div>
  )
}
'@

Write-ProjectFile 'web\src\components\ScrollScene.tsx' @'
'use client'

import { useEffect, useRef, useState } from 'react'

type Node = {
  id: string
  label: string
  x: number
  y: number
  tier: number
}

const NODES: Node[] = [
  { id: 'arrays',    label: 'Arrays',         x: 120, y: 278, tier: 0 },
  { id: 'loops',     label: 'Loops',          x: 380, y: 278, tier: 0 },
  { id: 'sorting',   label: 'Sorting basics', x: 120, y: 198, tier: 1 },
  { id: 'recursion', label: 'Recursion',      x: 380, y: 198, tier: 1 },
  { id: 'pq',        label: 'Priority queue', x: 105, y: 118, tier: 2 },
  { id: 'graphrep',  label: 'Graph repr.',    x: 250, y: 118, tier: 2 },
  { id: 'bfs',       label: 'BFS',            x: 395, y: 118, tier: 2 },
  { id: 'dijkstra',  label: 'Dijkstra',       x: 250, y: 38,  tier: 3 },
]

const EDGES: [string, string][] = [
  ['arrays', 'sorting'],
  ['arrays', 'pq'],
  ['loops', 'recursion'],
  ['sorting', 'pq'],
  ['recursion', 'graphrep'],
  ['recursion', 'bfs'],
  ['pq', 'dijkstra'],
  ['graphrep', 'dijkstra'],
  ['bfs', 'dijkstra'],
]

const BLAME_PATH: [string, string][] = [
  ['dijkstra', 'pq'],
  ['pq', 'sorting'],
]

const W = 110
const H = 40

function node(id: string) {
  return NODES.find((n) => n.id === id)!
}

/** Maps overall progress onto a 0..1 range for one stage. */
function stage(p: number, from: number, to: number) {
  return Math.max(0, Math.min(1, (p - from) / (to - from)))
}

const CAPTIONS = [
  { at: 0.02, text: 'Every subject is a graph, built from the foundations up.' },
  { at: 0.34, text: 'Prerequisites carry weights, not just links.' },
  { at: 0.52, text: 'Six of eight Dijkstra attempts fail.' },
  { at: 0.70, text: 'Blame propagates downward, weighted by what you already know.' },
  { at: 0.88, text: 'The root is two levels below where you failed.' },
]

export default function ScrollScene() {
  const wrapRef = useRef<HTMLDivElement>(null)
  const [p, setP] = useState(0)
  const [reduced, setReduced] = useState(false)

  useEffect(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      setReduced(true)
      setP(1)
      return
    }

    const el = wrapRef.current
    if (!el) return

    let frame = 0
    const update = () => {
      cancelAnimationFrame(frame)
      frame = requestAnimationFrame(() => {
        const rect = el.getBoundingClientRect()
        const travel = rect.height - window.innerHeight
        if (travel <= 0) return setP(1)
        setP(Math.max(0, Math.min(1, -rect.top / travel)))
      })
    }

    update()
    window.addEventListener('scroll', update, { passive: true })
    window.addEventListener('resize', update)
    return () => {
      window.removeEventListener('scroll', update)
      window.removeEventListener('resize', update)
      cancelAnimationFrame(frame)
    }
  }, [])

  // Stage timings
  const build = stage(p, 0.05, 0.34)   // nodes appear tier by tier
  const link = stage(p, 0.30, 0.50)    // edges draw
  const fail = stage(p, 0.50, 0.62)    // Dijkstra turns red
  const blame = stage(p, 0.62, 0.86)   // blame flows down
  const root = stage(p, 0.84, 0.96)    // root ignites

  const caption =
    [...CAPTIONS].reverse().find((c) => p >= c.at)?.text ?? CAPTIONS[0].text

  const tierVisible = (tier: number) => {
    const start = tier * 0.25
    return Math.max(0, Math.min(1, (build - start) / 0.25))
  }

  return (
    <section ref={wrapRef} className="rule relative h-[320vh]">
      <div className="sticky top-16 h-[calc(100vh-4rem)] flex items-center">
        <div className="mx-auto max-w-6xl w-full px-6">
          <div className="grid md:grid-cols-12 gap-10 items-center">
            <div className="md:col-span-4">
              <p className="font-mono text-[11px] eyebrow text-faint mb-6">CONCEPT GRAPH</p>
              <h2 className="font-display font-extrabold text-3xl md:text-4xl tight leading-tight">
                Nothing is scheduled<br />before its<br />prerequisites.
              </h2>
              <p className="mt-7 text-soft leading-relaxed min-h-[4.5rem]">{caption}</p>
              <div className="mt-8 h-px bg-rule relative" aria-hidden="true">
                <div
                  className="absolute inset-y-0 left-0 bg-amber"
                  style={{ width: `${p * 100}%` }}
                />
              </div>
            </div>

            <div className="md:col-span-8">
              <div className="border border-rule bg-card p-4 md:p-6">
                <svg viewBox="0 0 500 330" className="w-full" role="img"
                  aria-label="A prerequisite graph assembling from foundations upward, then a Dijkstra failure propagating blame down to sorting basics.">

                  {EDGES.map(([from, to]) => {
                    const a = node(from)
                    const b = node(to)
                    const onBlame = BLAME_PATH.some(
                      ([x, y]) => (x === to && y === from)
                    )
                    const vis = Math.min(tierVisible(a.tier), link)
                    const blamed = onBlame ? blame : 0
                    return (
                      <line
                        key={`${from}-${to}`}
                        x1={a.x} y1={a.y}
                        x2={b.x} y2={b.y + H / 2}
                        stroke={blamed > 0.15 ? '#B8721A' : '#C8D2C7'}
                        strokeWidth={blamed > 0.15 ? 2.5 : 1}
                        opacity={vis}
                      />
                    )
                  })}

                  {NODES.map((n) => {
                    const vis = tierVisible(n.tier)
                    const isFail = n.id === 'dijkstra'
                    const isRoot = n.id === 'sorting'
                    const isMid = n.id === 'pq'

                    let fill = '#FBFBF8'
                    let stroke = '#C8D2C7'
                    let text = '#4A554E'
                    let sw = 1

                    if (isFail && fail > 0.3) {
                      fill = '#F6E5E4'; stroke = '#9E2B2B'; text = '#9E2B2B'; sw = 2
                    }
                    if (isMid && blame > 0.4) {
                      stroke = '#B8721A'; text = '#141A17'; sw = 2
                    }
                    if (isRoot && root > 0.3) {
                      fill = '#F7EEDC'; stroke = '#B8721A'; text = '#B8721A'; sw = 2.5
                    }

                    return (
                      <g key={n.id} opacity={vis}
                         transform={`translate(0, ${(1 - vis) * 10})`}>
                        <rect
                          x={n.x - W / 2} y={n.y - H / 2}
                          width={W} height={H}
                          fill={fill} stroke={stroke} strokeWidth={sw}
                        />
                        <text
                          x={n.x} y={n.y + 4}
                          textAnchor="middle"
                          fontFamily="var(--font-plex-mono)"
                          fontSize="11"
                          fill={text}
                        >
                          {n.label}
                        </text>
                      </g>
                    )
                  })}

                  {fail > 0.5 && (
                    <text x={250} y={14} textAnchor="middle"
                      fontFamily="var(--font-plex-mono)" fontSize="10"
                      fill="#9E2B2B" opacity={fail}>
                      6 / 8 FAILED
                    </text>
                  )}

                  {blame > 0.5 && (
                    <text x={168} y={82} textAnchor="middle"
                      fontFamily="var(--font-plex-mono)" fontSize="10"
                      fill="#B8721A" opacity={blame}>
                      62%
                    </text>
                  )}

                  {root > 0.4 && (
                    <text x={120} y={236} textAnchor="middle"
                      fontFamily="var(--font-plex-mono)" fontSize="10"
                      fill="#B8721A" opacity={root}>
                      root cause &middot; mastery 0.31
                    </text>
                  )}
                </svg>
              </div>
              {reduced && (
                <p className="font-mono text-[10px] text-faint mt-3">
                  Animation reduced per your system settings.
                </p>
              )}
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
'@

Write-ProjectFile 'web\src\components\SiteFooter.tsx' @'
import Link from 'next/link'

export default function SiteFooter() {
  return (
    <footer>
      <div className="mx-auto max-w-6xl px-6 py-12 flex flex-wrap items-center justify-between gap-6 font-mono text-xs text-faint">
        <div className="flex items-baseline gap-3">
          <span className="font-display font-extrabold text-sm text-ink tight">DIAGNOSTIC</span>
          <span>Major project &middot; KIIT &middot; Group 82</span>
        </div>
        <div className="flex gap-7">
          <Link href="/privacy" className="hover:text-ink">Attention tracking &amp; privacy</Link>
          <Link href="/sources" className="hover:text-ink">Content sources</Link>
        </div>
      </div>
    </footer>
  )
}
'@

Write-ProjectFile 'web\src\components\SiteNav.tsx' @'
import Link from 'next/link'

export default function SiteNav() {
  return (
    <header className="border-b border-rule bg-paper/90 backdrop-blur sticky top-0 z-50">
      <div className="mx-auto max-w-6xl px-6 h-16 flex items-center justify-between">
        <div className="flex items-baseline gap-3">
          <span className="font-display font-extrabold text-lg tight">DIAGNOSTIC</span>
          <span className="font-mono text-[10px] text-faint eyebrow hidden sm:inline">
            ADAPTIVE LEARNING ENGINE
          </span>
        </div>
        <nav className="flex items-center gap-7 font-mono text-xs">
          <Link href="#how" className="hidden sm:inline text-soft hover:text-ink">How it works</Link>
          <Link href="#test" className="hidden sm:inline text-soft hover:text-ink">Try one</Link>
          <Link href="#focus" className="hidden sm:inline text-soft hover:text-ink">Attention</Link>
          <Link href="#exams" className="hidden md:inline text-soft hover:text-ink">Placements</Link>
          <Link
            href="/signup"
            className="border border-ink px-4 py-2 hover:bg-ink hover:text-paper transition-colors"
          >
            Start
          </Link>
        </nav>
      </div>
    </header>
  )
}
'@

Write-ProjectFile 'web\src\components\TakeTest.tsx' @'
'use client'

import { useState } from 'react'
import Link from 'next/link'

type Option = {
  id: string
  body: string
  correct: boolean
  misconception?: string
  note: string
}

const QUESTION = {
  concept: 'dbms.normalization_3nf',
  stem: 'A relation R(A, B, C) has functional dependencies A \u2192 B and B \u2192 C, with A as the only candidate key. Which normal form does R violate?',
  options: [
    {
      id: 'a',
      body: 'First normal form',
      correct: false,
      misconception: 'Treats any dependency chain as an atomicity problem',
      note: '1NF is only about atomic attribute values. Nothing here says an attribute holds a set.',
    },
    {
      id: 'b',
      body: 'Second normal form',
      correct: false,
      misconception: 'Confuses transitive dependency with partial dependency',
      note: '2NF violations need a partial dependency on part of a composite key. A is a single attribute, so there is no partial dependency available.',
    },
    {
      id: 'c',
      body: 'Third normal form',
      correct: true,
      note: 'C depends on A only through B. That transitive dependency is exactly what 3NF forbids.',
    },
    {
      id: 'd',
      body: 'No violation',
      correct: false,
      misconception: 'Does not recognise transitive dependency as a violation',
      note: 'A \u2192 B \u2192 C is a transitive dependency, and R is therefore not in 3NF.',
    },
  ] as Option[],
}

const CONFIDENCE = [
  { value: 1, label: 'Not sure' },
  { value: 2, label: 'Fairly sure' },
  { value: 3, label: 'Certain' },
]

export default function TakeTest() {
  const [confidence, setConfidence] = useState<number | null>(null)
  const [picked, setPicked] = useState<Option | null>(null)

  const reset = () => {
    setConfidence(null)
    setPicked(null)
  }

  const verdict = (() => {
    if (!picked || !confidence) return null
    if (picked.correct) {
      return confidence === 3
        ? { tag: 'MASTERED', tone: 'mastery', line: 'Correct and certain. This goes to review, not practice.' }
        : { tag: 'UNCERTAIN CORRECT', tone: 'ink', line: 'Correct, but you were not sure. Credited less, and you will see this concept again sooner.' }
    }
    if (confidence === 3) {
      return { tag: 'CONFIDENTLY WRONG', tone: 'alarm', line: 'A held belief, not a slip. This is the highest-priority thing to fix.' }
    }
    return { tag: 'KNOWN GAP', tone: 'ink', line: 'You already suspected this one. Straightforward to close.' }
  })()

  return (
    <section id="test" className="rule">
      <div className="mx-auto max-w-6xl px-6 py-20">
        <div className="grid md:grid-cols-12 gap-12">
          <div className="md:col-span-4">
            <p className="font-mono text-[11px] eyebrow text-faint mb-6">TRY ONE</p>
            <h2 className="font-display font-extrabold text-3xl md:text-4xl tight leading-tight">
              This is what<br />one question<br />looks like.
            </h2>
            <p className="mt-6 text-soft leading-relaxed">
              Declare your confidence first, then answer. What comes back is not a score &mdash;
              it is a reading of what you believe and how firmly.
            </p>
            {picked && (
              <button
                onClick={reset}
                className="mt-7 font-mono text-xs text-soft border-b border-rule pb-0.5 hover:text-ink hover:border-ink"
              >
                Try a different answer
              </button>
            )}
          </div>

          <div className="md:col-span-8">
            <div className="border border-rule bg-card">
              <div className="border-b border-rule px-6 py-3 flex items-center justify-between">
                <span className="font-mono text-[10px] eyebrow text-faint">DBMS &middot; NORMALIZATION &middot; 3NF</span>
                <span className="font-mono text-[10px] text-faint">MEDIAN 52s</span>
              </div>

              <div className="p-6">
                <p className="text-lg leading-relaxed mb-7">{QUESTION.stem}</p>

                <p className="font-mono text-[10px] eyebrow text-faint mb-3">
                  STEP 1 &mdash; HOW SURE ARE YOU?
                </p>
                <div className="flex flex-wrap gap-2 mb-8">
                  {CONFIDENCE.map((c) => (
                    <button
                      key={c.value}
                      onClick={() => setConfidence(c.value)}
                      disabled={!!picked}
                      className={`font-mono text-xs px-4 py-2 border transition-colors disabled:opacity-60 ${
                        confidence === c.value
                          ? 'border-ink bg-ink text-paper'
                          : 'border-rule text-soft hover:border-ink hover:text-ink'
                      }`}
                    >
                      {c.label}
                    </button>
                  ))}
                </div>

                <p className="font-mono text-[10px] eyebrow text-faint mb-3">
                  STEP 2 &mdash; YOUR ANSWER
                </p>
                <div className="space-y-2">
                  {QUESTION.options.map((o) => {
                    const chosen = picked?.id === o.id
                    const revealCorrect = picked && o.correct
                    return (
                      <button
                        key={o.id}
                        onClick={() => confidence && setPicked(o)}
                        disabled={!confidence || !!picked}
                        className={`w-full text-left px-5 py-3.5 border transition-colors disabled:cursor-not-allowed ${
                          chosen && !o.correct
                            ? 'border-alarm bg-alarm-wash'
                            : revealCorrect
                            ? 'border-mastery bg-white'
                            : 'border-rule hover:border-ink disabled:hover:border-rule'
                        } ${!confidence ? 'opacity-50' : ''}`}
                      >
                        <span className="font-mono text-xs text-faint mr-3">
                          {o.id.toUpperCase()}
                        </span>
                        <span className="text-sm">{o.body}</span>
                      </button>
                    )
                  })}
                </div>

                {!confidence && (
                  <p className="font-mono text-[10px] text-faint mt-4">
                    Pick a confidence level first &mdash; that is the whole point.
                  </p>
                )}

                {picked && verdict && (
                  <div className="mt-8 border-t border-rule pt-6">
                    <div className="flex flex-wrap items-center gap-3 mb-4">
                      <span
                        className={`font-mono text-[10px] eyebrow px-2.5 py-1 ${
                          verdict.tone === 'alarm'
                            ? 'bg-alarm text-paper'
                            : verdict.tone === 'mastery'
                            ? 'bg-mastery text-paper'
                            : 'bg-ink text-paper'
                        }`}
                      >
                        {verdict.tag}
                      </span>
                      {picked.misconception && (
                        <span className="font-mono text-[10px] text-amber">
                          MISCONCEPTION LOGGED
                        </span>
                      )}
                    </div>

                    <p className="text-sm text-soft leading-relaxed mb-4">{verdict.line}</p>

                    {picked.misconception && (
                      <div className="border-l-2 border-amber pl-4 mb-4">
                        <p className="font-mono text-[10px] eyebrow text-faint mb-1.5">
                          NAMED BELIEF
                        </p>
                        <p className="text-sm text-ink">{picked.misconception}</p>
                      </div>
                    )}

                    <p className="text-sm text-soft leading-relaxed">{picked.note}</p>

                    <p className="font-mono text-[11px] text-faint mt-6">
                      In the real test this feeds twenty of these into your concept graph
                      and generates week one.
                    </p>
                  </div>
                )}
              </div>
            </div>

            <div className="mt-6 flex flex-wrap items-center gap-4">
              <Link
                href="/signup"
                className="font-mono text-sm bg-ink text-paper px-7 py-3.5 hover:bg-blueprint transition-colors"
              >
                Take the full test
              </Link>
              <span className="font-mono text-xs text-faint">
                20 questions &middot; about 12 minutes &middot; no score at the end
              </span>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
'@

Write-ProjectFile 'web\src\components\TheGap.tsx' @'
export default function TheGap() {
  return (
    <section className="rule">
      <div className="mx-auto max-w-6xl px-6 py-20">
        <div className="grid md:grid-cols-12 gap-10">
          <div className="md:col-span-3">
            <p className="font-mono text-[11px] eyebrow text-faint">THE GAP</p>
          </div>
          <div className="md:col-span-9">
            <p className="font-display font-semibold text-2xl md:text-[2rem] leading-snug tight max-w-3xl">
              A quiz app knows you scored 6 out of 10. It doesn&rsquo;t know that four of those
              wrong answers came from one belief you&rsquo;ve held since second year.
            </p>
            <p className="mt-6 text-soft max-w-2xl leading-relaxed">
              Binary right-and-wrong throws away almost everything useful. Which wrong option you
              picked, how sure you were, how long you took, and what you already knew going in
              &mdash; all of it is signal, and all of it usually gets discarded.
            </p>
          </div>
        </div>
      </div>
    </section>
  )
}
'@

Write-ProjectFile 'web\src\components\dashboard\ConceptMap.tsx' @'
'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'

type Concept = { concept_id: string; name: string; subject_id: string; level: number }
type Prereq = { parent_id: string; child_id: string; weight: number }
type Mastery = { concept_id: string; mastery_prob: number; observation_count: number }
type Subject = { subject_id: string; name: string }

const W = 122
const H = 36
const COL_GAP = 20
const ROW_GAP = 78

function tone(m: number | null) {
  if (m === null) return { fill: '#FBFBF8', stroke: '#C8D2C7', text: '#7C877F' }
  if (m < 0.4) return { fill: '#F6E5E4', stroke: '#9E2B2B', text: '#9E2B2B' }
  if (m < 0.7) return { fill: '#F7EEDC', stroke: '#B8721A', text: '#B8721A' }
  return { fill: '#FBFBF8', stroke: '#2E6B4F', text: '#2E6B4F' }
}

export default function ConceptMap({
  concepts,
  prereqs,
  mastery,
  subjects,
}: {
  concepts: Concept[]
  prereqs: Prereq[]
  mastery: Mastery[]
  subjects: Subject[]
}) {
  const [subject, setSubject] = useState<string>(subjects[0]?.subject_id ?? 'all')
  const [sel, setSel] = useState<string | null>(null)

  const masteryOf = useMemo(
    () => new Map(mastery.map((m) => [m.concept_id, Number(m.mastery_prob)])),
    [mastery]
  )

  const shown = useMemo(
    () => concepts.filter((c) => subject === 'all' || c.subject_id === subject),
    [concepts, subject]
  )

  // Lay out by DAG level: level 0 at the bottom, deepest at the top.
  const layout = useMemo(() => {
    const byLevel = new Map<number, Concept[]>()
    for (const c of shown) {
      const list = byLevel.get(c.level) ?? []
      list.push(c)
      byLevel.set(c.level, list)
    }
    const levels = [...byLevel.keys()].sort((a, b) => a - b)
    const maxPerRow = Math.max(...levels.map((l) => byLevel.get(l)!.length), 1)
    const width = maxPerRow * (W + COL_GAP) + COL_GAP
    const height = levels.length * ROW_GAP + 30

    const pos = new Map<string, { x: number; y: number }>()
    for (const lvl of levels) {
      const row = byLevel.get(lvl)!
      const rowWidth = row.length * (W + COL_GAP) - COL_GAP
      const startX = (width - rowWidth) / 2
      const y = height - (levels.indexOf(lvl) + 1) * ROW_GAP
      row.forEach((c, i) => {
        pos.set(c.concept_id, { x: startX + i * (W + COL_GAP), y })
      })
    }
    return { pos, width, height }
  }, [shown])

  const selected = sel ? concepts.find((c) => c.concept_id === sel) ?? null : null
  const selMastery = sel ? masteryOf.get(sel) ?? null : null

  const blockedBy = useMemo(() => {
    if (!sel) return []
    return prereqs
      .filter((p) => p.child_id === sel)
      .map((p) => ({
        id: p.parent_id,
        name: concepts.find((c) => c.concept_id === p.parent_id)?.name ?? p.parent_id,
        m: masteryOf.get(p.parent_id) ?? null,
      }))
      .filter((p) => p.m === null || p.m < 0.7)
  }, [sel, prereqs, concepts, masteryOf])

  const unlocks = useMemo(() => {
    if (!sel) return []
    return prereqs
      .filter((p) => p.parent_id === sel)
      .map((p) => concepts.find((c) => c.concept_id === p.child_id)?.name ?? p.child_id)
  }, [sel, prereqs, concepts])

  if (concepts.length === 0) {
    return (
      <div className="border border-rule bg-card px-6 py-10 text-center">
        <p className="font-display font-semibold text-lg tight">No concepts loaded</p>
        <p className="text-sm text-soft mt-3">
          Run 002_seed_starter_content.sql in the Supabase SQL editor.
        </p>
      </div>
    )
  }

  return (
    <div className="grid xl:grid-cols-12 gap-7">
      <div className="xl:col-span-8">
        <div className="border border-rule bg-card">
          <div className="border-b border-rule px-5 py-3 flex flex-wrap items-center justify-between gap-3">
            <div className="flex gap-2">
              {subjects.map((s) => (
                <button
                  key={s.subject_id}
                  onClick={() => setSubject(s.subject_id)}
                  className={`font-mono text-[10px] px-3 py-1.5 border transition-colors ${
                    subject === s.subject_id
                      ? 'border-ink bg-ink text-paper'
                      : 'border-rule text-soft hover:border-ink hover:text-ink'
                  }`}
                >
                  {s.name}
                </button>
              ))}
            </div>
            <div className="flex items-center gap-3 font-mono text-[10px] text-faint">
              <span className="flex items-center gap-1.5">
                <span className="w-2.5 h-2.5 border" style={{ background: '#F6E5E4', borderColor: '#9E2B2B' }} />
                weak
              </span>
              <span className="flex items-center gap-1.5">
                <span className="w-2.5 h-2.5 border" style={{ background: '#FBFBF8', borderColor: '#2E6B4F' }} />
                strong
              </span>
              <span className="flex items-center gap-1.5">
                <span className="w-2.5 h-2.5 border" style={{ background: '#FBFBF8', borderColor: '#C8D2C7' }} />
                unobserved
              </span>
            </div>
          </div>

          <div className="p-4 overflow-x-auto">
            <svg
              viewBox={`0 0 ${layout.width} ${layout.height}`}
              className="w-full"
              style={{ minWidth: Math.min(layout.width, 640) }}
              role="img"
              aria-label="Concept graph coloured by mastery, prerequisites below dependents."
            >
              {prereqs.map((e) => {
                const a = layout.pos.get(e.parent_id)
                const b = layout.pos.get(e.child_id)
                if (!a || !b) return null
                const pm = masteryOf.get(e.parent_id) ?? null
                const weak = pm !== null && pm < 0.4
                return (
                  <line
                    key={`${e.parent_id}-${e.child_id}`}
                    x1={a.x + W / 2} y1={a.y}
                    x2={b.x + W / 2} y2={b.y + H}
                    stroke={weak ? '#B8721A' : '#C8D2C7'}
                    strokeWidth={weak ? 2 : 1}
                  />
                )
              })}

              {shown.map((c) => {
                const p = layout.pos.get(c.concept_id)
                if (!p) return null
                const m = masteryOf.get(c.concept_id) ?? null
                const t = tone(m)
                const active = sel === c.concept_id
                return (
                  <g
                    key={c.concept_id}
                    onClick={() => setSel(active ? null : c.concept_id)}
                    className="cursor-pointer"
                  >
                    <rect
                      x={p.x} y={p.y} width={W} height={H}
                      fill={t.fill}
                      stroke={active ? '#141A17' : t.stroke}
                      strokeWidth={active ? 2.5 : 1.5}
                    />
                    <text
                      x={p.x + W / 2} y={p.y + 15}
                      textAnchor="middle"
                      fontFamily="var(--font-plex-mono)"
                      fontSize="9.5"
                      fill={t.text}
                    >
                      {c.name.length > 18 ? c.name.slice(0, 17) + '.' : c.name}
                    </text>
                    <text
                      x={p.x + W / 2} y={p.y + 28}
                      textAnchor="middle"
                      fontFamily="var(--font-plex-mono)"
                      fontSize="9"
                      fill="#7C877F"
                    >
                      {m === null ? 'unobserved' : m.toFixed(2)}
                    </text>
                  </g>
                )
              })}
            </svg>
          </div>
        </div>
      </div>

      <div className="xl:col-span-4">
        <div className="border border-rule bg-card sticky top-20">
          <div className="border-b border-rule px-5 py-3">
            <p className="font-mono text-[10px] eyebrow text-faint">
              {selected ? 'SELECTED' : 'NO SELECTION'}
            </p>
          </div>
          <div className="px-5 py-5">
            {!selected ? (
              <p className="text-sm text-soft leading-relaxed">
                Click a node to see its mastery, what it unlocks, and which
                prerequisites are holding it back.
              </p>
            ) : (
              <>
                <p className="font-display font-semibold text-xl tight">{selected.name}</p>
                <p className="font-mono text-[10px] text-faint mt-1">
                  {selected.subject_id.toUpperCase()} &middot; level {selected.level}
                </p>

                <div className="mt-5">
                  <div className="flex items-baseline justify-between mb-1.5">
                    <span className="font-mono text-[10px] text-faint">MASTERY</span>
                    <span className="font-mono text-xs">
                      {selMastery === null ? 'unobserved' : selMastery.toFixed(2)}
                    </span>
                  </div>
                  <div className="h-1.5 bg-rule relative">
                    <div
                      className={
                        selMastery === null
                          ? 'bg-rule'
                          : selMastery < 0.4
                          ? 'bg-alarm'
                          : selMastery < 0.7
                          ? 'bg-amber'
                          : 'bg-mastery'
                      }
                      style={{
                        width: `${(selMastery ?? 0) * 100}%`,
                        position: 'absolute',
                        inset: '0 auto 0 0',
                      }}
                    />
                  </div>
                </div>

                {blockedBy.length > 0 && (
                  <div className="mt-6 border-l-2 border-alarm pl-4">
                    <p className="font-mono text-[10px] eyebrow text-alarm mb-2">
                      WEAK PREREQUISITES
                    </p>
                    <ul className="space-y-1">
                      {blockedBy.map((b) => (
                        <li key={b.id} className="font-mono text-xs">
                          {b.name}{' '}
                          <span className="text-faint">
                            {b.m === null ? '(unobserved)' : b.m.toFixed(2)}
                          </span>
                        </li>
                      ))}
                    </ul>
                  </div>
                )}

                <div className="mt-6">
                  <p className="font-mono text-[10px] eyebrow text-faint mb-2">UNLOCKS</p>
                  {unlocks.length ? (
                    <ul className="space-y-1">
                      {unlocks.map((u) => (
                        <li key={u} className="font-mono text-xs text-soft">{u}</li>
                      ))}
                    </ul>
                  ) : (
                    <p className="font-mono text-xs text-faint">Nothing downstream</p>
                  )}
                </div>

                <Link
                  href={`/study/session?concept=${encodeURIComponent(selected.concept_id)}`}
                  className="block text-center mt-7 font-mono text-xs border border-ink py-2.5 hover:bg-ink hover:text-paper transition-colors"
                >
                  Practise this concept
                </Link>
              </>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
'@

Write-ProjectFile 'web\src\components\dashboard\DiagnosisBanner.tsx' @'
import type { RootCause } from '@/lib/analytics'

export default function DiagnosisBanner({
  name,
  rootCause,
  confidentlyWrong,
}: {
  name: string
  rootCause: RootCause | null
  confidentlyWrong: number
}) {
  return (
    <div className="border border-rule bg-card">
      <div className="border-b border-rule px-6 py-3 flex flex-wrap items-center justify-between gap-3">
        <span className="font-mono text-[10px] eyebrow text-faint">DIAGNOSIS</span>
        {confidentlyWrong > 0 && (
          <span className="font-mono text-[10px] text-alarm">
            {confidentlyWrong} CONFIDENTLY WRONG
          </span>
        )}
      </div>

      <div className="px-6 py-7">
        <p className="font-mono text-[11px] eyebrow text-faint mb-4">
          {name.split(' ')[0].toUpperCase()}, START HERE
        </p>

        {!rootCause ? (
          <>
            <h1 className="font-display font-extrabold text-2xl md:text-[2rem] tight leading-tight max-w-2xl">
              Nothing has failed enough to trace yet.
            </h1>
            <p className="mt-4 text-soft leading-relaxed max-w-xl">
              Root-cause attribution needs failures to propagate. Answer more questions
              and the graph will start pointing somewhere.
            </p>
          </>
        ) : (
          <>
            {rootCause.isTraced ? (
              <>
                <h1 className="font-display font-extrabold text-2xl md:text-[2rem] tight leading-tight max-w-2xl">
                  Your {rootCause.failedConcept} failures trace down to{' '}
                  <span className="text-amber">{rootCause.rootConcept}</span>.
                </h1>
                <p className="mt-4 text-soft leading-relaxed max-w-xl">
                  {rootCause.failures} failure{rootCause.failures === 1 ? '' : 's'} on{' '}
                  {rootCause.failedConcept}. {Math.round(rootCause.share * 100)}% of the
                  blame lands on its weakest prerequisite, and the chain bottoms out at{' '}
                  {rootCause.rootConcept} (mastery{' '}
                  {rootCause.rootMastery.toFixed(2)}).
                </p>
              </>
            ) : (
              <>
                <h1 className="font-display font-extrabold text-2xl md:text-[2rem] tight leading-tight max-w-2xl">
                  <span className="text-amber">{rootCause.failedConcept}</span> is the gap
                  itself.
                </h1>
                <p className="mt-4 text-soft leading-relaxed max-w-xl">
                  {rootCause.failures} failure{rootCause.failures === 1 ? '' : 's'} here,
                  but every prerequisite is already solid. Nothing underneath is holding
                  you back, so this is worth attacking directly rather than going a level
                  down.
                </p>
              </>
            )}

            <div className="mt-6 border-t border-rule pt-5">
              <p className="font-mono text-[10px] eyebrow text-faint mb-4">
                {rootCause.isTraced ? 'BLAME TRACE' : 'PREREQUISITES CHECKED'}
              </p>
              <ol className="space-y-2.5">
                {rootCause.trace.map((s, i) => (
                  <li key={s.conceptId} className="flex items-center gap-4">
                    <span className="font-mono text-[10px] text-faint w-4 shrink-0">
                      {i === 0 ? 'x' : '>'}
                    </span>
                    <span className="font-mono text-xs w-44 shrink-0 truncate">
                      {s.concept}
                    </span>
                    <div className="flex-1 h-1.5 bg-rule relative min-w-[3rem]">
                      <div
                        className={i === rootCause.trace.length - 1 ? 'bg-amber' : 'bg-faint'}
                        style={{
                          width: `${s.share * 100}%`,
                          position: 'absolute',
                          inset: '0 auto 0 0',
                        }}
                      />
                    </div>
                    <span className="font-mono text-[10px] text-faint w-24 text-right shrink-0">
                      {Math.round(s.share * 100)}% &middot; m{s.mastery.toFixed(2)}
                    </span>
                  </li>
                ))}
              </ol>
              <p className="font-mono text-[10px] text-faint mt-4">
                {rootCause.isTraced
                  ? 'blame = edge weight \u00d7 (1 \u2212 mastery) \u00d7 uncertainty, normalised per level'
                  : 'propagation stopped: every prerequisite is above the 0.80 mastery threshold'}
              </p>
            </div>
          </>
        )}
      </div>
    </div>
  )
}
'@

Write-ProjectFile 'web\src\components\dashboard\EmptyState.tsx' @'
import Link from 'next/link'

export default function EmptyState({
  title,
  body,
  cta = 'Take the placement test',
  href = '/study/placement',
}: {
  title: string
  body: string
  cta?: string
  href?: string
}) {
  return (
    <div className="border border-rule bg-card px-6 py-10 text-center">
      <p className="font-display font-semibold text-lg tight">{title}</p>
      <p className="text-sm text-soft mt-3 max-w-md mx-auto leading-relaxed">{body}</p>
      <Link
        href={href}
        className="inline-block mt-6 font-mono text-xs border border-ink px-5 py-2.5 hover:bg-ink hover:text-paper transition-colors"
      >
        {cta}
      </Link>
    </div>
  )
}
'@

Write-ProjectFile 'web\src\components\dashboard\FixFirstQueue.tsx' @'
import Link from 'next/link'
import type { FixItem } from '@/lib/analytics'

export default function FixFirstQueue({ items }: { items: FixItem[] }) {
  return (
    <div className="border border-rule bg-card">
      <div className="border-b border-rule px-5 py-3 flex items-center justify-between">
        <p className="font-mono text-[10px] eyebrow text-faint">FIX FIRST</p>
        <span className="font-mono text-[10px] text-faint">NAMED BELIEFS</span>
      </div>
      {items.length === 0 ? (
        <div className="px-5 py-5">
          <p className="text-xs text-soft leading-relaxed">
            No diagnosed misconceptions yet. These appear when a wrong answer matches a
            distractor tagged to a specific false belief.
          </p>
        </div>
      ) : (
        <ol className="divide-y divide-rule">
          {items.map((it, i) => (
            <li key={it.belief} className="px-5 py-4">
              <div className="flex items-baseline justify-between gap-3 mb-1.5">
                <Link
                  href={`/study/session?concept=${encodeURIComponent(it.conceptId)}`}
                  className="font-mono text-[11px] truncate hover:text-blueprint"
                >
                  <span className="text-faint mr-2">{String(i + 1).padStart(2, '0')}</span>
                  {it.concept}
                </Link>
                <span className="font-mono text-[10px] text-amber shrink-0">
                  {it.times}x
                </span>
              </div>
              <p className="text-xs text-soft leading-relaxed">{it.belief}</p>
              <p className="font-mono text-[10px] text-faint mt-1.5">{it.subject}</p>
            </li>
          ))}
        </ol>
      )}
    </div>
  )
}
'@

Write-ProjectFile 'web\src\components\dashboard\MasteryBar.tsx' @'
export default function MasteryBar({
  mastery,
  observations,
}: {
  mastery: number
  observations: number
}) {
  const thin = observations < 4
  const color = mastery < 0.4 ? 'bg-alarm' : mastery < 0.7 ? 'bg-amber' : 'bg-mastery'

  // Rough interval: shrinks as observations accumulate. Communicates
  // "we are not sure yet" without pretending to a calibrated CI.
  const spread = Math.min(0.45, 0.5 / Math.sqrt(observations + 1))
  const lo = Math.max(0, mastery - spread)
  const hi = Math.min(1, mastery + spread)

  return (
    <div>
      <div className="h-1.5 bg-rule relative">
        {thin && (
          <div
            className="absolute inset-y-0 bg-rule border-x border-faint/40"
            style={{ left: `${lo * 100}%`, width: `${(hi - lo) * 100}%` }}
          />
        )}
        <div
          className={`${color} ${thin ? 'opacity-50' : ''}`}
          style={{ width: `${mastery * 100}%`, position: 'absolute', inset: '0 auto 0 0' }}
        />
      </div>
      <p className="font-mono text-[10px] text-faint mt-1.5">
        {thin ? (
          <>
            <span className="text-amber">provisional</span> &middot; {observations}{' '}
            observation{observations === 1 ? '' : 's'}
          </>
        ) : (
          <>mastery {mastery.toFixed(2)} &middot; {observations} observations</>
        )}
      </p>
    </div>
  )
}
'@

Write-ProjectFile 'web\src\components\dashboard\MasteryBySubject.tsx' @'
import type { SubjectMastery } from '@/lib/analytics'

export default function MasteryBySubject({ subjects }: { subjects: SubjectMastery[] }) {
  return (
    <div className="border border-rule bg-card">
      <div className="border-b border-rule px-5 py-3">
        <p className="font-mono text-[10px] eyebrow text-faint">MASTERY BY SUBJECT</p>
      </div>
      <div className="px-5 py-5 space-y-4">
        {subjects.length === 0 && (
          <p className="text-xs text-soft leading-relaxed">
            Nothing observed yet. Mastery appears once you answer questions in a subject.
          </p>
        )}
        {subjects.map((s) => (
          <div key={s.subjectId}>
            <div className="flex items-baseline justify-between gap-3 mb-1.5">
              <span className="font-mono text-[11px] truncate">{s.subject}</span>
              <span className="font-mono text-[10px] text-faint shrink-0">
                {s.mastery.toFixed(2)}
              </span>
            </div>
            <div className="h-1.5 bg-rule relative">
              <div
                className={
                  s.mastery < 0.5 ? 'bg-alarm' : s.mastery < 0.7 ? 'bg-amber' : 'bg-mastery'
                }
                style={{ width: `${s.mastery * 100}%`, position: 'absolute', inset: '0 auto 0 0' }}
              />
            </div>
            <p className="font-mono text-[10px] text-faint mt-1.5">
              {s.observed} of {s.concepts} concepts observed
            </p>
          </div>
        ))}
      </div>
    </div>
  )
}
'@

Write-ProjectFile 'web\src\components\dashboard\PageHead.tsx' @'
export default function PageHead({
  eyebrow,
  title,
  lede,
  aside,
}: {
  eyebrow: string
  title: string
  lede: string
  aside?: React.ReactNode
}) {
  return (
    <div className="flex flex-wrap items-end justify-between gap-6 mb-8">
      <div>
        <p className="font-mono text-[11px] eyebrow text-faint mb-4">{eyebrow}</p>
        <h1 className="font-display font-extrabold text-3xl tight leading-tight">{title}</h1>
        <p className="mt-3 text-soft leading-relaxed max-w-xl">{lede}</p>
      </div>
      {aside}
    </div>
  )
}
'@

Write-ProjectFile 'web\src\components\dashboard\SettingsForm.tsx' @'
'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'

const EXAMS = [
  { id: 'tcs_nqt', name: 'TCS NQT' },
  { id: 'infosys_se', name: 'Infosys SE' },
  { id: 'amazon_sde1', name: 'Amazon SDE-1' },
  { id: '', name: 'Semester exams only' },
]

const TRACKED = [
  ['Tab focus and blur', 'When the study tab loses focus, and for how long.'],
  ['Idle gaps', 'No input for 45 seconds or more during a block.'],
  ['Response times', 'How long each answer takes, against the item median.'],
  ['Hour of day', 'Which hours your accuracy is highest in.'],
]

const NOT_TRACKED = [
  'Keystrokes or what you type outside answer fields',
  'Which other tabs or sites are open',
  'Anything at all when tracking is off',
]

export default function SettingsForm({
  email,
  displayName,
  weeklyMinutes,
  trackingOptIn,
  targetExamId,
}: {
  email: string
  displayName: string
  weeklyMinutes: number
  trackingOptIn: boolean
  targetExamId: string | null
}) {
  const supabase = createClient()

  const [name, setName] = useState(displayName)
  const [minutes, setMinutes] = useState(weeklyMinutes)
  const [tracking, setTracking] = useState(trackingOptIn)
  const [exam, setExam] = useState(targetExamId ?? '')
  const [busy, setBusy] = useState(false)
  const [saved, setSaved] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function save() {
    setBusy(true)
    setError(null)
    setSaved(false)

    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user) return

    const { error } = await supabase
      .from('profiles')
      .update({
        display_name: name,
        weekly_minutes: minutes,
        tracking_opt_in: tracking,
        target_exam_id: exam || null,
      })
      .eq('student_id', user.id)

    setBusy(false)
    if (error) setError(error.message)
    else setSaved(true)
  }

  return (
    <div className="grid xl:grid-cols-12 gap-7">
      <div className="xl:col-span-7 space-y-7">
        <section className="border border-rule bg-card">
          <div className="border-b border-rule px-6 py-3">
            <p className="font-mono text-[10px] eyebrow text-faint">ACCOUNT</p>
          </div>
          <div className="px-6 py-6 space-y-5">
            <label className="block">
              <span className="font-mono text-[10px] eyebrow text-faint">DISPLAY NAME</span>
              <input
                value={name}
                onChange={(e) => setName(e.target.value)}
                className="mt-2 w-full bg-paper border border-rule px-4 py-2.5 text-sm focus:border-ink focus:outline-none"
              />
            </label>
            <div>
              <span className="font-mono text-[10px] eyebrow text-faint">EMAIL</span>
              <p className="mt-2 font-mono text-sm text-soft">{email}</p>
            </div>
          </div>
        </section>

        <section className="border border-rule bg-card">
          <div className="border-b border-rule px-6 py-3">
            <p className="font-mono text-[10px] eyebrow text-faint">STUDY BUDGET</p>
          </div>
          <div className="px-6 py-6">
            <div className="flex items-baseline justify-between mb-3">
              <span className="font-mono text-xs">Minutes per week</span>
              <span className="font-display font-extrabold text-2xl tight">{minutes}</span>
            </div>
            <input
              type="range"
              min={60}
              max={1200}
              step={30}
              value={minutes}
              onChange={(e) => setMinutes(Number(e.target.value))}
              className="w-full accent-[#141A17]"
            />
            <p className="text-xs text-soft mt-3 leading-relaxed">
              The planner will not fill this if it cannot justify the time. Setting it
              high does not produce a busier plan, only a longer ceiling.
            </p>
          </div>
        </section>

        <section className="border border-rule bg-card">
          <div className="border-b border-rule px-6 py-3">
            <p className="font-mono text-[10px] eyebrow text-faint">TARGET</p>
          </div>
          <div className="px-6 py-6">
            <div className="grid sm:grid-cols-2 gap-2">
              {EXAMS.map((e) => (
                <button
                  key={e.id || 'none'}
                  onClick={() => setExam(e.id)}
                  className={`font-mono text-xs px-4 py-3 border text-left transition-colors ${
                    exam === e.id
                      ? 'border-ink bg-ink text-paper'
                      : 'border-rule text-soft hover:border-ink hover:text-ink'
                  }`}
                >
                  {e.name}
                </button>
              ))}
            </div>
            <p className="text-xs text-soft mt-4 leading-relaxed">
              Changes topic weights in the planner. Your mastery estimates are unaffected.
            </p>
          </div>
        </section>
      </div>

      <div className="xl:col-span-5 space-y-7">
        <section
          className={`border-2 ${tracking ? 'border-blueprint' : 'border-rule'} bg-card`}
        >
          <div className="border-b border-rule px-5 py-3 flex items-center justify-between">
            <p className="font-mono text-[10px] eyebrow text-faint">ATTENTION TRACKING</p>
            <button
              onClick={() => setTracking(!tracking)}
              role="switch"
              aria-checked={tracking}
              className={`font-mono text-[10px] px-3 py-1.5 border transition-colors ${
                tracking
                  ? 'border-blueprint bg-blueprint text-paper'
                  : 'border-rule text-faint hover:border-ink hover:text-ink'
              }`}
            >
              {tracking ? 'ON' : 'OFF'}
            </button>
          </div>

          <div className="px-5 py-5">
            <p className="font-mono text-[10px] eyebrow text-faint mb-3">WHAT IS RECORDED</p>
            <ul className="space-y-3 mb-6">
              {TRACKED.map(([k, v]) => (
                <li key={k}>
                  <p className="font-mono text-[11px]">{k}</p>
                  <p className="text-xs text-soft mt-0.5 leading-relaxed">{v}</p>
                </li>
              ))}
            </ul>

            <p className="font-mono text-[10px] eyebrow text-faint mb-3">WHAT IS NOT</p>
            <ul className="space-y-1.5">
              {NOT_TRACKED.map((n) => (
                <li key={n} className="text-xs text-soft leading-relaxed">
                  {n}
                </li>
              ))}
            </ul>

            {!tracking && (
              <div className="border-l-2 border-amber bg-amber-wash px-4 py-3 mt-5">
                <p className="text-xs text-soft leading-relaxed">
                  With this off, blocks default to 25 minutes for everyone and the
                  focus half-life stays unmeasured.
                </p>
              </div>
            )}
          </div>
        </section>

        <div className="flex flex-wrap items-center gap-4">
          <button
            onClick={save}
            disabled={busy}
            className="font-mono text-sm bg-ink text-paper px-7 py-3.5 hover:bg-blueprint transition-colors disabled:opacity-50"
          >
            {busy ? 'Saving\u2026' : 'Save changes'}
          </button>
          {saved && <span className="font-mono text-xs text-mastery">Saved</span>}
          {error && <span className="font-mono text-xs text-alarm">{error}</span>}
        </div>
      </div>
    </div>
  )
}
'@

Write-ProjectFile 'web\src\components\dashboard\SideRail.tsx' @'
'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'

const NAV = [
  { href: '/dashboard', label: 'Today' },
  { href: '/study', label: 'Study' },
  { href: '/dashboard/diagnosis', label: 'Diagnosis' },
  { href: '/dashboard/map', label: 'Concept map' },
  { href: '/dashboard/plan', label: 'Plan' },
  { href: '/dashboard/simulate', label: 'Simulate' },
  { href: '/dashboard/settings', label: 'Settings' },
]

export default function SideRail({ name }: { name: string }) {
  const path = usePathname()

  return (
    <aside className="lg:fixed lg:inset-y-0 lg:left-0 lg:w-56 bg-ink text-paper flex lg:flex-col z-40">
      <div className="px-6 py-5 lg:py-6 shrink-0">
        <Link href="/" className="font-display font-extrabold text-base tight">
          DIAGNOSTIC
        </Link>
      </div>

      <nav className="flex lg:flex-col gap-px overflow-x-auto lg:overflow-visible lg:mt-2 flex-1">
        {NAV.map((item) => {
          const active =
            item.href === '/study'
              ? path.startsWith('/study')
              : path === item.href
          return (
            <Link
              key={item.href}
              href={item.href}
              className={`font-mono text-xs px-6 py-3 whitespace-nowrap transition-colors ${
                active
                  ? 'bg-paper/10 text-paper border-l-2 border-amber'
                  : 'text-paper/50 hover:text-paper hover:bg-paper/5 border-l-2 border-transparent'
              }`}
            >
              {item.label}
            </Link>
          )
        })}
      </nav>

      <div className="hidden lg:block px-6 py-6 border-t border-paper/10">
        <p className="font-mono text-[10px] eyebrow text-paper/40 mb-1.5">SIGNED IN</p>
        <p className="font-mono text-xs text-paper/80 truncate">{name}</p>
        <Link
          href="/dashboard/settings"
          className="font-mono text-[10px] text-paper/40 hover:text-paper mt-3 inline-block"
        >
          Settings
        </Link>
      </div>
    </aside>
  )
}
'@

Write-ProjectFile 'web\src\components\dashboard\Simulator.tsx' @'
'use client'

import { useState } from 'react'

type Subject = {
  id: string
  name: string
  mastery: number
  weight: number   // exam weight for the current target
  ceiling: number  // diminishing returns kick in past this
}

const SUBJECTS: Subject[] = [
  { id: 'apt', name: 'Aptitude', mastery: 0.66, weight: 0.40, ceiling: 6 },
  { id: 'dsa', name: 'DSA', mastery: 0.43, weight: 0.25, ceiling: 10 },
  { id: 'dbms', name: 'DBMS', mastery: 0.71, weight: 0.15, ceiling: 5 },
  { id: 'cn', name: 'Computer Networks', mastery: 0.54, weight: 0.20, ceiling: 8 },
]

const BUDGET = 12

/** Mastery gain saturates: the first hour on a weak topic is worth far more
 *  than the sixth on a strong one. */
function projectedMastery(s: Subject, hours: number) {
  const room = 1 - s.mastery
  const gain = room * (1 - Math.exp(-hours / s.ceiling))
  return Math.min(0.98, s.mastery + gain)
}

function score(alloc: Record<string, number>) {
  return SUBJECTS.reduce(
    (a, s) => a + projectedMastery(s, alloc[s.id] ?? 0) * s.weight * 100,
    0
  )
}

const BASELINE = score({})

export default function Simulator() {
  const [alloc, setAlloc] = useState<Record<string, number>>({
    apt: 3, dsa: 3, dbms: 2, cn: 2,
  })

  const used = Object.values(alloc).reduce((a, b) => a + b, 0)
  const left = BUDGET - used
  const projected = score(alloc)
  const delta = projected - BASELINE

  function set(id: string, v: number) {
    const others = used - (alloc[id] ?? 0)
    setAlloc({ ...alloc, [id]: Math.min(v, BUDGET - others) })
  }

  // Best single extra hour, given the current allocation
  const bestNext = SUBJECTS.map((s) => ({
    name: s.name,
    gain: score({ ...alloc, [s.id]: (alloc[s.id] ?? 0) + 1 }) - projected,
  })).sort((a, b) => b.gain - a.gain)[0]

  return (
    <div className="grid xl:grid-cols-12 gap-7">
      <div className="xl:col-span-7">
        <div className="border border-rule bg-card">
          <div className="border-b border-rule px-6 py-3 flex items-center justify-between">
            <p className="font-mono text-[10px] eyebrow text-faint">ALLOCATE {BUDGET} HOURS</p>
            <p
              className={`font-mono text-[10px] ${left === 0 ? 'text-mastery' : 'text-amber'}`}
            >
              {left === 0 ? 'FULLY ALLOCATED' : `${left}H UNASSIGNED`}
            </p>
          </div>

          <div className="px-6 py-6 space-y-7">
            {SUBJECTS.map((s) => {
              const h = alloc[s.id] ?? 0
              const after = projectedMastery(s, h)
              return (
                <div key={s.id}>
                  <div className="flex flex-wrap items-baseline justify-between gap-3 mb-2">
                    <span className="font-mono text-xs">{s.name}</span>
                    <span className="font-mono text-[10px] text-faint">
                      weight {s.weight.toFixed(2)} &middot; {s.mastery.toFixed(2)}{' '}
                      &rarr; <span className="text-ink">{after.toFixed(2)}</span>
                    </span>
                  </div>

                  <input
                    type="range"
                    min={0}
                    max={BUDGET}
                    value={h}
                    onChange={(e) => set(s.id, Number(e.target.value))}
                    className="w-full accent-[#141A17]"
                    aria-label={`Hours on ${s.name}`}
                  />

                  <div className="flex items-center justify-between mt-1.5">
                    <span className="font-mono text-[10px] text-faint">{h}h</span>
                    <div className="flex-1 mx-4 h-1 bg-rule relative">
                      <div
                        className="bg-faint"
                        style={{ width: `${s.mastery * 100}%`, position: 'absolute', inset: '0 auto 0 0' }}
                      />
                      <div
                        className="bg-amber"
                        style={{
                          left: `${s.mastery * 100}%`,
                          width: `${(after - s.mastery) * 100}%`,
                          position: 'absolute',
                          top: 0,
                          bottom: 0,
                        }}
                      />
                    </div>
                  </div>
                </div>
              )
            })}
          </div>
        </div>
      </div>

      <div className="xl:col-span-5 space-y-7">
        <div className="border border-rule bg-ink text-paper px-6 py-7">
          <p className="font-mono text-[10px] eyebrow text-paper/50 mb-4">
            PROJECTED SCORE &middot; TCS NQT
          </p>
          <div className="flex items-baseline gap-4">
            <span className="font-display font-extrabold text-5xl tight">
              {projected.toFixed(0)}
            </span>
            <span className="font-mono text-sm text-amber">
              +{delta.toFixed(1)} from {BASELINE.toFixed(0)}
            </span>
          </div>
          <div className="h-2 bg-paper/10 mt-6 relative">
            <div
              className="bg-paper/30"
              style={{ width: `${BASELINE}%`, position: 'absolute', inset: '0 auto 0 0' }}
            />
            <div
              className="bg-amber"
              style={{
                left: `${BASELINE}%`,
                width: `${delta}%`,
                position: 'absolute',
                top: 0,
                bottom: 0,
              }}
            />
          </div>
          <p className="text-sm text-paper/60 mt-5 leading-relaxed">
            Gains saturate. The sixth hour on a subject you already know is worth a
            fraction of the first hour on one you do not.
          </p>
        </div>

        <div className="border-l-2 border-amber bg-amber-wash px-5 py-4">
          <p className="font-mono text-[10px] eyebrow text-amber mb-2">BEST NEXT HOUR</p>
          <p className="text-sm">
            One more hour on <span className="font-semibold">{bestNext.name}</span> adds{' '}
            {bestNext.gain.toFixed(2)} points &mdash; more than any other single hour
            from here.
          </p>
        </div>

        <div className="border border-rule bg-card px-5 py-5">
          <p className="font-mono text-[10px] eyebrow text-faint mb-3">WHAT THIS IGNORES</p>
          <p className="text-xs text-soft leading-relaxed">
            Forgetting between now and the exam, and the fact that unlocking a
            prerequisite raises the ceiling on everything above it. The scheduler
            accounts for both; this slider does not.
          </p>
        </div>
      </div>
    </div>
  )
}
'@

Write-ProjectFile 'web\src\components\dashboard\StatStrip.tsx' @'
export default function StatStrip({
  attemptCount,
  focusHalfLife,
  sessionsTracked,
  activeMinutes,
  namedBeliefs,
}: {
  attemptCount: number
  focusHalfLife: number | null
  sessionsTracked: number
  activeMinutes: number
  namedBeliefs: number
}) {
  const stats = [
    {
      label: 'ATTEMPTS RECORDED',
      value: String(attemptCount),
      note: `${activeMinutes.toFixed(0)} tracked active minutes`,
      tone: 'text-ink',
    },
    {
      label: 'NAMED BELIEFS OPEN',
      value: String(namedBeliefs),
      note: namedBeliefs ? 'Wrong answers with a diagnosed cause' : 'No tagged misconceptions yet',
      tone: namedBeliefs ? 'text-amber' : 'text-faint',
    },
    {
      label: 'FOCUS HALF-LIFE',
      value: focusHalfLife ? `${focusHalfLife}m` : '--',
      note: focusHalfLife
        ? 'Blocks sized to match'
        : sessionsTracked < 5
        ? `Needs 5 tracked sessions (${sessionsTracked} so far)`
        : 'Curve not yet separable from noise; using the default block length',
      tone: focusHalfLife ? 'text-blueprint' : 'text-faint',
    },
  ]

  return (
    <div className="grid sm:grid-cols-3 gap-px bg-rule border border-rule">
      {stats.map((s) => (
        <div key={s.label} className="bg-card px-6 py-5">
          <p className="font-mono text-[10px] eyebrow text-faint mb-3">{s.label}</p>
          <p className={`font-display font-extrabold text-3xl tight ${s.tone}`}>{s.value}</p>
          <p className="text-xs text-soft mt-2 leading-relaxed">{s.note}</p>
        </div>
      ))}
    </div>
  )
}
'@

Write-ProjectFile 'web\src\components\study\CodeRunner.tsx' @'
'use client'

import { useEffect, useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import { useStudySession } from '@/hooks/useStudySession'
import { useTypingTelemetry } from '@/hooks/useTypingTelemetry'
import {
  runRemote,
  runPython,
  loadPyodide,
  type TestCase,
  type TestResult,
} from '@/lib/runners'

type Starter = {
  language: string
  label: string
  starter_code: string
  is_runnable: boolean
}

type Problem = {
  problem_id: string
  title: string
  prompt: string
  starter_code: string
  difficulty: number
  concept_id: string | null
  language_label: string | null
  coding_tests: TestCase[]
  problem_starters: Starter[]
}

/** Older rows stored a literal backslash-n. Repair on read. */
function normalise(code: string) {
  return code.replace(/\\n/g, '\n').replace(/\\t/g, '  ')
}

function difficultyLabel(d: number) {
  if (d < -0.4) return 'EASY'
  if (d < 0.4) return 'MEDIUM'
  return 'HARD'
}

const FALLBACK_STARTERS: Record<string, string> = {
  cpp: 'int solve() {\n    // your code here\n}',
  java: 'static int solve() {\n    // your code here\n}',
  python: 'def solve():\n    # your code here\n    pass',
}

const EXT: Record<string, string> = { cpp: 'CPP', java: 'JAVA', python: 'PY' }

// Python runs in the browser. Everything else is compiled on the server.
const LOCAL_LANGS = new Set(['python'])

const ORDER = ['cpp', 'java', 'python']

export default function CodeRunner({
  problems,
  trackingOptIn,
}: {
  problems: Problem[]
  trackingOptIn: boolean
}) {
  const [pi, setPi] = useState(0)
  const problem = problems[pi]

  const starters = useMemo(() => {
    const list = [...(problem.problem_starters ?? [])].sort(
      (a, b) => ORDER.indexOf(a.language) - ORDER.indexOf(b.language)
    )
    if (list.length > 0) return list
    // Migration 005 not run: fall back to the single stored starter.
    return [
      {
        language: 'cpp',
        label: 'C++',
        starter_code: problem.starter_code,
        is_runnable: true,
      },
    ]
  }, [problem])

  const [lang, setLang] = useState(starters[0]?.language ?? 'cpp')

  const starterFor = (language: string) =>
    normalise(
      starters.find((s) => s.language === language)?.starter_code ??
        FALLBACK_STARTERS[language] ??
        ''
    )

  const [code, setCode] = useState(() => starterFor(lang))
  const [results, setResults] = useState<TestResult[] | null>(null)
  const [runError, setRunError] = useState<string | null>(null)
  const [running, setRunning] = useState(false)
  const [pyStatus, setPyStatus] = useState<'idle' | 'loading' | 'ready' | 'failed'>('idle')
  const taRef = useRef<HTMLTextAreaElement>(null)

  // Warm Pyodide as soon as Python is chosen, so Run is not the slow step.
  useEffect(() => {
    if (lang !== 'python' || pyStatus !== 'idle') return
    setPyStatus('loading')
    loadPyodide()
      .then(() => setPyStatus('ready'))
      .catch(() => setPyStatus('failed'))
  }, [lang, pyStatus])

  const session = useStudySession({ plannedMinutes: 25, enabled: trackingOptIn })
  const typing = useTypingTelemetry({
    sessionId: session.sessionId,
    enabled: trackingOptIn,
  })

  const lines = useMemo(() => code.split('\n').length, [code])

  function selectProblem(i: number) {
    const next = problems[i]
    const list = next.problem_starters ?? []
    const keep = list.some((s) => s.language === lang) ? lang : list[0]?.language ?? 'cpp'
    setPi(i)
    setLang(keep)
    setCode(
      normalise(
        list.find((s) => s.language === keep)?.starter_code ??
          next.starter_code ??
          FALLBACK_STARTERS[keep] ??
          ''
      )
    )
    setResults(null)
    setRunError(null)
  }

  function switchLanguage(next: string) {
    if (next === lang) return
    const untouched = code.trim() === starterFor(lang).trim()
    if (!untouched && !confirm('Switch language? Your current code will be replaced.')) {
      return
    }
    setLang(next)
    setCode(starterFor(next))
    setResults(null)
    setRunError(null)
  }

  async function run() {
    setRunning(true)
    setRunError(null)
    const outcome = LOCAL_LANGS.has(lang)
      ? await runPython(code, problem.coding_tests)
      : await runRemote(problem.problem_id, lang, code)
    setRunning(false)
    setResults(outcome.results)
    setRunError(outcome.error)
    typing.noteRun(!outcome.error && outcome.results.every((x) => x.passed))
  }

  const passed = results?.filter((r) => r.passed).length ?? 0
  const fi = typing.liveFocus ?? typing.focusIndex
  const live = typing.live

  return (
    <main className="px-6 lg:px-10 py-8 pb-20">
      <div className="flex flex-wrap items-end justify-between gap-4 mb-7">
        <div>
          <p className="font-mono text-[11px] eyebrow text-faint mb-3">
            CODE PRACTICE &middot; {difficultyLabel(problem.difficulty)}
          </p>
          <h1 className="font-display font-extrabold text-2xl tight">{problem.title}</h1>
        </div>
        <div className="flex gap-2">
          {problems.map((p, i) => (
            <button
              key={p.problem_id}
              onClick={() => selectProblem(i)}
              className={`font-mono text-[10px] px-3 py-2 border transition-colors ${
                i === pi
                  ? 'border-ink bg-ink text-paper'
                  : 'border-rule text-soft hover:border-ink hover:text-ink'
              }`}
            >
              {p.title}
            </button>
          ))}
        </div>
      </div>

      <div className="grid xl:grid-cols-12 gap-7">
        <div className="xl:col-span-8 space-y-5">
          <div className="border border-rule bg-card px-6 py-5">
            <p className="text-sm leading-relaxed">{problem.prompt}</p>
          </div>

          <div className="border border-rule bg-card">
            <div className="border-b border-rule px-4 py-2.5 flex flex-wrap items-center justify-between gap-3">
              <div className="flex items-center gap-3">
                <div className="flex gap-px bg-rule border border-rule">
                  {starters.map((st) => (
                    <button
                      key={st.language}
                      onClick={() => switchLanguage(st.language)}
                      className={`font-mono text-[10px] px-3 py-1.5 transition-colors ${
                        lang === st.language
                          ? 'bg-ink text-paper'
                          : 'bg-card text-soft hover:text-ink'
                      }`}
                    >
                      {st.label}
                    </button>
                  ))}
                </div>
                <span className="font-mono text-[10px] eyebrow text-faint">
                  SOLUTION.{EXT[lang] ?? 'TXT'} &middot; {lines} LINES
                </span>
              </div>
              <button
                onClick={run}
                disabled={running || (lang === 'python' && pyStatus === 'loading')}
                className="font-mono text-xs border border-ink px-4 py-1.5 hover:bg-ink hover:text-paper transition-colors disabled:opacity-50"
              >
                {running
                  ? 'Running...'
                  : lang === 'python' && pyStatus === 'loading'
                  ? 'Loading Python...'
                  : 'Run tests'}
              </button>
            </div>
            <textarea
              ref={taRef}
              value={code}
              onChange={(e) => setCode(e.target.value)}
              onKeyDown={typing.onKeyDown}
              spellCheck={false}
              rows={16}
              className="w-full bg-card font-mono text-sm px-4 py-4 resize-y focus:outline-none leading-relaxed"
              style={{ tabSize: 2 }}
            />
            <div className="border-t border-rule px-4 py-2.5">
              <p className="font-mono text-[10px] text-faint leading-relaxed">
                {lang === 'python' ? (
                  <>
                    Runs in your browser through Pyodide, so it works without a
                    connection once loaded. Define <span className="text-ink">solve</span>{' '}
                    and <span className="text-ink">return</span> the answer.{' '}
                    {pyStatus === 'loading' && 'Downloading the runtime, about 10 MB, once per visit.'}
                    {pyStatus === 'failed' && (
                      <span className="text-alarm">Runtime unreachable. Try C++ or Java.</span>
                    )}
                  </>
                ) : (
                  <>
                    Compiled and run on the server. Write only the{' '}
                    <span className="text-ink">solve</span> function &mdash; includes,{' '}
                    {lang === 'java' ? 'the class wrapper' : 'headers'} and main() are
                    generated for you. Needs a network connection.
                  </>
                )}
              </p>
            </div>
          </div>

          {(results || runError) && (
            <div className="border border-rule bg-card">
              <div className="border-b border-rule px-4 py-2.5 flex items-center justify-between">
                <span className="font-mono text-[10px] eyebrow text-faint">RESULTS</span>
                {results && (
                  <span
                    className={`font-mono text-[10px] ${
                      passed === results.length ? 'text-mastery' : 'text-alarm'
                    }`}
                  >
                    {passed} / {results.length} PASSED
                  </span>
                )}
              </div>
              <div className="px-4 py-4">
                {runError ? (
                  <p className="font-mono text-xs text-alarm">{runError}</p>
                ) : (
                  <ul className="space-y-2">
                    {results!.map((r) => (
                      <li key={r.ordinal} className="font-mono text-xs flex flex-wrap gap-3">
                        <span className={r.passed ? 'text-mastery' : 'text-alarm'}>
                          {r.passed ? 'PASS' : 'FAIL'}
                        </span>
                        <span className="text-faint">
                          {r.hidden ? 'hidden test' : `test ${r.ordinal + 1}`}
                        </span>
                        {!r.passed && !r.hidden && (
                          <span className="text-soft">
                            got {r.got} &middot; want {r.want}
                          </span>
                        )}
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            </div>
          )}
        </div>

        <div className="xl:col-span-4 space-y-5">
          {!trackingOptIn ? (
            <div className="border-l-2 border-amber bg-amber-wash px-5 py-4">
              <p className="font-mono text-[10px] eyebrow text-amber mb-2">TRACKING OFF</p>
              <p className="text-xs text-soft leading-relaxed">
                Typing rhythm is not being recorded, so this session will not refine your
                focus model.{' '}
                <Link href="/dashboard/settings" className="text-ink border-b border-rule">
                  Turn it on
                </Link>
                .
              </p>
            </div>
          ) : (
            <>
              <div className="border border-rule bg-card">
                <div className="border-b border-rule px-5 py-3 flex items-center justify-between">
                  <p className="font-mono text-[10px] eyebrow text-faint">FOCUS SIGNAL</p>
                  <span className="font-mono text-[10px] text-faint">
                    {typing.windowCount} window{typing.windowCount === 1 ? '' : 's'}
                  </span>
                </div>

                <div className="px-5 py-5">
                  {/* Window progress, so it is obvious something is happening */}
                  <div className="h-1 bg-rule relative mb-4">
                    <div
                      className="bg-blueprint absolute inset-y-0 left-0 transition-all duration-1000"
                      style={{ width: `${typing.windowProgress * 100}%` }}
                    />
                  </div>

                  {!typing.hasBaseline ? (
                    <>
                      <p className="font-display font-extrabold text-3xl tight text-faint">
                        {typing.charsThisWindow}
                        <span className="font-mono text-sm text-faint">
                          {' '}/ {typing.minChars} chars
                        </span>
                      </p>
                      <p className="text-xs text-soft mt-2 leading-relaxed">
                        Establishing your baseline. Keep typing &mdash; the first window
                        closes after 45 seconds and sets the reference everything else is
                        measured against.
                      </p>
                    </>
                  ) : (
                    <>
                      <p
                        className={`font-display font-extrabold text-3xl tight ${
                          (fi ?? 1) < 0.7
                            ? 'text-alarm'
                            : (fi ?? 1) < 0.9
                            ? 'text-amber'
                            : 'text-mastery'
                        }`}
                      >
                        {(fi ?? 1).toFixed(2)}
                      </p>
                      <p className="text-xs text-soft mt-2 leading-relaxed">
                        Relative to your own baseline this session. Not an absolute
                        measure, and not a claim about tiredness.
                      </p>
                      {(fi ?? 1) < 0.7 && (
                        <div className="border-l-2 border-alarm pl-4 mt-4">
                          <p className="text-xs text-alarm leading-relaxed">
                            Rhythm has drifted well below where you started. This is
                            usually the point to stop rather than push through.
                          </p>
                        </div>
                      )}
                    </>
                  )}
                </div>
              </div>

              {/* Live, unflushed metrics so there is feedback within seconds */}
              <div className="border border-rule bg-card">
                <div className="border-b border-rule px-5 py-3 flex items-center justify-between">
                  <p className="font-mono text-[10px] eyebrow text-faint">LIVE</p>
                  {typing.liveFocus !== null && (
                    <span className="font-mono text-[10px] text-blueprint">
                      idx {typing.liveFocus.toFixed(2)}
                    </span>
                  )}
                </div>
                {!live ? (
                  <div className="px-5 py-5">
                    <p className="text-xs text-soft leading-relaxed">
                      Start typing in the editor. Metrics appear after a few keystrokes.
                    </p>
                  </div>
                ) : (
                  <dl className="divide-y divide-rule font-mono text-xs">
                    {[
                      ['chars this window', live.charsTyped],
                      ['mean gap', live.meanIkiMs ? `${Math.round(live.meanIkiMs)}ms` : '--'],
                      ['rhythm sd', live.sdIkiMs ? `${Math.round(live.sdIkiMs)}ms` : '--'],
                      ['backspace rate', live.backspaceRate.toFixed(3)],
                      ['burst length', live.meanBurstLen ? live.meanBurstLen.toFixed(1) : '--'],
                      ['pauses over 2s', live.pausesOver2s],
                      ['pauses: thinking', live.pausesThinking],
                      ['pauses: lost', live.pausesLost],
                    ].map(([k, v]) => (
                      <div key={String(k)} className="px-5 py-2.5 flex justify-between gap-3">
                        <dt className="text-faint">{k}</dt>
                        <dd>{v}</dd>
                      </div>
                    ))}
                  </dl>
                )}
                <div className="border-t border-rule px-5 py-3">
                  <p className="font-mono text-[10px] text-faint leading-relaxed">
                    Aggregates only. No keystrokes or code content are stored.
                  </p>
                </div>
              </div>
            </>
          )}

          <button
            onClick={async () => {
              await typing.flush()
              await session.endSession('completed')
            }}
            className="w-full font-mono text-sm border border-ink py-3 hover:bg-ink hover:text-paper transition-colors"
          >
            End session
          </button>
        </div>
      </div>
    </main>
  )
}
'@

Write-ProjectFile 'web\src\components\study\PlacementRunner.tsx' @'
'use client'

import { useEffect, useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { useStudySession } from '@/hooks/useStudySession'

type Opt = { option_id: string; body: string; ordinal: number }
type Q = {
  question_id: string
  stem: string
  difficulty: number
  median_time_sec: number
  primary_concept_id: string
  concepts: { name: string; subject_id: string } | null
  options: Opt[]
}

type Result = {
  isCorrect: boolean
  errorType: string
  misconception: { label: string; remediation_note: string } | null
  correctAnswer: string | null
  concept: string | null
}

const CONF = [
  { v: 1, label: 'Not sure' },
  { v: 2, label: 'Fairly sure' },
  { v: 3, label: 'Certain' },
]

export default function PlacementRunner({
  questions,
  trackingOptIn,
}: {
  questions: Q[]
  trackingOptIn: boolean
}) {
  const router = useRouter()
  const [consented, setConsented] = useState(trackingOptIn)
  const [started, setStarted] = useState(false)

  const [i, setI] = useState(0)
  const [conf, setConf] = useState<number | null>(null)
  const [picked, setPicked] = useState<string | null>(null)
  const [result, setResult] = useState<Result | null>(null)
  const [busy, setBusy] = useState(false)
  const [shownAt, setShownAt] = useState(Date.now())
  const [log, setLog] = useState<{ correct: boolean; type: string }[]>([])
  const [done, setDone] = useState(false)

  const session = useStudySession({
    plannedMinutes: 12,
    enabled: started && consented,
  })

  const q = questions[i]
  const sorted = useMemo(
    () => (q ? [...q.options].sort((a, b) => a.ordinal - b.ordinal) : []),
    [q]
  )

  useEffect(() => {
    setShownAt(Date.now())
  }, [i])

  async function submit(optionId: string) {
    if (!conf || busy) return
    setBusy(true)
    setPicked(optionId)

    const res = await fetch('/api/attempt', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        questionId: q.question_id,
        optionId,
        confidence: conf,
        timeTakenSec: (Date.now() - shownAt) / 1000,
        sessionId: session.sessionId,
        minutesIntoSession:
          session.activeMinutes === null
            ? null
            : Number(session.activeMinutes.toFixed(2)),
      }),
    })

    const data: Result = await res.json()
    setResult(data)
    setLog((l) => [...l, { correct: data.isCorrect, type: data.errorType }])
    setBusy(false)
  }

  async function next() {
    if (i + 1 >= questions.length) {
      const first5 = log.slice(0, 5)
      const baseline = first5.length
        ? first5.filter((x) => x.correct).length / first5.length
        : undefined
      await session.endSession('completed', baseline)
      setDone(true)
      router.refresh()
      return
    }
    setI(i + 1)
    setConf(null)
    setPicked(null)
    setResult(null)
  }

  // ---------- Consent gate ----------
  if (!started) {
    return (
      <main className="min-h-screen flex items-center px-6 py-16">
        <div className="mx-auto max-w-2xl w-full">
          <p className="font-mono text-[11px] eyebrow text-blueprint mb-5">
            PLACEMENT TEST
          </p>
          <h1 className="font-display font-extrabold text-4xl tight leading-[1.1]">
            Twenty questions.<br />No score at the end.
          </h1>
          <p className="mt-6 text-soft leading-relaxed max-w-lg">
            Declare confidence before each answer. What comes back is a map of what
            you believe and how firmly, plus the concepts underneath your errors.
          </p>

          <div className="mt-10 border border-rule bg-card">
            <div className="border-b border-rule px-6 py-3">
              <p className="font-mono text-[10px] eyebrow text-faint">
                ATTENTION TRACKING &mdash; OPTIONAL
              </p>
            </div>
            <div className="px-6 py-6">
              <p className="text-sm text-soft leading-relaxed mb-5">
                If you turn this on, we record when the tab loses focus, gaps of 45
                seconds or more without input, and how long each answer takes. That is
                what measures your focus half-life and sizes your study blocks. We do
                not record keystrokes or which other tabs are open.
              </p>
              <button
                onClick={() => setConsented(!consented)}
                role="switch"
                aria-checked={consented}
                className={`font-mono text-xs px-4 py-2.5 border transition-colors ${
                  consented
                    ? 'border-blueprint bg-blueprint text-paper'
                    : 'border-rule text-soft hover:border-ink hover:text-ink'
                }`}
              >
                {consented ? 'TRACKING ON' : 'TRACKING OFF'}
              </button>
            </div>
          </div>

          <div className="mt-8 flex flex-wrap items-center gap-4">
            <button
              onClick={() => setStarted(true)}
              className="font-mono text-sm bg-ink text-paper px-8 py-4 hover:bg-blueprint transition-colors"
            >
              Begin
            </button>
            <Link href="/dashboard" className="font-mono text-xs text-faint hover:text-ink">
              Not now
            </Link>
          </div>
        </div>
      </main>
    )
  }

  // ---------- Completion ----------
  if (done) {
    const correct = log.filter((l) => l.correct).length
    const confWrong = log.filter((l) => l.type === 'misconception').length
    const guesses = log.filter((l) => l.type === 'guess').length

    return (
      <main className="min-h-screen flex items-center px-6 py-16">
        <div className="mx-auto max-w-2xl w-full">
          <p className="font-mono text-[11px] eyebrow text-blueprint mb-5">COMPLETE</p>
          <h1 className="font-display font-extrabold text-4xl tight leading-[1.1]">
            Mapped onto the graph.
          </h1>
          <p className="mt-6 text-soft leading-relaxed">
            {correct} of {log.length} correct &mdash; but that is the least useful number
            here. {confWrong} answers traced to a named misconception, and {guesses} correct
            answers came back too fast to credit.
          </p>
          <p className="font-mono text-xs text-faint mt-6">
            {session.tracking
              ? `Active time ${(session.activeMinutes ?? 0).toFixed(1)} min \u00b7 ${session.blurCount} tab switches`
              : 'Attention tracking was off for this session.'}
          </p>
          <Link
            href="/dashboard"
            className="inline-block mt-9 font-mono text-sm bg-ink text-paper px-8 py-4 hover:bg-blueprint transition-colors"
          >
            See your diagnosis
          </Link>
        </div>
      </main>
    )
  }

  // ---------- Question ----------
  return (
    <main className="min-h-screen px-6 py-10">
      <div className="mx-auto max-w-2xl">
        <div className="flex items-center justify-between gap-4 mb-8">
          <span className="font-mono text-[10px] eyebrow text-faint">
            {i + 1} / {questions.length}
          </span>
          <div className="flex-1 h-px bg-rule relative">
            <div
              className="absolute inset-y-0 left-0 bg-ink"
              style={{ width: `${(i / questions.length) * 100}%` }}
            />
          </div>
          {consented && (
            <span className="font-mono text-[10px] text-faint">
              {(session.activeMinutes ?? 0).toFixed(1)}m active
            </span>
          )}
        </div>

        <p className="font-mono text-[10px] eyebrow text-faint mb-4">
          {q.concepts?.subject_id?.toUpperCase()} &middot; {q.concepts?.name}
        </p>
        <p className="text-xl leading-relaxed mb-9">{q.stem}</p>

        <p className="font-mono text-[10px] eyebrow text-faint mb-3">
          HOW SURE ARE YOU?
        </p>
        <div className="flex flex-wrap gap-2 mb-9">
          {CONF.map((c) => (
            <button
              key={c.v}
              onClick={() => setConf(c.v)}
              disabled={!!result}
              className={`font-mono text-xs px-4 py-2.5 border transition-colors disabled:opacity-60 ${
                conf === c.v
                  ? 'border-ink bg-ink text-paper'
                  : 'border-rule text-soft hover:border-ink hover:text-ink'
              }`}
            >
              {c.label}
            </button>
          ))}
        </div>

        <div className="space-y-2">
          {sorted.map((o) => {
            const chosen = picked === o.option_id
            const isRight = result && o.body === result.correctAnswer
            return (
              <button
                key={o.option_id}
                onClick={() => submit(o.option_id)}
                disabled={!conf || !!result}
                className={`w-full text-left px-5 py-4 border transition-colors disabled:cursor-not-allowed ${
                  chosen && result && !result.isCorrect
                    ? 'border-alarm bg-alarm-wash'
                    : isRight
                    ? 'border-mastery bg-card'
                    : 'border-rule hover:border-ink disabled:hover:border-rule'
                } ${!conf ? 'opacity-50' : ''}`}
              >
                <span className="text-sm">{o.body}</span>
              </button>
            )
          })}
        </div>

        {!conf && (
          <p className="font-mono text-[10px] text-faint mt-4">
            Pick a confidence level first.
          </p>
        )}

        {result && (
          <div className="mt-8 border-t border-rule pt-6">
            <span
              className={`font-mono text-[10px] eyebrow px-2.5 py-1 ${
                result.errorType === 'misconception'
                  ? 'bg-alarm text-paper'
                  : result.errorType === 'mastered'
                  ? 'bg-mastery text-paper'
                  : 'bg-ink text-paper'
              }`}
            >
              {result.errorType.replace('_', ' ').toUpperCase()}
            </span>

            {result.misconception && (
              <div className="border-l-2 border-amber pl-4 mt-5">
                <p className="font-mono text-[10px] eyebrow text-faint mb-1.5">
                  NAMED BELIEF
                </p>
                <p className="text-sm">{result.misconception.label}</p>
                <p className="text-sm text-soft mt-2 leading-relaxed">
                  {result.misconception.remediation_note}
                </p>
              </div>
            )}

            <button
              onClick={next}
              className="mt-7 font-mono text-sm bg-ink text-paper px-7 py-3.5 hover:bg-blueprint transition-colors"
            >
              {i + 1 >= questions.length ? 'Finish' : 'Next question'}
            </button>
          </div>
        )}
      </div>
    </main>
  )
}
'@

Write-ProjectFile 'web\src\hooks\useStudySession.ts' @'
'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { createClient } from '@/lib/supabase/client'

const IDLE_MS = 45_000

/**
 * Owns the attention data for one study session.
 *
 * activeMinutes = wall clock MINUS time the tab was hidden MINUS idle gaps.
 * Everything downstream (the focus curve, block sizing, the fatigue cutoff)
 * is fitted against this number, so it must not be elapsed time.
 */
export function useStudySession(opts: {
  subjectId?: string
  plannedMinutes?: number
  enabled: boolean
}) {
  const supabase = createClient()
  const [sessionId, setSessionId] = useState<string | null>(null)
  const [activeMinutes, setActiveMinutes] = useState(0)

  const startedAt = useRef<number>(Date.now())
  const deadMs = useRef(0)          // hidden + idle time, accumulated
  const hiddenAt = useRef<number | null>(null)
  const idleAt = useRef<number | null>(null)
  const lastInput = useRef<number>(Date.now())
  const blurCount = useRef(0)
  const idleSeconds = useRef(0)
  const sessionRef = useRef<string | null>(null)

  const logEvent = useCallback(
    async (type: string, durationMs?: number) => {
      if (!sessionRef.current || !opts.enabled) return
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) return
      await supabase.from('focus_events').insert({
        session_id: sessionRef.current,
        student_id: user.id,
        event_type: type,
        duration_ms: durationMs ?? null,
      })
    },
    [supabase, opts.enabled]
  )

  // Open the session. Skipped entirely when tracking is off, so no
  // half-populated session rows are written.
  useEffect(() => {
    if (!opts.enabled) return
    let cancelled = false
    ;(async () => {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user || cancelled) return

      const { data } = await supabase
        .from('study_sessions')
        .insert({
          student_id: user.id,
          subject_id: opts.subjectId ?? null,
          planned_minutes: opts.plannedMinutes ?? null,
        })
        .select('session_id')
        .single()

      if (data && !cancelled) {
        sessionRef.current = data.session_id
        setSessionId(data.session_id)
      }
    })()
    return () => {
      cancelled = true
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [opts.enabled])

  // Tick active minutes once a second. Guarded on `enabled`: without the
  // input listeners there is nothing to clear an idle gap, so an unguarded
  // timer would freeze active time at exactly IDLE_MS and write that same
  // value onto every attempt.
  useEffect(() => {
    if (!opts.enabled) return
    const t = setInterval(() => {
      const now = Date.now()

      // Roll idle into dead time as it accrues
      if (!idleAt.current && now - lastInput.current > IDLE_MS && !hiddenAt.current) {
        idleAt.current = lastInput.current + IDLE_MS
        logEvent('idle_start')
      }

      let dead = deadMs.current
      if (hiddenAt.current) dead += now - hiddenAt.current
      if (idleAt.current) dead += now - idleAt.current

      setActiveMinutes(Math.max(0, (now - startedAt.current - dead) / 60000))
    }, 1000)
    return () => clearInterval(t)
  }, [opts.enabled, logEvent])

  // Visibility and input listeners
  useEffect(() => {
    if (!opts.enabled) return

    const onVisibility = () => {
      if (document.visibilityState === 'hidden') {
        hiddenAt.current = Date.now()
        blurCount.current += 1
        logEvent('tab_blur')
      } else if (hiddenAt.current) {
        const d = Date.now() - hiddenAt.current
        deadMs.current += d
        hiddenAt.current = null
        lastInput.current = Date.now()
        logEvent('tab_focus', d)
      }
    }

    const onInput = () => {
      const now = Date.now()
      if (idleAt.current) {
        const d = now - idleAt.current
        deadMs.current += d
        idleSeconds.current += Math.round(d / 1000)
        idleAt.current = null
        logEvent('idle_end', d)
      }
      lastInput.current = now
    }

    document.addEventListener('visibilitychange', onVisibility)
    for (const e of ['mousemove', 'keydown', 'scroll', 'click', 'touchstart']) {
      window.addEventListener(e, onInput, { passive: true })
    }
    return () => {
      document.removeEventListener('visibilitychange', onVisibility)
      for (const e of ['mousemove', 'keydown', 'scroll', 'click', 'touchstart']) {
        window.removeEventListener(e, onInput)
      }
    }
  }, [opts.enabled, logEvent])

  const endSession = useCallback(
    async (reason: string, baselineAccuracy?: number) => {
      if (!sessionRef.current) return
      await supabase
        .from('study_sessions')
        .update({
          ended_at: new Date().toISOString(),
          active_minutes: Number(activeMinutes.toFixed(2)),
          blur_count: blurCount.current,
          idle_seconds: idleSeconds.current,
          baseline_accuracy: baselineAccuracy ?? null,
          end_reason: reason,
        })
        .eq('session_id', sessionRef.current)
    },
    [supabase, activeMinutes]
  )

  return {
    sessionId,
    // null when tracking is off, so callers write NULL rather than a
    // meaningless constant into attempts.minutes_into_session.
    activeMinutes: opts.enabled ? activeMinutes : null,
    tracking: opts.enabled,
    blurCount: blurCount.current,
    endSession,
  }
}
'@

Write-ProjectFile 'web\src\hooks\useTypingTelemetry.ts' @'
'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { createClient } from '@/lib/supabase/client'

const WINDOW_MS = 120_000      // full aggregation window
const FIRST_WINDOW_MS = 45_000 // shorter first window so a baseline exists fast
const LIVE_MS = 1_500          // how often the on-screen readout refreshes
const MIN_CHARS = 20           // below this a window is too sparse to mean anything
const PAUSE_MS = 2_000         // gap that counts as a pause
const IKI_CAP_MS = 10_000      // gaps above this are pauses, not typing rhythm
const BURST_GAP_MS = 1_000     // gap that breaks an uninterrupted run
const EXIT_KEYS = 10           // keystrokes examined after a pause

export type WindowMetrics = {
  charsTyped: number
  meanIkiMs: number | null
  sdIkiMs: number | null
  backspaceRate: number
  pausesOver2s: number
  longestPauseMs: number
  meanBurstLen: number | null
  pausesThinking: number
  pausesLost: number
}

/**
 * Derives a focus signal from typing rhythm.
 *
 * Deliberately does NOT claim to detect drowsiness. It measures deviation
 * from the student's own baseline within the session, which is measurable;
 * "sleepy vs thinking hard" is not separable from keystrokes alone.
 *
 * Pauses are classified by how they END rather than how long they run: a
 * thinking pause resolves into a confident burst, a disengaged one resolves
 * into corrections.
 */
export function useTypingTelemetry(opts: {
  sessionId: string | null
  enabled: boolean
}) {
  const supabase = createClient()

  const keyTimes = useRef<number[]>([])
  const backspaces = useRef(0)
  const chars = useRef(0)
  const pauses = useRef<number[]>([])
  const pendingPause = useRef<{ at: number; corrections: number; keys: number } | null>(null)
  const thinking = useRef(0)
  const lost = useRef(0)
  const runAttempts = useRef(0)
  const runFailures = useRef(0)
  const windowStart = useRef(Date.now())

  const [baseline, setBaseline] = useState<WindowMetrics | null>(null)
  const [current, setCurrent] = useState<WindowMetrics | null>(null)
  const [focusIndex, setFocusIndex] = useState<number | null>(null)
  const [windowCount, setWindowCount] = useState(0)
  // Live, unflushed view of the window in progress. Purely for display, so
  // the student sees something within seconds instead of after two minutes.
  const [live, setLive] = useState<WindowMetrics | null>(null)
  const [liveFocus, setLiveFocus] = useState<number | null>(null)
  const [windowProgress, setWindowProgress] = useState(0)

  const compute = useCallback((): WindowMetrics => {
    const t = keyTimes.current
    const ikis: number[] = []
    const bursts: number[] = []
    let burst = 1

    for (let i = 1; i < t.length; i++) {
      const gap = t[i] - t[i - 1]
      if (gap <= IKI_CAP_MS) ikis.push(gap)
      if (gap <= BURST_GAP_MS) {
        burst++
      } else {
        bursts.push(burst)
        burst = 1
      }
    }
    bursts.push(burst)

    const mean = ikis.length ? ikis.reduce((a, b) => a + b, 0) / ikis.length : null
    const sd =
      mean !== null && ikis.length > 1
        ? Math.sqrt(ikis.reduce((a, g) => a + (g - mean) ** 2, 0) / (ikis.length - 1))
        : null

    return {
      charsTyped: chars.current,
      meanIkiMs: mean,
      sdIkiMs: sd,
      backspaceRate: chars.current ? backspaces.current / chars.current : 0,
      pausesOver2s: pauses.current.length,
      longestPauseMs: pauses.current.length ? Math.max(...pauses.current) : 0,
      meanBurstLen: bursts.length ? bursts.reduce((a, b) => a + b, 0) / bursts.length : null,
      pausesThinking: thinking.current,
      pausesLost: lost.current,
    }
  }, [])

  /** Higher is better. 1.0 means "typing like your session baseline". */
  const scoreAgainst = useCallback((m: WindowMetrics, base: WindowMetrics) => {
    const parts: number[] = []
    if (m.meanIkiMs && base.meanIkiMs) parts.push(base.meanIkiMs / m.meanIkiMs)
    if (m.sdIkiMs && base.sdIkiMs) parts.push(base.sdIkiMs / m.sdIkiMs)
    if (base.backspaceRate > 0.01) {
      parts.push(base.backspaceRate / Math.max(m.backspaceRate, 0.001))
    }
    if (m.meanBurstLen && base.meanBurstLen) parts.push(m.meanBurstLen / base.meanBurstLen)
    if (!parts.length) return null
    const raw = parts.reduce((a, b) => a + b, 0) / parts.length
    return Math.max(0, Math.min(1.6, raw))
  }, [])

  const flush = useCallback(async () => {
    if (!opts.enabled || chars.current < MIN_CHARS) return

    const m = compute()
    const minutesIn = (Date.now() - windowStart.current) / 60000

    setCurrent(m)
    setWindowCount((n) => n + 1)

    if (!baseline) {
      setBaseline(m)
      setFocusIndex(1)
    } else {
      setFocusIndex(scoreAgainst(m, baseline))
    }

    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (user) {
      await supabase.from('typing_windows').insert({
        session_id: opts.sessionId,
        student_id: user.id,
        minutes_into_session: Number(minutesIn.toFixed(2)),
        window_seconds: Math.round(WINDOW_MS / 1000),
        chars_typed: m.charsTyped,
        mean_iki_ms: m.meanIkiMs,
        sd_iki_ms: m.sdIkiMs,
        backspace_rate: m.backspaceRate,
        pauses_over_2s: m.pausesOver2s,
        longest_pause_ms: m.longestPauseMs,
        mean_burst_len: m.meanBurstLen,
        pauses_thinking: m.pausesThinking,
        pauses_lost: m.pausesLost,
        run_attempts: runAttempts.current,
        run_failures: runFailures.current,
      })
    }

    keyTimes.current = []
    backspaces.current = 0
    chars.current = 0
    pauses.current = []
    thinking.current = 0
    lost.current = 0
    runAttempts.current = 0
    runFailures.current = 0
    windowStart.current = Date.now()
  }, [opts.enabled, opts.sessionId, baseline, compute, scoreAgainst, supabase])

  // Flush completed windows. The first is short so a baseline exists early.
  useEffect(() => {
    if (!opts.enabled) return
    const ms = baseline ? WINDOW_MS : FIRST_WINDOW_MS
    const t = setInterval(flush, ms)
    return () => clearInterval(t)
  }, [opts.enabled, baseline, flush])

  // Live readout, refreshed every couple of seconds.
  useEffect(() => {
    if (!opts.enabled) return
    const t = setInterval(() => {
      const target = baseline ? WINDOW_MS : FIRST_WINDOW_MS
      setWindowProgress(
        Math.min(1, (Date.now() - windowStart.current) / target)
      )
      if (chars.current < 5) {
        setLive(null)
        setLiveFocus(null)
        return
      }
      const m = compute()
      setLive(m)
      setLiveFocus(baseline ? scoreAgainst(m, baseline) : null)
    }, LIVE_MS)
    return () => clearInterval(t)
  }, [opts.enabled, baseline, compute, scoreAgainst])

  const onKeyDown = useCallback(
    (e: { key: string }) => {
      if (!opts.enabled) return
      const now = Date.now()
      const last = keyTimes.current[keyTimes.current.length - 1]

      if (last && now - last > PAUSE_MS) {
        pauses.current.push(now - last)
        pendingPause.current = { at: now, corrections: 0, keys: 0 }
      }

      if (pendingPause.current) {
        const p = pendingPause.current
        p.keys++
        if (e.key === 'Backspace' || e.key === 'Delete') p.corrections++
        if (p.keys >= EXIT_KEYS) {
          // A pause that resolves into corrections is disengagement.
          // One that resolves into clean typing was thought.
          if (p.corrections / p.keys > 0.25) lost.current++
          else thinking.current++
          pendingPause.current = null
        }
      }

      keyTimes.current.push(now)
      if (e.key === 'Backspace' || e.key === 'Delete') backspaces.current++
      else if (e.key.length === 1) chars.current++
    },
    [opts.enabled]
  )

  const noteRun = useCallback((passed: boolean) => {
    runAttempts.current++
    if (!passed) runFailures.current++
  }, [])

  return {
    onKeyDown,
    noteRun,
    flush,
    focusIndex,
    current,
    baseline,
    windowCount,
    hasBaseline: baseline !== null,
    // live view of the in-progress window
    live,
    liveFocus,
    windowProgress,
    charsThisWindow: chars.current,
    minChars: MIN_CHARS,
  }
}
'@

Write-ProjectFile 'web\src\lib\analytics.ts' @'
import { createClient } from '@/lib/supabase/server'

/**
 * Real analytics computed from the student's own rows.
 *
 * Blame propagation and the diagnosis counts need no trained model, so they
 * produce genuine output from the first attempt onward. Anything that DOES
 * need fitting (forgetting half-life, focus curve) returns null here and the
 * UI says so rather than inventing a number.
 */

export type BlameStep = { concept: string; conceptId: string; share: number; mastery: number }

export type RootCause = {
  failedConcept: string
  failedConceptId: string
  rootConcept: string
  rootConceptId: string
  share: number
  rootMastery: number
  failures: number
  trace: BlameStep[]
  /** false when the prerequisites are solid and the weakness is the concept
   *  itself. That is a real diagnosis, not a missing one. */
  isTraced: boolean
}

export type SubjectMastery = {
  subject: string
  subjectId: string
  mastery: number
  concepts: number
  observed: number
}

export type FixItem = {
  concept: string
  conceptId: string
  subject: string
  blame: number
  belief: string
  times: number
}

export type DiagnosisCounts = {
  sureCorrect: number
  sureWrong: number
  unsureCorrect: number
  unsureWrong: number
  total: number
  errorMix: { kind: string; n: number }[]
}

export type Analytics = {
  attemptCount: number
  hasEnoughForDiagnosis: boolean
  rootCause: RootCause | null
  subjects: SubjectMastery[]
  fixFirst: FixItem[]
  diagnosis: DiagnosisCounts
  weakest: {
    conceptId: string
    name: string
    subjectId: string
    mastery: number
    observations: number
  }[]
  medianObservations: number
  thinEstimate: boolean
  focusHalfLife: number | null
  sessionsTracked: number
  activeMinutes: number
  decayingCount: number | null
}

const STOP_MASTERY = 0.8   // stop recursing into concepts the student knows
const MAX_DEPTH = 4

export async function getAnalytics(studentId: string): Promise<Analytics> {
  const supabase = await createClient()

  const [
    { data: attempts },
    { data: concepts },
    { data: prereqs },
    { data: mastery },
    { data: subjects },
    { data: sessions },
  ] = await Promise.all([
    supabase
      .from('attempts')
      .select(`
        attempt_id, is_correct, confidence, error_type, created_at,
        questions:question_id ( primary_concept_id ),
        options:chosen_option_id ( misconception_id,
          misconceptions:misconception_id ( label, concept_id ) )
      `)
      .eq('student_id', studentId)
      .order('created_at', { ascending: false })
      .limit(500),
    supabase.from('concepts').select('concept_id, name, subject_id, level'),
    supabase.from('prerequisites').select('parent_id, child_id, weight'),
    supabase
      .from('mastery')
      .select('concept_id, mastery_prob, uncertainty, observation_count')
      .eq('student_id', studentId),
    supabase.from('subjects').select('subject_id, name'),
    supabase
      .from('study_sessions')
      .select('session_id, active_minutes, started_at')
      .eq('student_id', studentId)
      .not('active_minutes', 'is', null),
  ])

  const A = attempts ?? []
  const C = concepts ?? []
  const P = prereqs ?? []
  const M = mastery ?? []
  const S = subjects ?? []
  const SESS = sessions ?? []

  const conceptById = new Map(C.map((c) => [c.concept_id, c]))
  const masteryById = new Map(
    M.map((m) => [
      m.concept_id,
      {
        p: Number(m.mastery_prob),
        u: Number(m.uncertainty),
        n: Number(m.observation_count ?? 0),
      },
    ])
  )
  const parentsOf = new Map<string, { id: string; w: number }[]>()
  for (const e of P) {
    const list = parentsOf.get(e.child_id) ?? []
    list.push({ id: e.parent_id, w: Number(e.weight) })
    parentsOf.set(e.child_id, list)
  }

  const mOf = (id: string) => masteryById.get(id)?.p ?? 0.15
  const uOf = (id: string) => masteryById.get(id)?.u ?? 1.0
  const nameOf = (id: string) => conceptById.get(id)?.name ?? id

  // ---------- Diagnosis counts ----------
  const diagnosis: DiagnosisCounts = {
    sureCorrect: 0,
    sureWrong: 0,
    unsureCorrect: 0,
    unsureWrong: 0,
    total: A.length,
    errorMix: [],
  }
  const mix = new Map<string, number>()
  for (const a of A) {
    const sure = (a.confidence ?? 2) === 3
    if (a.is_correct) sure ? diagnosis.sureCorrect++ : diagnosis.unsureCorrect++
    else sure ? diagnosis.sureWrong++ : diagnosis.unsureWrong++
    if (!a.is_correct && a.error_type) {
      mix.set(a.error_type, (mix.get(a.error_type) ?? 0) + 1)
    }
  }
  diagnosis.errorMix = [...mix.entries()]
    .map(([kind, n]) => ({ kind, n }))
    .sort((x, y) => y.n - x.n)

  // ---------- Failures by concept ----------
  const failuresByConcept = new Map<string, number>()
  for (const a of A) {
    if (a.is_correct) continue
    const q = a.questions as unknown as { primary_concept_id: string } | null
    if (!q?.primary_concept_id) continue
    failuresByConcept.set(
      q.primary_concept_id,
      (failuresByConcept.get(q.primary_concept_id) ?? 0) + 1
    )
  }

  // ---------- Blame propagation ----------
  // blame(p) = weight(p -> c) * (1 - mastery(p)) * uncertainty(p), normalised.
  function propagate(conceptId: string): BlameStep[] {
    const trace: BlameStep[] = [
      { concept: nameOf(conceptId), conceptId, share: 1, mastery: mOf(conceptId) },
    ]
    let current = conceptId
    for (let d = 0; d < MAX_DEPTH; d++) {
      const parents = parentsOf.get(current)
      if (!parents || parents.length === 0) break

      const scored = parents.map((p) => ({
        id: p.id,
        raw: p.w * (1 - mOf(p.id)) * uOf(p.id),
      }))
      const total = scored.reduce((a, s) => a + s.raw, 0)
      if (total <= 0) break

      scored.sort((a, b) => b.raw - a.raw)
      const top = scored[0]

      // Stop BEFORE appending a concept the student already knows. Appending
      // first and checking afterwards named strongly-mastered prerequisites
      // as root causes, which is the opposite of the point: the trace should
      // bottom out at the last genuinely weak concept.
      if (mOf(top.id) >= STOP_MASTERY) break

      trace.push({
        concept: nameOf(top.id),
        conceptId: top.id,
        share: top.raw / total,
        mastery: mOf(top.id),
      })
      current = top.id
    }
    return trace
  }

  let rootCause: RootCause | null = null
  const ranked = [...failuresByConcept.entries()].sort((a, b) => b[1] - a[1])
  if (ranked.length > 0) {
    const [failedId, failures] = ranked[0]
    const trace = propagate(failedId)
    const last = trace[trace.length - 1]

    // A trace of length 1 means every prerequisite is already solid, so the
    // weakness is the concept itself. Reported as such rather than suppressed:
    // "your prerequisites are fine, the gap is here" is exactly the kind of
    // answer the graph exists to give.
    rootCause = {
      failedConcept: nameOf(failedId),
      failedConceptId: failedId,
      rootConcept: last.concept,
      rootConceptId: last.conceptId,
      share: trace.length > 1 ? trace[1].share : 1,
      rootMastery: last.mastery,
      failures,
      trace,
      isTraced: trace.length > 1,
    }
  }

  // ---------- Fix-first queue, from named misconceptions ----------
  const beliefs = new Map<string, { label: string; conceptId: string; n: number }>()
  for (const a of A) {
    if (a.is_correct) continue
    const opt = a.options as unknown as {
      misconceptions: { label: string; concept_id: string } | null
    } | null
    const m = opt?.misconceptions
    if (!m) continue
    const key = m.label
    const prev = beliefs.get(key)
    beliefs.set(key, {
      label: m.label,
      conceptId: m.concept_id,
      n: (prev?.n ?? 0) + 1,
    })
  }
  const beliefTotal = [...beliefs.values()].reduce((a, b) => a + b.n, 0) || 1
  const fixFirst: FixItem[] = [...beliefs.values()]
    .sort((a, b) => b.n - a.n)
    .slice(0, 5)
    .map((b) => ({
      concept: nameOf(b.conceptId),
      conceptId: b.conceptId,
      subject: conceptById.get(b.conceptId)?.subject_id?.toUpperCase() ?? '',
      blame: b.n / beliefTotal,
      belief: b.label,
      times: b.n,
    }))

  // ---------- Mastery by subject ----------
  const subjectName = new Map(S.map((s) => [s.subject_id, s.name]))
  const bySubject = new Map<string, { sum: number; observed: number; total: number }>()
  for (const c of C) {
    const e = bySubject.get(c.subject_id) ?? { sum: 0, observed: 0, total: 0 }
    e.total++
    const m = masteryById.get(c.concept_id)
    if (m) {
      e.sum += m.p
      e.observed++
    }
    bySubject.set(c.subject_id, e)
  }
  const subjectStats: SubjectMastery[] = [...bySubject.entries()]
    .filter(([, e]) => e.observed > 0)
    .map(([id, e]) => ({
      subjectId: id,
      subject: subjectName.get(id) ?? id,
      mastery: e.sum / e.observed,
      concepts: e.total,
      observed: e.observed,
    }))
    .sort((a, b) => a.mastery - b.mastery)

  // ---------- Weakest observed concepts ----------
  const weakest = M.map((m) => ({
    conceptId: m.concept_id,
    name: nameOf(m.concept_id),
    subjectId: conceptById.get(m.concept_id)?.subject_id ?? '',
    mastery: Number(m.mastery_prob),
    observations: Number(m.observation_count ?? 0),
  }))
    .sort((a, b) => a.mastery - b.mastery)
    .slice(0, 6)

  // BKT is unstable at low observation counts: with one or two attempts per
  // concept the estimate is close to "did you get that single question right".
  // Surface that rather than presenting a volatile number as settled.
  const obsCounts = M.map((m) => Number(m.observation_count ?? 0)).sort((a, b) => a - b)
  const medianObservations = obsCounts.length
    ? obsCounts[Math.floor(obsCounts.length / 2)]
    : 0

  const activeMinutes = SESS.reduce((a, s) => a + Number(s.active_minutes ?? 0), 0)

  return {
    attemptCount: A.length,
    hasEnoughForDiagnosis: A.length >= 5,
    rootCause,
    subjects: subjectStats,
    fixFirst,
    diagnosis,
    weakest,
    medianObservations,
    thinEstimate: medianObservations < 4,
    // Needs the Python fitter and ~5 tracked sessions. Null until then.
    focusHalfLife: null,
    sessionsTracked: SESS.length,
    activeMinutes,
    decayingCount: null,
  }
}
'@

Write-ProjectFile 'web\src\lib\runners.ts' @'
'use client'

export type TestCase = {
  test_id: number
  input_json: string
  expect_json: string
  is_hidden: boolean
  ordinal: number
}

export type TestResult = {
  ordinal: number
  hidden: boolean
  passed: boolean
  got: string
  want: string
}

export type RunOutcome = { results: TestResult[]; error: string | null }

/**
 * Remote runner for compiled languages.
 *
 * C++ and Java have no practical browser runtime, so they are compiled and
 * executed server-side. main() is generated from the problem's type
 * signature, so the student writes only `solve`.
 */
export async function runRemote(
  problemId: string,
  language: string,
  code: string
): Promise<RunOutcome> {
  try {
    const res = await fetch('/api/run', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ problemId, language, code }),
    })
    const data = await res.json()
    if (!res.ok) return { results: [], error: data.error ?? `Request failed (${res.status})` }
    return { results: data.results ?? [], error: data.error ?? null }
  } catch {
    return {
      results: [],
      error: 'Could not reach the execution service. Python still runs offline.',
    }
  }
}

/* ------------------------------------------------------------------ */
/* Python via Pyodide                                                  */
/* ------------------------------------------------------------------ */

const PYODIDE_VERSION = 'v0.26.2'
const PYODIDE_URL = `https://cdn.jsdelivr.net/pyodide/${PYODIDE_VERSION}/full/`

type Pyodide = { runPython: (code: string) => unknown }

declare global {
  interface Window {
    loadPyodide?: (opts: { indexURL: string }) => Promise<Pyodide>
  }
}

let pyodidePromise: Promise<Pyodide> | null = null

/** Loads Pyodide once, on first use. Roughly 10 MB, so never eagerly. */
export function loadPyodide(): Promise<Pyodide> {
  if (pyodidePromise) return pyodidePromise

  pyodidePromise = new Promise<Pyodide>((resolve, reject) => {
    if (window.loadPyodide) {
      window.loadPyodide({ indexURL: PYODIDE_URL }).then(resolve).catch(reject)
      return
    }
    const script = document.createElement('script')
    script.src = `${PYODIDE_URL}pyodide.js`
    script.onload = () => {
      if (!window.loadPyodide) {
        reject(new Error('Pyodide loaded but the entry point is missing.'))
        return
      }
      window.loadPyodide({ indexURL: PYODIDE_URL }).then(resolve).catch(reject)
    }
    script.onerror = () =>
      reject(new Error('Could not reach the Pyodide CDN. Check your connection.'))
    document.head.appendChild(script)
  })

  return pyodidePromise
}

/**
 * Runs the student's Python and compares against the same JSON expectations
 * the JavaScript runner uses. separators=(',', ':') matters: json.dumps
 * inserts spaces by default and every comparison would fail.
 */
export async function runPython(code: string, tests: TestCase[]): Promise<RunOutcome> {
  let py: Pyodide
  try {
    py = await loadPyodide()
  } catch (e) {
    return { results: [], error: e instanceof Error ? e.message : String(e) }
  }

  const ordered = [...tests].sort((a, b) => a.ordinal - b.ordinal)
  const inputs = JSON.stringify(ordered.map((t) => t.input_json))

  const harness = `
import json, traceback

_user_globals = {}
_outputs = []
_fatal = None

try:
    exec(${JSON.stringify(code)}, _user_globals)
    _solve = _user_globals.get('solve')
    if not callable(_solve):
        _fatal = 'No function named solve was defined.'
except Exception:
    _fatal = traceback.format_exc(limit=1).strip().splitlines()[-1]

if _fatal is None:
    for _raw in json.loads(${JSON.stringify(inputs)}):
        try:
            _args = json.loads(_raw)
            _r = _solve(*_args)
            _outputs.append(json.dumps(_r, separators=(',', ':')))
        except Exception as _e:
            _outputs.append('threw: ' + type(_e).__name__ + ': ' + str(_e))

json.dumps({'fatal': _fatal, 'outputs': _outputs})
`

  let payload: { fatal: string | null; outputs: string[] }
  try {
    payload = JSON.parse(String(py.runPython(harness)))
  } catch (e) {
    return { results: [], error: e instanceof Error ? e.message : String(e) }
  }

  if (payload.fatal) return { results: [], error: payload.fatal }

  const results: TestResult[] = ordered.map((t, i) => {
    const got = payload.outputs[i] ?? 'no output'
    return {
      ordinal: t.ordinal,
      hidden: t.is_hidden,
      passed: got === t.expect_json,
      got,
      want: t.expect_json,
    }
  })

  return { results, error: null }
}
'@

Write-ProjectFile 'web\src\lib\supabase\client.ts' @'
import { createBrowserClient } from '@supabase/ssr'

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  )
}
'@

Write-ProjectFile 'web\src\lib\supabase\middleware.ts' @'
import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

const PROTECTED = ['/dashboard', '/study', '/plan', '/map']
const AUTH_PAGES = ['/login', '/signup']

export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request })

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value)
          )
          response = NextResponse.next({ request })
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options)
          )
        },
      },
    }
  )

  // Do not remove: this refreshes the auth token on every request.
  const {
    data: { user },
  } = await supabase.auth.getUser()

  const path = request.nextUrl.pathname

  if (!user && PROTECTED.some((p) => path.startsWith(p))) {
    const url = request.nextUrl.clone()
    url.pathname = '/login'
    url.searchParams.set('next', path)
    return NextResponse.redirect(url)
  }

  if (user && AUTH_PAGES.some((p) => path.startsWith(p))) {
    const url = request.nextUrl.clone()
    url.pathname = '/dashboard'
    url.search = ''
    return NextResponse.redirect(url)
  }

  return response
}
'@

Write-ProjectFile 'web\src\lib\supabase\server.ts' @'
import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'

export async function createClient() {
  const cookieStore = await cookies()

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll()
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options)
            )
          } catch {
            // Called from a Server Component. Middleware refreshes the session,
            // so this is safe to ignore.
          }
        },
      },
    }
  )
}
'@

Write-ProjectFile 'web\src\middleware.ts' @'
import { type NextRequest } from 'next/server'
import { updateSession } from '@/lib/supabase/middleware'

export async function middleware(request: NextRequest) {
  return await updateSession(request)
}

export const config = {
  matcher: [
    /*
     * Everything except static assets and image files.
     */
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
}
'@

if (Test-Path 'web\tailwind.config.ts') { Remove-Item 'web\tailwind.config.ts' }
if (Test-Path 'web\tailwind.config.js') { Remove-Item 'web\tailwind.config.js' }

foreach ($d in @('content\dbms','content\cn','content\os','docs')) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green