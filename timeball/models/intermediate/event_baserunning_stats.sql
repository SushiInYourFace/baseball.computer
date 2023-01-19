WITH event_info AS (
    SELECT *
    FROM {{ ref('events') }}
),

states AS (
    SELECT *
    FROM {{ ref('event_starting_base_states') }}
),

baserunning_plays AS (
    SELECT *
    FROM {{ ref('event_baserunning_plays') }}
),

advances AS (
    SELECT *
    FROM {{ ref('event_baserunning_advance_attempts') }}
),

plate_appearances AS (
    SELECT *
    FROM {{ ref('event_plate_appearances') }}
),

baserunner_meta AS (
    SELECT *
    FROM {{ ref('baserunner_info') }}
),

bases_meta AS (
    SELECT *
    FROM {{ ref('bases_info') }}
),

plate_appearance_meta AS (
    SELECT *
    FROM {{ ref('plate_appearance_result_types') }}
),

states_full AS (
    SELECT
        baserunner_key,
        runner_lineup_position
    FROM states
    UNION ALL
    SELECT
        event_key || '-' || 'Batter' AS baserunner_key,
        at_bat AS runner_lineup_position
    FROM event_info
),

joined AS (
    SELECT
        a.game_id,
        a.event_id,
        a.event_key,
        a.baserunner_key,
        a.baserunner,
        sf.runner_lineup_position,
        a.is_successful,
        a.advanced_on_error_flag,
        a.explicit_out_flag,
        baserunner_meta.numeric_value AS number_base_from,
        bases_meta.numeric_value AS number_base_to,
        pa.plate_appearance_result,
        pam.is_in_play,
        COALESCE(bp.baserunning_play_type, 'None') AS baserunning_play_type,
        COALESCE(pam.total_bases, 0) AS batter_total_bases
    FROM advances AS a
    INNER JOIN states_full AS sf USING (baserunner_key)
    LEFT JOIN plate_appearances AS pa USING (event_key)
    LEFT JOIN baserunner_meta ON a.baserunner = baserunner_meta.baserunner
    LEFT JOIN bases_meta ON a.attempted_advance_to = bases_meta.base
    LEFT JOIN plate_appearance_meta AS pam ON pa.plate_appearance_result = pam.name
    LEFT JOIN baserunning_plays AS bp
        ON a.event_key = bp.event_key
    -- This can't be part of the above join because it will cause a nested loop,
    -- but it should be. We need to make sure that the baserunner is the
    -- same as the one in the baserunning play, or that no baserunner
    -- was specified (meaning that the play applies to all baserunners).
    WHERE a.baserunner = bp.baserunner OR bp.baserunning_play_type IS NULL
),

final AS (
    SELECT
        game_id,
        event_id,
        event_key,
        baserunner_key,
        baserunner,
        runner_lineup_position,
        (is_successful AND number_base_to = 4)::INT AS runs_scored,
        (baserunning_play_type = 'StolenBase')::INT AS stolen_bases,
        (baserunning_play_type LIKE '%CaughtStealing')::INT AS caught_stealing,
        (baserunning_play_type LIKE 'PickedOff%')::INT AS pickoffs,
        explicit_out_flag::INT AS caught_on_basepaths,

        (baserunning_play_type = 'WildPitch')::INT AS advances_on_wild_pitches,
        (baserunning_play_type = 'PassedBall')::INT AS advances_on_passed_balls,
        (baserunning_play_type = 'Balk')::INT AS advances_on_balks,
        (baserunning_play_type = 'OtherAdvance')::INT AS advances_on_unspecified_plays,
        (baserunning_play_type = 'DefensiveIndifference')::INT AS advances_on_defensive_indifference,
        (baserunning_play_type = 'AdvancedOnError' OR advanced_on_error_flag)::INT AS advances_on_errors,

        is_in_play::INT AS balls_in_play_while_running,

        CASE WHEN is_successful
            THEN number_base_to - number_base_from
            ELSE 0
        END AS bases_advanced,
        CASE WHEN is_successful AND is_in_play AND NOT advanced_on_error_flag
            THEN number_base_to - number_base_from
            ELSE 0
        END AS bases_advanced_on_balls_in_play,
        CASE WHEN is_successful AND NOT advanced_on_error_flag
            THEN number_base_to - number_base_from - LEAST(4 - number_base_from, batter_total_bases)
            ELSE 0
        END AS extra_bases_advanced_on_balls_in_play
    FROM joined
)

SELECT COUNT(*) FROM final
WHERE caught_stealing > 0