"""
Render the survival-curve chart used in the README.

Run:  python scripts/make_charts.py
Out:  results/survival_curves.png, results/tier_summary.png
"""
import os
import sqlite3

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

DB_PATH = os.path.join("data", "retention.db")
COLOURS = {"Tier 1 - Healthy": "#2f6f4e",
           "Tier 2 - Watchlist": "#c98a1b",
           "Tier 3 - At risk": "#b03a2e"}

SURVIVAL_SQL = """
WITH title_metrics AS (
    SELECT title_id, AVG(is_completed) AS completion_rate
    FROM viewing_sessions GROUP BY title_id
),
tiered AS (
    SELECT title_id,
           CASE NTILE(3) OVER (ORDER BY completion_rate DESC)
                WHEN 1 THEN 'Tier 1 - Healthy'
                WHEN 2 THEN 'Tier 2 - Watchlist'
                ELSE 'Tier 3 - At risk' END AS risk_tier
    FROM title_metrics
),
decile_counts AS (
    SELECT tr.risk_tier, s.dropoff_decile, COUNT(*) AS n
    FROM viewing_sessions s JOIN tiered tr ON tr.title_id = s.title_id
    GROUP BY tr.risk_tier, s.dropoff_decile
)
SELECT risk_tier, dropoff_decile,
       100.0 * SUM(n) OVER (PARTITION BY risk_tier ORDER BY dropoff_decile
                            ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)
             / SUM(n) OVER (PARTITION BY risk_tier) AS pct_still_watching
FROM decile_counts ORDER BY risk_tier, dropoff_decile;
"""


def main():
    os.makedirs("results", exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    df = pd.read_sql_query(SURVIVAL_SQL, conn)
    conn.close()

    fig, ax = plt.subplots(figsize=(8.5, 5.2), dpi=160)
    for tier, group in df.groupby("risk_tier"):
        ax.plot(group["dropoff_decile"] * 10, group["pct_still_watching"],
                marker="o", markersize=4.5, linewidth=2,
                color=COLOURS.get(tier, "#7b8794"), label=tier)

    ax.set_xlabel("% of runtime elapsed", fontsize=9)
    ax.set_ylabel("% of viewers still watching", fontsize=9)
    ax.set_title("Two different failure modes, not one\n"
                 "At-risk titles lose the audience immediately;\n"
                 "watchlist titles hold, then sag past the midpoint",
                 fontsize=11, loc="left", pad=10)
    ax.set_ylim(0, 105)
    ax.set_xticks(range(10, 101, 10))
    ax.grid(axis="y", color="#e4e7eb", linewidth=0.8)
    ax.set_axisbelow(True)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    ax.legend(frameon=False, fontsize=9)
    fig.tight_layout()
    fig.savefig(os.path.join("results", "survival_curves.png"))
    plt.close(fig)
    print("Wrote results/survival_curves.png")


if __name__ == "__main__":
    main()
