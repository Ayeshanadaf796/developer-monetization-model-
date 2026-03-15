-- 1. : Revenue, install volume, and monetization mix by category
WITH cleaned AS (
  SELECT
    Category,
    Type,


    SAFE_CAST(REGEXP_REPLACE(CAST(Revenue AS STRING), r'[^0-9.\-]', '') AS FLOAT64) AS revenue_num,

    
    SAFE_CAST(REGEXP_REPLACE(CAST(Installs AS STRING), r'[^0-9]', '') AS INT64) AS installs_num,

    SAFE_CAST(Rating AS FLOAT64) AS rating_num
  FROM `playstore-487709.google.monetization`
),

agg AS (
  SELECT
    Category,
    COUNT(*) AS total_apps,
    ROUND(SUM(revenue_num), 2) AS total_revenue,
    ROUND(AVG(revenue_num), 2) AS avg_revenue_per_app,
    SUM(installs_num) AS total_installs,
    SUM(IF(Type = 'Free', 1, 0)) AS free_apps,
    SUM(IF(Type = 'Paid', 1, 0)) AS paid_apps,
    ROUND(AVG(rating_num), 2) AS avg_rating
  FROM cleaned
  GROUP BY Category
)

SELECT
  *,
  ROUND(total_revenue * 100.0 / SUM(total_revenue) OVER (), 2) AS revenue_share_pct
FROM agg
ORDER BY total_revenue DESC
LIMIT 10;


-- 2.Revenue by monetization model and developer type (2x2 matrix)
WITH cleaned AS (
  SELECT
    Type AS monetization_model,
    developer_type,

    SAFE_CAST(REGEXP_REPLACE(CAST(Revenue AS STRING), r'[^0-9.\-]', '') AS FLOAT64) AS revenue_num,
    SAFE_CAST(CAST(Rating AS STRING) AS FLOAT64) AS rating_num,
    SAFE_CAST(REGEXP_REPLACE(CAST(Installs AS STRING), r'[^0-9]', '') AS INT64) AS installs_num
  FROM `playstore-487709.google.monetization`
),

agg AS (
  SELECT
    monetization_model,
    developer_type,
    COUNT(*) AS app_count,
    ROUND(SUM(revenue_num), 2) AS total_revenue,
    ROUND(AVG(revenue_num), 2) AS avg_revenue,

  
    ROUND(APPROX_QUANTILES(revenue_num, 2)[OFFSET(1)], 2) AS median_revenue,

    ROUND(AVG(rating_num), 2) AS avg_rating,
    SUM(installs_num) AS total_installs
  FROM cleaned
  GROUP BY monetization_model, developer_type
)

SELECT *
FROM agg
ORDER BY avg_revenue DESC;


-- 3.Revenue per install efficiency (monetization conversion rate)
WITH cleaned AS (
  SELECT
    Category,
    SAFE_CAST(REGEXP_REPLACE(CAST(Revenue AS STRING), r'[^0-9.\-]', '') AS FLOAT64) AS revenue_num,
    SAFE_CAST(REGEXP_REPLACE(CAST(Installs AS STRING), r'[^0-9]', '') AS INT64) AS installs_num
  FROM `playstore-487709.google.monetization`
),
agg AS (
  SELECT
    Category,
    SUM(revenue_num) AS total_revenue,
    SUM(installs_num) AS total_installs
  FROM cleaned
  WHERE installs_num IS NOT NULL AND installs_num > 0
  GROUP BY Category
)
SELECT
  Category,
  ROUND(total_revenue, 2) AS total_revenue,
  total_installs,
  ROUND(total_revenue / NULLIF(total_installs, 0), 4) AS revenue_per_install,
  RANK() OVER (ORDER BY total_revenue / NULLIF(total_installs, 0) DESC) AS efficiency_rank
FROM agg
ORDER BY revenue_per_install DESC;


--4.Category-level Indie vs Enterprise performance comparison
SELECT
  Category,
  ROUND(AVG(CASE WHEN developer_type='Indie' THEN Revenue END), 2) AS indie_avg_rev,
  ROUND(AVG(CASE WHEN developer_type='Enterprise' THEN Revenue END), 2) AS ent_avg_rev,
  ROUND(AVG(CASE WHEN developer_type='Indie' THEN Rating END), 2) AS indie_avg_rating,
  ROUND(AVG(CASE WHEN developer_type='Enterprise' THEN Rating END), 2) AS ent_avg_rating,
  COUNT(CASE WHEN developer_type='Indie' THEN 1 END) AS indie_count,
  COUNT(CASE WHEN developer_type='Enterprise' THEN 1 END) AS ent_count,
  ROUND(
    AVG(CASE WHEN developer_type='Indie' THEN Revenue END) /
    NULLIF(AVG(CASE WHEN developer_type='Enterprise' THEN Revenue END), 0),
    3) AS indie_to_ent_rev_ratio
FROM `playstore-487709.google.monetization`
GROUP BY Category
HAVING COUNT(CASE WHEN developer_type='Indie' THEN 1 END) > 10
   AND COUNT(CASE WHEN developer_type='Enterprise' THEN 1 END) > 5
ORDER BY indie_to_ent_rev_ratio DESC;


-- 5.Revenue and reach by content rating tier
WITH cleaned AS (
  SELECT
    `Content Rating` AS content_rating,

    SAFE_CAST(REGEXP_REPLACE(CAST(Revenue AS STRING), r'[^0-9.\-]', '') AS FLOAT64) AS revenue_num,
    SAFE_CAST(REGEXP_REPLACE(CAST(Installs AS STRING), r'[^0-9]', '') AS INT64) AS installs_num,
    SAFE_CAST(CAST(Rating AS STRING) AS FLOAT64) AS rating_num
  FROM `playstore-487709.google.monetization`
),

