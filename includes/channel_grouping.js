function channelGrouping(mediumExpr, sourceExpr) {
  return `CASE
    WHEN COALESCE(${mediumExpr}, '(none)') IN ('cpc', 'ppc', 'paidsearch') THEN 'Paid Search'
    WHEN COALESCE(${mediumExpr}, '(none)') = 'organic' THEN 'Organic Search'
    WHEN LOWER(COALESCE(${mediumExpr}, '')) LIKE '%social%' THEN 'Social'
    WHEN COALESCE(${mediumExpr}, '(none)') = 'email' THEN 'Email'
    WHEN COALESCE(${mediumExpr}, '(none)') IN ('display', 'banner') THEN 'Display'
    WHEN COALESCE(${mediumExpr}, '(none)') = 'referral' THEN 'Referral'
    WHEN COALESCE(${mediumExpr}, '(none)') = 'affiliate' THEN 'Affiliate'
    WHEN COALESCE(${mediumExpr}, '(none)') IN ('(none)', '') THEN 'Direct'
    ELSE CONCAT(COALESCE(${sourceExpr}, '(direct)'), ' / ', COALESCE(${mediumExpr}, '(none)'))
  END`;
}

module.exports = { channelGrouping };
