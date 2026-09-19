-- =====================================================================
-- Viewer Retention Diagnostic - OTT Platform
-- Analysis queries (SQLite 3.25+)
-- Hypothesis: low completion is not one problem. Some titles lose viewers
-- in the opening minutes (a hook problem); others hold viewers through the
-- setup and lose them in the back half (a pacing problem). Those need
-- different fixes, so the diagnostic must separate them.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Q1. Title scorecard with risk tiering
-- Completion rate, early-abandon rate, and an NTILE-based risk tier so the
-- catalogue splits into three actionable groups rather than a long list.
-- ---------------------------------------------------------------------
WITH title_metrics AS (
    SELECT
        t.title_id,
        t.title_name,
        t.genre,
        t.format,
        t.licence_cost_usd,
        COUNT(*)                                                     AS sessions,
        ROUND(AVG(s.is_completed), 3)                                AS completion_rate,
        ROUND(AVG(CASE WHEN s.dropoff_decile <= 2 THEN 1.0 ELSE 0 END), 3)
                                                                     AS early_abandon_rate,
        ROUND(AVG(CASE WHEN s.dropoff_decile BETWEEN 5 AND 8 THEN 1.0 ELSE 0 END), 3)
                                                                     AS mid_abandon_rate,
        ROUND(AVG(s.pct_completed), 3)                               AS avg_pct_watched
    FROM titles t
    JOIN viewing_sessions s ON s.title_id = t.title_id
    GROUP BY t.title_id
),
tiered AS (
    SELECT
        *,
        NTILE(3) OVER (ORDER BY completion_rate DESC) AS tier_rank,
        RANK()   OVER (ORDER BY completion_rate DESC) AS completion_rank,
        ROUND(completion_rate
              - AVG(completion_rate) OVER (), 3)      AS vs_catalogue_avg
    FROM title_metrics
)
SELECT
    title_name,
    genre,
    format,
    sessions,
    completion_rate,
    early_abandon_rate,
    mid_abandon_rate,
    vs_catalogue_avg,
    CASE tier_rank WHEN 1 THEN 'Tier 1 - Healthy'
                   WHEN 2 THEN 'Tier 2 - Watchlist'
                   ELSE 'Tier 3 - At risk' END        AS risk_tier,
    -- diagnosis: where the title actually loses people
    CASE
        WHEN early_abandon_rate >= 0.30 THEN 'Hook failure (lost in first 20%)'
        WHEN mid_abandon_rate  >= 0.35 THEN 'Pacing sag (lost in middle)'
        ELSE 'No single dominant leak'
    END                                               AS failure_mode,
    ROUND(licence_cost_usd / 1000000.0, 2)            AS licence_cost_musd
FROM tiered
ORDER BY completion_rate DESC;


-- ---------------------------------------------------------------------
-- Q2. Survival curve by risk tier
-- What share of viewers are still watching at the end of each decile.
-- SUM() OVER with a reverse frame turns a histogram into a survival curve.
-- ---------------------------------------------------------------------
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
    SELECT tr.risk_tier, s.dropoff_decile, COUNT(*) AS sessions_ending_here
    FROM viewing_sessions s
    JOIN tiered tr ON tr.title_id = s.title_id
    GROUP BY tr.risk_tier, s.dropoff_decile
)
SELECT
    risk_tier,
    dropoff_decile,
    sessions_ending_here,
    ROUND(100.0 * SUM(sessions_ending_here) OVER (
              PARTITION BY risk_tier
              ORDER BY dropoff_decile
              ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)
          / SUM(sessions_ending_here) OVER (PARTITION BY risk_tier), 1)
        AS pct_still_watching
FROM decile_counts
ORDER BY risk_tier, dropoff_decile;


-- ---------------------------------------------------------------------
-- Q3. Does runtime explain drop-off? (pacing hypothesis test)
-- Buckets titles by runtime and compares completion within format, so the
-- "our episodes are too long" claim can be checked rather than assumed.
-- ---------------------------------------------------------------------
WITH per_title AS (
    SELECT t.title_id, t.format, t.runtime_minutes,
           AVG(s.is_completed) AS completion_rate
    FROM titles t JOIN viewing_sessions s ON s.title_id = t.title_id
    GROUP BY t.title_id
)
SELECT
    format,
    CASE
        WHEN format = 'Series' AND runtime_minutes < 45 THEN 'Short episode (<45m)'
        WHEN format = 'Series'                          THEN 'Long episode (45m+)'
        WHEN runtime_minutes < 110                      THEN 'Short film (<110m)'
        ELSE 'Long film (110m+)'
    END                                    AS runtime_bucket,
    COUNT(*)                               AS titles,
    ROUND(AVG(completion_rate), 3)         AS avg_completion_rate
FROM per_title
GROUP BY format, runtime_bucket
ORDER BY format, avg_completion_rate DESC;


-- ---------------------------------------------------------------------
-- Q4. Genre view - is the problem concentrated in one type of content?
-- ---------------------------------------------------------------------
WITH per_title AS (
    SELECT t.genre, t.title_id, t.licence_cost_usd,
           AVG(s.is_completed) AS completion_rate,
           COUNT(*)            AS sessions
    FROM titles t JOIN viewing_sessions s ON s.title_id = t.title_id
    GROUP BY t.title_id
)
SELECT
    genre,
    COUNT(*)                                         AS titles,
    SUM(sessions)                                    AS sessions,
    ROUND(AVG(completion_rate), 3)                   AS avg_completion_rate,
    ROUND(SUM(licence_cost_usd) / 1000000.0, 1)      AS licence_spend_musd,
    RANK() OVER (ORDER BY AVG(completion_rate) DESC) AS genre_rank
FROM per_title
GROUP BY genre
ORDER BY avg_completion_rate DESC;


-- ---------------------------------------------------------------------
-- Q5. Device split - is weak completion a content problem or a UX problem?
-- If completion collapses on one device, the fix is product, not content.
-- ---------------------------------------------------------------------
SELECT
    device,
    COUNT(*)                                AS sessions,
    ROUND(AVG(is_completed), 3)             AS completion_rate,
    ROUND(AVG(pct_completed), 3)            AS avg_pct_watched,
    ROUND(AVG(CASE WHEN dropoff_decile <= 2 THEN 1.0 ELSE 0 END), 3) AS early_abandon_rate
FROM viewing_sessions
GROUP BY device
ORDER BY completion_rate DESC;
