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
        oa.outs_played,
        (pa.event_key IS NOT NULL)::INT AS plate_appearances_in_field,
        bbi.hit_to_fielder,
        dp.is_double_play,
        dp.is_triple_play,
        dp.is_ground_ball_double_play,
        CASE WHEN prt.is_in_play THEN 1 ELSE 0 END AS plate_appearances_in_field_with_ball_in_play
    FROM outs_agg AS oa
    FULL OUTER JOIN {{ ref('stg_event_plate_appearances') }} AS pa USING (event_key)
    LEFT JOIN {{ ref('seed_plate_appearance_result_types') }} AS prt USING (plate_appearance_result)
    LEFT JOIN {{ ref('event_double_plays') }} AS dp USING (event_key)
    LEFT JOIN {{ ref('stg_event_batted_ball_info') }} AS bbi USING (event_key)
),

final AS (
    SELECT
        event_key,
        s.player_id AS fielder_id,
        s.team_id AS fielding_team_id,
        fp.fielding_position,
        e.outs_played,
        e.plate_appearances_in_field,
        e.plate_appearances_in_field_with_ball_in_play,
        CASE WHEN e.hit_to_fielder = fp.fielding_position THEN 1 ELSE 0 END AS balls_hit_to,
        COALESCE(fp.fielding_plays, 0) AS fielding_plays,
        COALESCE(fp.putouts, 0) AS putouts,
        COALESCE(fp.assists, 0) AS assists,
        COALESCE(fp.errors, 0) AS errors,
        COALESCE(fp.fielders_choices, 0) AS fielders_choices,
        (passed_balls.event_key IS NOT NULL AND fp.fielding_position = 2) AS passed_balls,
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
    FROM {{ ref('event_fielding_states') }} AS s
    LEFT JOIN event_level_agg AS e USING (event_key)
    LEFT JOIN fielding_plays_agg AS fp USING (event_key, fielding_position)
    LEFT JOIN passed_balls USING (event_key)
)

SELECT * FROM final
