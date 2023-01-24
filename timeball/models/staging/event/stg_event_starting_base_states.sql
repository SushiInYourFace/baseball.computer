WITH source AS (
    SELECT * FROM {{ source('event', 'event_starting_base_state') }}
),

renamed AS (
    SELECT
        game_id,
        event_id,
        baserunner,
        runner_lineup_position,
        charged_to_pitcher_id,
        event_key,
        event_key || '-' || baserunner AS baserunner_key

    FROM source
)

SELECT * FROM renamed