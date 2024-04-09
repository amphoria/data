WITH dim AS (
    SELECT
        generate_series(DATE_TRUNC('hour', MIN(t.ts)), DATE_TRUNC('hour', MAX(t.ts)), '1 hour' :: INTERVAL) AS ts,
        m.market_id
    FROM
        (
            SELECT
                ts
            FROM
                {{ ref('fct_core_market_updated') }}
        ) AS t
        CROSS JOIN (
            SELECT
                DISTINCT market_id
            FROM
                {{ ref('fct_core_market_updated') }}
        ) AS m
    GROUP BY
        m.market_id
),
rewards_distributed AS (
    SELECT
        ts,
        pool_id,
        collateral_type,
        market_id,
        distributor,
        market_symbol,
        amount,
        ts_start,
        "duration"
    FROM
        {{ ref('fct_pool_rewards') }}
),
hourly_rewards AS (
    SELECT
        dim.ts,
        dim.market_id,
        r.pool_id,
        r.collateral_type,
        r.ts_start,
        dim.ts + '1 hour' :: INTERVAL AS ts_end,
        r.distributor,
        r.market_symbol,
        p.price,
        -- get the hourly amount distributed
        r.amount / (
            r."duration" / 3600
        ) AS hourly_amount,
        -- get the amount of time distributed this hour
        -- use the smaller of those two intervals
        -- convert the interval to a number of hours
        -- multiply the result by the hourly amount to get the amount distributed this hour
        (
            EXTRACT(
                epoch
                FROM
                    LEAST(
                        "duration" / 3600 * '1 hour' :: INTERVAL,
                        dim.ts + '1 hour' :: INTERVAL - GREATEST(
                            dim.ts,
                            r.ts_start
                        )
                    )
            ) / 3600
        ) * r.amount / (
            r."duration" / 3600
        ) AS amount_distributed
    FROM
        dim
        LEFT JOIN rewards_distributed r
        ON dim.market_id = r.market_id
        AND dim.ts + '1 hour' :: INTERVAL >= r.ts_start
        AND dim.ts < r.ts_start + r."duration" * '1 second' :: INTERVAL
        LEFT JOIN {{ ref('fct_prices_hourly') }}
        p
        ON dim.ts = p.ts
        AND r.market_symbol = p.market_symbol
)
SELECT
    *,
    amount_distributed * price AS rewards_usd
FROM
    hourly_rewards
WHERE
    amount_distributed IS NOT NULL