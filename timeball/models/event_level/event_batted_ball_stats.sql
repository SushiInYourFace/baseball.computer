{{
  config(
    materialized = 'table',
    )
}}
WITH final AS (
    SELECT
        event_key,
        1 AS balls_in_play,
        CASE WHEN contact = 'Fly' THEN 1 ELSE 0 END AS contact_type_fly_ball,
        CASE WHEN contact = 'GroundBall' THEN 1 ELSE 0 END AS contact_type_ground_ball,
        CASE WHEN contact = 'LineDrive' THEN 1 ELSE 0 END AS contact_type_line_drive,
        CASE WHEN contact = 'PopFly' THEN 1 ELSE 0 END AS contact_type_pop_fly,
        CASE
            WHEN COALESCE(contact, 'Unknown') = 'Unknown' THEN 1 ELSE 0
        END AS contact_type_unknown,
        CASE WHEN contact_broad_classification = 'AirBall' THEN 1 ELSE 0 END AS contact_broad_type_air_ball,
        CASE
            WHEN contact_broad_classification = 'GroundBall' THEN 1 ELSE 0
        END AS contact_broad_type_ground_ball,
        CASE
            WHEN COALESCE(contact_broad_classification, 'Unknown') = 'Unknown' THEN 1 ELSE 0
        END AS contact_broad_type_unknown,
        CASE WHEN is_bunt THEN 1 ELSE 0 END AS bunts,
        -- Distances,
        CASE WHEN location_depth = 'Battery' THEN 1 ELSE 0 END AS batted_distance_battery,
        CASE WHEN location_depth = 'Infield' THEN 1 ELSE 0 END AS batted_distance_infield,
        CASE WHEN location_depth = 'Outfield' THEN 1 ELSE 0 END AS batted_distance_outfield,
        CASE
            WHEN COALESCE(location_depth, 'Unknown') = 'Unknown' THEN 1 ELSE 0
        END AS batted_distance_unknown,
        CASE WHEN location_side = 'Left' THEN 1 ELSE 0 END AS batted_angle_left,
        CASE WHEN location_side = 'Right' THEN 1 ELSE 0 END AS batted_angle_right,
        CASE WHEN location_side = 'Middle' THEN 1 ELSE 0 END AS batted_angle_middle,
        CASE
            WHEN COALESCE(location_side, 'Unknown') IN ('All', 'Unknown') THEN 1 ELSE 0
        END AS batted_angle_unknown,
        -- All angle_* cols are mutually exclusive,
        -- but hits down foul line can be true at the same time as batted_angle_left/right
        CASE WHEN location_edge = 'Corner' THEN 1 ELSE 0 END AS batted_down_foul_line,
    FROM {{ ref('calc_batted_ball_type') }}
)

SELECT * FROM final
