-- TODO: Unclear whether this should exist as such.
-- Per-event-fielding stats for positions not involved in the play
-- are only there for innings/PA played, which can be tabulated
-- in more efficient ways.
{{
  config(
    materialized = 'table',
    )
}}
WITH fielding_plays_agg AS (
    SELECT
        event_key,
        fielding_position,
        COUNT(*) AS fielding_plays,
        COUNT(*) FILTER (WHERE fielding_play = 'Putout') AS putouts,
        COUNT(*) FILTER (WHERE fielding_play = 'Assist') AS assists,
        COUNT(*) FILTER (WHERE fielding_play = 'Error') AS errors,
        COUNT(*) FILTER (WHERE fielding_play = 'FieldersChoice') AS fielders_choices,
    FROM {{ ref('stg_event_fielding_plays') }}
    -- Exclude unknown attributions
    WHERE fielding_position != 0
    GROUP BY 1, 2
),

outs_agg AS (
    SELECT
        event_key,
        COUNT(*) AS outs_played
    FROM {{ ref('stg_event_outs') }}
    GROUP BY 1
),

passed_balls AS (
    SELECT DISTINCT event_key
    FROM {{ ref('stg_event_baserunning_plays') }}
    WHERE baserunning_play_type = 'PassedBall'
),

-- Join these together before the end to avoid an
-- unnecessary fanout
event_level_agg AS (
    SELECT
        event_key,
        events.event_id,
        events.batting_side,
        COALESCE(oa.outs_played, 0) AS outs_played,
        (pa.event_key IS NOT NULL)::INT AS plate_appearances_in_field,
        bbi.hit_to_fielder,
        dp.is_double_play,
        dp.is_triple_play,
        dp.is_ground_ball_double_play,
        CASE WHEN prt.is_in_play THEN 1 ELSE 0 END AS plate_appearances_in_field_with_ball_in_play
    FROM {{ ref('stg_events') }} AS events
    LEFT JOIN outs_agg AS oa USING (event_key)
    LEFT JOIN {{ ref('stg_event_plate_appearances') }} AS pa USING (event_key)
    LEFT JOIN {{ ref('seed_plate_appearance_result_types') }} AS prt USING (plate_appearance_result)
    LEFT JOIN {{ ref('event_double_plays') }} AS dp USING (event_key)
    LEFT JOIN {{ ref('stg_event_batted_ball_info') }} AS bbi USING (event_key)
),

positions AS (
    SELECT UNNEST(GENERATE_SERIES(1, 9))::TINYINT AS fielding_position
),

final AS (
    SELECT
        e.event_key,
        positions.fielding_position,
        e.outs_played,
        e.plate_appearances_in_field,
        e.plate_appearances_in_field_with_ball_in_play,
        CASE WHEN e.hit_to_fielder = positions.fielding_position THEN 1 ELSE 0 END AS balls_hit_to,
        COALESCE(fp.fielding_plays, 0) AS fielding_plays,
        COALESCE(fp.putouts, 0) AS putouts,
        COALESCE(fp.assists, 0) AS assists,
        COALESCE(fp.errors, 0) AS errors,
        COALESCE(fp.fielders_choices, 0) AS fielders_choices,
        (passed_balls.event_key IS NOT NULL AND positions.fielding_position = 2)::INT AS passed_balls,
        -- Only count double plays for the fielder who made a putout
        -- or assist on the play
        CASE WHEN e.is_double_play AND fp.putouts + fp.assists > 0
                THEN 1
            ELSE 0
        END AS double_plays,
        CASE WHEN e.is_triple_play AND fp.putouts + fp.assists > 0
                THEN 1
            ELSE 0
        END AS triple_plays,
        CASE WHEN e.is_ground_ball_double_play AND fp.putouts + fp.assists > 0
                THEN 1
            ELSE 0
        END AS ground_ball_double_plays
    FROM event_level_agg AS e
    CROSS JOIN positions
    LEFT JOIN fielding_plays_agg AS fp USING (event_key, fielding_position)
    LEFT JOIN passed_balls USING (event_key)
)

SELECT * FROM final