agg AS (
  SELECT
    content_rating,
    COUNT(*) AS app_count,
    SUM(revenue_num) AS total_revenue,
    AVG(revenue_num) AS avg_revenue,
    SUM(installs_num) AS total_installs,
    AVG(rating_num) AS avg_rating
  FROM cleaned
  GROUP BY content_rating
)

SELECT
  content_rating AS `Content Rating`,
  app_count,
  ROUND(total_revenue, 2) AS total_revenue,
  ROUND(avg_revenue, 2) AS avg_revenue,
  total_installs,
  ROUND(total_revenue * 100.0 / NULLIF(SUM(total_revenue) OVER (), 0), 2) AS revenue_share_pct,
  ROUND(avg_rating, 2) AS avg_rating
FROM agg
ORDER BY total_revenue DESC;


--6.Top 20 revenue-generating apps with full context
SELECT
  App,
  Category,
  Type,
  developer_type,
  Price,
  Revenue,
  Rating,
  Installs,
  `Content Rating`,
  RANK() OVER (ORDER BY Revenue DESC) AS revenue_rank,
  RANK() OVER (PARTITION BY Category ORDER BY Revenue DESC) AS category_rank
FROM `playstore-487709.google.monetization`
ORDER BY Revenue DESC
LIMIT 20;


--7.App quality tiers and their revenue impact
WITH cleaned AS (
  SELECT
    SAFE_CAST(CAST(Rating AS STRING) AS FLOAT64) AS rating_num,

    SAFE_CAST(REGEXP_REPLACE(CAST(Revenue AS STRING), r'[^0-9.\-]', '') AS FLOAT64) AS revenue_num,

    SAFE_CAST(REGEXP_REPLACE(CAST(Installs AS STRING), r'[^0-9]', '') AS INT64) AS installs_num,

    SAFE_CAST(REGEXP_REPLACE(CAST(Reviews AS STRING), r'[^0-9]', '') AS INT64) AS reviews_num
  FROM `playstore-487709.google.monetization`
),
tiered AS (
  SELECT
    CASE
      WHEN rating_num >= 4.5 THEN 'Premium (4.5+)'
      WHEN rating_num >= 4.0 THEN 'High (4.0-4.49)'
      WHEN rating_num >= 3.5 THEN 'Mid (3.5-3.99)'
      WHEN rating_num >= 3.0 THEN 'Low (3.0-3.49)'
      ELSE 'Poor (<3.0)'
    END AS quality_tier,
    revenue_num,
    installs_num,
    reviews_num
  FROM cleaned
  WHERE rating_num IS NOT NULL AND rating_num > 0
)

SELECT
  quality_tier,
  COUNT(*) AS app_count,
  ROUND(AVG(revenue_num), 2) AS avg_revenue,
  ROUND(SUM(revenue_num), 2) AS total_revenue,
  SUM(installs_num) AS total_installs,
  ROUND(AVG(CAST(reviews_num AS FLOAT64)), 0) AS avg_reviews
FROM tiered
GROUP BY quality_tier
ORDER BY avg_revenue DESC;


--8.Percentile rank of apps within their category (advanced analytics)
WITH cleaned AS (
  SELECT
    App,
    Category,
    Revenue,
    developer_type,
    Type,
    SAFE_CAST(REGEXP_REPLACE(CAST(Revenue AS STRING), r'[^0-9.\-]', '') AS FLOAT64) AS revenue_num
  FROM `playstore-487709.google.monetization`
)
SELECT
  App,
  Category,
  Revenue,
  developer_type,
  Type,

  PERCENT_RANK() OVER (PARTITION BY Category ORDER BY revenue_num) AS revenue_percentile,
  NTILE(4) OVER (PARTITION BY Category ORDER BY revenue_num) AS revenue_quartile,
  AVG(revenue_num) OVER (PARTITION BY Category) AS category_avg_revenue,
  revenue_num - AVG(revenue_num) OVER (PARTITION BY Category) AS vs_category_avg
FROM cleaned
WHERE revenue_num IS NOT NULL
ORDER BY Category, revenue_percentile DESC;


--9.: Opportunity matrix — high revenue potential, low app density
WITH cleaned AS (
  SELECT
    Category,
    developer_type,
    SAFE_CAST(REGEXP_REPLACE(CAST(Revenue AS STRING), r'[^0-9.\-]', '') AS FLOAT64) AS revenue_num,
    SAFE_CAST(CAST(Rating AS STRING) AS FLOAT64) AS rating_num,
    SAFE_CAST(REGEXP_REPLACE(CAST(Installs AS STRING), r'[^0-9]', '') AS INT64) AS installs_num
  FROM `playstore-487709.google.monetization`
),

cat_metrics AS (
  SELECT
    Category,
    developer_type,
    COUNT(*) AS app_count,
    ROUND(AVG(revenue_num), 2) AS avg_revenue,
    ROUND(AVG(rating_num), 2) AS avg_rating,
    SUM(installs_num) AS total_installs
  FROM cleaned
  GROUP BY Category, developer_type
),

ranked AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY avg_revenue DESC) AS rev_tier,
    NTILE(3) OVER (ORDER BY app_count ASC) AS scarcity_tier
  FROM cat_metrics
)

SELECT
  *,
  CASE
    WHEN rev_tier = 1 AND scarcity_tier = 1 THEN 'HIGH OPPORTUNITY'
    WHEN rev_tier = 1 AND scarcity_tier = 2 THEN 'MODERATE OPPORTUNITY'
    ELSE 'COMPETITIVE / SATURATED'
  END AS market_opportunity
FROM ranked
WHERE rev_tier = 1
ORDER BY avg_revenue DESC;






















