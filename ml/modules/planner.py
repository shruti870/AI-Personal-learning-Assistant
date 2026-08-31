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