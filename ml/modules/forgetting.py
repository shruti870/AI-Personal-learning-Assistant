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