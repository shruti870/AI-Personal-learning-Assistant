# AI Personal Learning Assistant

A study assistant for campus placement preparation (aptitude, reasoning, DSA, DBMS, OS, computer networks). It goes beyond a quiz score: it estimates what each student knows concept by concept, traces wrong answers back to the prerequisite that actually causes them, and builds a weekly plan sized to how long the student stays focused.

## What it does

| Feature | Where | How |
|---|---|---|
| Placement test (20 questions, stratified by subject and difficulty) | `/study/placement` | Student states confidence before answering |
| Concept drills | `/study/session?concept=…` | Same runner, one concept |
| Code practice (Python in the browser, C++/Java on a remote judge) | `/study/code` | Typing rhythm feeds the attention model |
| Knowledge tracing (mastery per concept) | Postgres trigger + `ml/modules/bkt.py` | Bayesian Knowledge Tracing, confidence-adjusted |
| Root-cause diagnosis | `/dashboard`, `/dashboard/diagnosis` | Blame propagated down the prerequisite graph |
| Named misconceptions | Answer feedback | Wrong options are tagged with the belief behind them |
| AI tutor | "Explain my mistake" after a wrong answer | Claude explains the error, using the misconception and weakest prerequisite |
| Focus half-life | `ml/modules/attention.py` | Accuracy decay within a session, from tab/idle tracking (opt-in) |
| Forgetting curve | `ml/modules/forgetting.py` | Per-student retention half-life, fitted by maximum likelihood |
| Weekly plan | `/dashboard/plan` | Priority = room to gain x blame x exam weight x urgency x readiness |
| Target exam (TCS NQT, Infosys SE, Amazon SDE-1) | `/dashboard/settings` | Re-weights the plan and simulator by subject |
| What-if simulator | `/dashboard/simulate` | Projects readiness from the student's own mastery |

## Architecture

```
web/  Next.js 16 + Supabase auth ──► Supabase Postgres (supabase/migrations)
          │  /api/attempt   grade an answer, trigger updates mastery
          │  /api/recompute ──► ml/ FastAPI: refit mastery, focus, forgetting, plan
          │  /api/explain   ──► Claude API (AI tutor)
          │  /api/run       ──► public code judge (C++/Java)
ml/   FastAPI + pandas/scipy/scikit-learn, reads and writes the same Postgres
```

## Setup

You need Node 22.18+ (or 23.6+; `npm test` runs TypeScript directly), Python 3.12, and a Supabase project.

### 1. Database

In the Supabase SQL editor, run every file in `supabase/migrations/` in order (`001` to `009`). They are safe to re-run. `009` hides the answer key from students, so set `SUPABASE_SERVICE_ROLE_KEY` (below) before using the app after running it.

### 2. Web app

```bash
cd web
cp .env.example .env.local      # fill in the values
npm install
npm run dev                     # http://localhost:3000
```

| Variable | What it is |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase -> Project Settings -> API |
| `SUPABASE_SERVICE_ROLE_KEY` | Same page, the `service_role` key. Server-only: used to grade answers, since students cannot read the answer key. Never prefix it with `NEXT_PUBLIC_` |
| `ML_URL` | Where the ML service runs (default `http://localhost:8000`) |
| `ML_API_KEY` | Shared secret with the ML service; empty is fine locally |
| `ANTHROPIC_API_KEY` | For the AI tutor; without it the button says it is not set up |

### 3. ML service

```bash
cd ml
python3.12 -m venv venv && source venv/bin/activate   # Windows: venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env            # DATABASE_URL from Supabase -> Database -> Connection string
uvicorn main:app --reload       # http://localhost:8000/docs
```

Use the **Session pooler** connection string if the direct one is refused (common on college networks). Set `ML_API_KEY` (same value in both `.env` files) before exposing the service anywhere.

### 4. Tests

```bash
cd web && npm test              # unit tests (node --test)
cd ml  && pip install -r requirements-dev.txt && pytest
```

## Demo walkthrough

1. Sign up, open **Settings**, turn on attention tracking, and pick a target exam.
2. Take the **placement test**. Answer some questions wrong on purpose and press **Explain my mistake** to show the AI tutor.
3. Open the **dashboard**: weakest concepts, root-cause banner and named misconceptions are computed straight away.
4. Press **Refresh analysis**. The ML service fits the models and writes a plan.
5. Open **Plan**: blocks by day with a plain-English reason each. Mark one done.
6. Open **Simulate** and move hours between subjects.
7. Change the target exam in Settings, press **Regenerate plan**, and show how the plan shifts.

To have data for every panel without studying for a week, generate a synthetic cohort first: `python synth.py --students 30 --days 21` in `ml/`, then `curl -X POST localhost:8000/recompute-all`. See `ml/README.md`.

## Results (synthetic cohort, `docs/evaluation.json`)

31 students, 8,928 training and 2,247 test attempts.

| Model | Next-answer AUC | Calibration error (ECE) | Root-cause precision |
|---|---|---|---|
| Full system | 0.555 | 0.078 | 0.32 |
| Without confidence | 0.557 | 0.069 | 0.32 |
| Without forgetting | 0.535 | 0.196 | 0.32 |
| Without prerequisite blame | 0.555 | 0.078 | 0.00 |

What this shows, honestly:

- **Forgetting earns its place.** Removing it drops AUC and makes calibration more than twice as bad.
- **Prerequisite blame earns its place.** Without it, root-cause precision falls to zero.
- **Confidence does not help yet.** Removing it changes nothing measurable on this data.
- **Next-answer prediction is weak overall** (AUC 0.555, where 0.5 is chance), and the model is overconfident above 0.5.
- **Parameter recovery:** retention half-life is right on average (6.46 vs 6.42 days), but per-student correlation is low (0.05). Focus half-life is not recovered (fitted 7.3 vs true 23.4 minutes). The attention model needs more sessions per student, or a better estimator, before its numbers mean much.

## Known limitations

- A student can still insert attempt rows directly through the Supabase client (the `attempts` policy allows it), which would inflate their own mastery. It only affects that student's own numbers.
- Hidden test cases for coding problems are sent to the browser, because Python runs there (so it works offline). A determined student can read them.
- C++ and Java run on the public Piston judge (`emkc.org`). Its availability is not guaranteed; Python runs in the browser and always works.
- The AI tutor's limits (one explanation per wrong answer, 20 per student per hour) are kept in server memory, so they reset on restart and are per instance. Fine for a single-server demo; move them to a table before scaling out.
- The question bank is small (132 questions over 64 concepts).
