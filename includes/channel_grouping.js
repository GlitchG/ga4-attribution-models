const { BRAND_TERMS_REGEX } = require('./constants');

function channelGrouping(mediumExpr, sourceExpr, campaignExpr) {
  return `CASE
    -- 1. Cross-network (Performance Max, Demand Gen)
    WHEN LOWER(${campaignExpr}) LIKE '%pmax%' OR LOWER(${campaignExpr}) LIKE '%performance_max%'
      OR LOWER(${campaignExpr}) LIKE '%demand_gen%' OR LOWER(${campaignExpr}) LIKE '%demand-gen%'
      THEN 'Cross-network'

    -- 2. Paid Shopping (incl. free listings via srsltid)
    WHEN COALESCE(${mediumExpr}, '') IN ('cpc','ppc','paidsearch')
      AND (LOWER(${sourceExpr}) LIKE '%shopping%' OR LOWER(${campaignExpr}) LIKE '%shopping%')
      THEN 'Paid Shopping'

    -- 3. Paid Search Brand vs Non-Brand
    WHEN COALESCE(${mediumExpr}, '') IN ('cpc','ppc','paidsearch')
      AND REGEXP_CONTAINS(LOWER(COALESCE(${campaignExpr}, '')), r'${BRAND_TERMS_REGEX}')
      THEN 'Paid Search Brand'
    WHEN COALESCE(${mediumExpr}, '') IN ('cpc','ppc','paidsearch')
      THEN 'Paid Search Non-Brand'

    -- 4. Paid Video (YouTube ads etc.)
    WHEN LOWER(${sourceExpr}) IN ('youtube','vimeo')
      AND COALESCE(${mediumExpr}, '') IN ('cpc','ppc','cpv','cpm','paid')
      THEN 'Paid Video'

    -- 5. Paid Social
    WHEN LOWER(${sourceExpr}) IN ('facebook','instagram','tiktok','pinterest','linkedin','x','twitter','snapchat','reddit')
      AND COALESCE(${mediumExpr}, '') IN ('cpc','ppc','paid','paidsocial')
      THEN 'Paid Social'

    -- 6. Display
    WHEN COALESCE(${mediumExpr}, '') IN ('display','banner','cpm','expandable','interstitial')
      THEN 'Display'

    -- 7. Organic Shopping (free listings without paid)
    WHEN LOWER(${sourceExpr}) LIKE '%shopping%' THEN 'Organic Shopping'

    -- 8. Organic Video
    WHEN LOWER(${sourceExpr}) IN ('youtube','vimeo','dailymotion') THEN 'Organic Video'

    -- 9. Organic Social
    WHEN LOWER(${sourceExpr}) IN ('facebook','instagram','tiktok','pinterest','linkedin','x','twitter','snapchat','reddit')
      OR LOWER(COALESCE(${mediumExpr}, '')) LIKE '%social%'
      THEN 'Organic Social'

    -- 10. Organic Search
    WHEN COALESCE(${mediumExpr}, '') = 'organic' THEN 'Organic Search'

    -- 11. Email
    WHEN COALESCE(${mediumExpr}, '') IN ('email','e-mail','mail','newsletter') THEN 'Email'

    -- 12. SMS
    WHEN COALESCE(${mediumExpr}, '') = 'sms' THEN 'SMS'

    -- 13. Affiliate
    WHEN COALESCE(${mediumExpr}, '') = 'affiliate' THEN 'Affiliate'

    -- 14. Audio
    WHEN COALESCE(${mediumExpr}, '') IN ('audio','podcast') THEN 'Audio'

    -- 15. Mobile Push
    WHEN COALESCE(${mediumExpr}, '') IN ('push','mobile-push','app-push') THEN 'Mobile Push'

    -- 16. Referral
    WHEN COALESCE(${mediumExpr}, '') = 'referral' THEN 'Referral'

    -- 17. Direct
    WHEN COALESCE(${mediumExpr}, '(none)') IN ('(none)','') THEN 'Direct'

    -- 18. Public sample anonymised values
    WHEN COALESCE(${sourceExpr}, '') LIKE '%data deleted%' OR COALESCE(${sourceExpr}, '') LIKE '%<Other>%' THEN 'Unknown'

    -- Catch-all
    ELSE CONCAT(COALESCE(${sourceExpr}, '(direct)'), ' / ', COALESCE(${mediumExpr}, '(none)'))
  END`;
}

function getChannelList() {
  // Single source of truth for BQML feature engineering and validation.
  return [
    'Cross-network', 'Paid Search Brand', 'Paid Search Non-Brand',
    'Paid Shopping', 'Paid Social', 'Paid Video', 'Display',
    'Organic Search', 'Organic Shopping', 'Organic Social', 'Organic Video',
    'Email', 'SMS', 'Affiliate', 'Audio', 'Mobile Push', 'Referral', 'Direct', 'Unknown'
  ];
}

module.exports = { channelGrouping, getChannelList };
