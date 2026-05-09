# Contributing to GA4 Attribution Models

## How to Contribute

### 1. Fork and Clone
```
git clone https://github.com/YOUR_USERNAME/ga4-attribution-models.git
cd ga4-attribution-models
```

### 2. Create a Branch
```
git checkout -b feature/your-feature-name
```

### 3. Make Changes
- Add new attribution models in `definitions/attribution_models/*.sqlx`
- Add funnel analyses in `definitions/ecommerce_funnel/`
- Update documentation as needed

### 4. Test Your Queries
- Open the BigQuery Console
- Run your query against `bigquery-public-data.ga4_obfuscated_sample_ecommerce`
- Verify results are sensible

### 5. Submit a Pull Request
- Push to your fork
- Open a PR with a description of your changes
- Reference any related issues

## SQL Style Guide

- Use uppercase for SQL keywords (SELECT, FROM, WHERE)
- Include DECLARE statements for date ranges at the top
- Add comments explaining complex logic
- Use backticks for `project.dataset.table` references
- Use consistent indentation (2 spaces)

## Attribution Model Ideas

Want to contribute but need ideas?
- Markov-chain attribution (probabilistic removal effect)
- Custom position-based models (W-shaped, reverse U-shaped)
- Cross-channel interaction analysis
- Time-to-conversion analysis by channel
- Multi-touch attribution with custom weights

## Bug Reports

Include:
- SQL file name
- Expected vs actual behaviour
- Sample query results (if applicable)

## Questions?

Open an issue or reach out:
- GitHub: [@GlitchG](https://github.com/GlitchG)
- [LinkedIn](https://www.linkedin.com/in/glebads)
