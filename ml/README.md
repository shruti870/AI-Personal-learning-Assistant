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