# Contributing to GA4 Attribution Models

Thank you for your interest in contributing! 

## 🛠️ How to Contribute

### 1. Fork & Clone
```bash
git clone https://github.com/YOUR_USERNAME/ga4-attribution-models.git
cd ga4-attribution-models
```

### 2. Create a Branch
```bash
git checkout -b feature/your-feature-name
```

### 3. Make Changes
- Add new attribution models in `/attribution_models/`
- Add funnel analyses in `/ecommerce_funnel/`
- Update documentation as needed

### 4. Test Your Queries
```sql
-- Test with BigQuery:
-- 1. Open BigQuery Console
-- 2. Run your query against bigquery-public-data.ga4_obfuscated_sample_ecommerce
-- 3. Verify results make sense
```

### 5. Submit Pull Request
- Push to your fork
- Open PR with description of changes
- Reference any related issues

## 📏 SQL Style Guide

- Use uppercase for SQL keywords
- Include DECLARE statements for date ranges
- Add comments explaining complex logic
- Use backticks for project.dataset.table references
- Format with proper indentation

## 💡 Attribution Model Ideas

Want to contribute but need ideas?
- Data-driven attribution (using ML)
- Custom position-based models
- Cross-channel interaction analysis
- Time-to-conversion analysis
- Multi-touch attribution with custom weights

## 🐛 Bug Reports

Include:
- SQL file name
- Expected vs actual behavior
- Sample query results (if applicable)

## 📧 Questions?

Open an issue or reach out:
- GitHub: [@GlitchG](https://github.com/GlitchG)
- Telegram: [@GlitchG](https://t.me/glitch_g)
- [LinkedIn](https://www.linkedin.com/in/glebads)

---

**Thank you for helping improve this project! 🙏**
