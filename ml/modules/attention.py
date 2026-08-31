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