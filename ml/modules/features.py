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