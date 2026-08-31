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