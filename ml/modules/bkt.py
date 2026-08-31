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