-- =====================================================================
-- Viewer Retention Diagnostic - OTT Platform
-- Schema definition (SQLite)
-- =====================================================================

DROP TABLE IF EXISTS viewing_sessions;
DROP TABLE IF EXISTS titles;

CREATE TABLE titles (
    title_id        INTEGER PRIMARY KEY,
    title_name      TEXT    NOT NULL,
    genre           TEXT    NOT NULL,
    format          TEXT    NOT NULL,  -- Series / Film
    runtime_minutes INTEGER NOT NULL,
    release_date    TEXT    NOT NULL,
    licence_cost_usd REAL   NOT NULL   -- what the platform paid for it
);

-- One row per viewing session. `dropoff_decile` records which tenth of the
-- runtime the viewer was in when they stopped (10 = finished).
CREATE TABLE viewing_sessions (
    session_id     INTEGER PRIMARY KEY,
    title_id       INTEGER NOT NULL REFERENCES titles(title_id),
    user_id        INTEGER NOT NULL,
    watch_date     TEXT    NOT NULL,
    pct_completed  REAL    NOT NULL,   -- 0.0 - 1.0
    dropoff_decile INTEGER NOT NULL,   -- 1..10
    device         TEXT    NOT NULL,
    is_completed   INTEGER NOT NULL    -- 1 if pct_completed >= 0.90
);

CREATE INDEX idx_sessions_title ON viewing_sessions(title_id);
CREATE INDEX idx_sessions_date  ON viewing_sessions(watch_date);
