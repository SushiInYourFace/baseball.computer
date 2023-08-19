WITH source AS (
    SELECT * FROM {{ source('baseballdatabank', 'fielding') }}
),

renamed AS (
    SELECT
        playerid AS databank_player_id,
        yearid AS season,
        stint,
        teamid AS team_id,
        lgid AS league_id,
        g AS games,
        gs AS games_started,
        innouts AS outs_played,
        po AS putouts,
        a AS assists,
        e AS errors,
        dp AS double_plays,
        pb AS passed_balls,
        wp AS wild_pitches,
        sb AS stolen_bases,
        cs AS caught_stealing,
        CASE pos
            WHEN 'P' THEN 1
            WHEN 'C' THEN 2
            WHEN '1B' THEN 3
            WHEN '2B' THEN 4
            WHEN '3B' THEN 5
            WHEN 'SS' THEN 6
        END AS fielding_position,
        CASE
            WHEN pos IN ('P', 'C', 'OF') THEN pos
            WHEN pos IN ('1B', '2B', '3B', 'SS') THEN 'IF'
        END AS fielding_position_category
    FROM source
)

SELECT * FROM renamed
