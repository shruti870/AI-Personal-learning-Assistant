"""
Evaluation and ablation.

Produces the numbers a results section needs, and â€” more importantly â€” the
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
    construction â€” which is the point of the ablation.
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