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