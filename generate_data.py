"""
Generate the synthetic OTT viewing dataset.

Titles are given one of three underlying retention shapes so the diagnostic has
real structure to find:

  cold_open   viewers bail in the first 20% - the hook fails
  mid_sag     viewers stay through the setup then leave around 60-70% - pacing fails
  sticky      viewers largely finish

Run:  python scripts/generate_data.py
Out:  data/retention.db
"""
import os
import random
import sqlite3
from datetime import date, timedelta

RANDOM_SEED = 11
DB_PATH = os.path.join("data", "retention.db")
START_DATE = date(2025, 6, 1)
WINDOW_DAYS = 180

GENRES = ["Drama", "Thriller", "Comedy", "Documentary", "Reality", "Sci-Fi"]
DEVICES = ["Smart TV", "Mobile", "Web", "Tablet"]
DEVICE_WEIGHTS = [0.45, 0.30, 0.15, 0.10]

# retention shape -> weights over dropoff deciles 1..10
SHAPES = {
    "cold_open": [0.26, 0.20, 0.13, 0.08, 0.06, 0.05, 0.04, 0.04, 0.04, 0.10],
    "mid_sag":   [0.07, 0.06, 0.06, 0.07, 0.10, 0.14, 0.13, 0.08, 0.05, 0.24],
    "sticky":    [0.04, 0.03, 0.03, 0.03, 0.04, 0.05, 0.05, 0.06, 0.07, 0.60],
}

# 40 titles: 12 cold_open, 13 mid_sag, 15 sticky
SHAPE_MIX = ["cold_open"] * 12 + ["mid_sag"] * 13 + ["sticky"] * 15


def build():
    rng = random.Random(RANDOM_SEED)
    os.makedirs("data", exist_ok=True)
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    conn = sqlite3.connect(DB_PATH)
    with open(os.path.join("sql", "01_schema.sql")) as fh:
        conn.executescript(fh.read())

    shapes = SHAPE_MIX[:]
    rng.shuffle(shapes)

    titles, sessions = [], []
    session_id = 0

    for title_id, shape in enumerate(shapes, start=1):
        fmt = rng.choices(["Series", "Film"], weights=[0.6, 0.4])[0]
        runtime = rng.randint(35, 58) if fmt == "Series" else rng.randint(88, 142)
        release = START_DATE + timedelta(days=rng.randint(0, 60))
        titles.append((
            title_id,
            f"Title {title_id:02d}",
            rng.choice(GENRES),
            fmt,
            runtime,
            release.isoformat(),
            round(rng.uniform(0.4, 9.5) * 1_000_000, 0),
        ))

        weights = SHAPES[shape]
        for _ in range(rng.randint(150, 320)):
            session_id += 1
            decile = rng.choices(range(1, 11), weights=weights)[0]
            # within-decile position, so pct_completed isn't artificially blocky
            pct = 1.0 if decile == 10 and rng.random() < 0.75 else round(
                min(1.0, (decile - 1) / 10 + rng.uniform(0.005, 0.099)), 3)
            watch = release + timedelta(days=rng.randint(0, WINDOW_DAYS))
            sessions.append((
                session_id, title_id, rng.randint(1, 9000), watch.isoformat(),
                pct, decile, rng.choices(DEVICES, weights=DEVICE_WEIGHTS)[0],
                1 if pct >= 0.90 else 0,
            ))

    conn.executemany("INSERT INTO titles VALUES (?,?,?,?,?,?,?)", titles)
    conn.executemany("INSERT INTO viewing_sessions VALUES (?,?,?,?,?,?,?,?)", sessions)
    conn.commit()
    conn.close()
    print(f"Wrote {len(titles)} titles and {len(sessions):,} viewing sessions -> {DB_PATH}")


if __name__ == "__main__":
    build()
