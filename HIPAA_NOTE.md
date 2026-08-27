# HIPAA Awareness Note

**Disclaimer:** This project uses the CMS DE-SynPUF (Data Entrepreneurs'
Synthetic Public Use File), a publicly available synthetic dataset. No
Protected Health Information (PHI) is present in any file in this repository.
All provider IDs, beneficiary IDs, dates, and financial values are synthetic.

In a production environment, this pipeline would operate under HIPAA Privacy
Rule and Security Rule controls, including but not limited to:

- **Minimum necessary access** - analysts receive only the data elements
  required for the specific FWA investigation
- **Role-based access controls (RBAC)** - separate roles for data engineers,
  analysts, and investigators with tiered permissions
- **Audit logging** - all data access logged with user, timestamp, query,
  and business justification
- **Encryption** - at rest (AES-256) and in transit (TLS 1.2+) for all
  claims and beneficiary data
- **De-identification review** - per 45 CFR § 164.514, any analytical
  output shared externally must be reviewed for re-identification risk
- **Business Associate Agreements (BAA)** - required with all data
  processors, including cloud platforms (Snowflake, SAS OnDemand) and
  any third-party tools with data access

The author acknowledges that FWA detection inherently involves access to
detailed claims and provider data, and that appropriate safeguards are
essential to protect beneficiary privacy while enabling effective fraud
detection.

## Relevant Regulations

| Regulation | Scope |
|---|---|
| HIPAA Privacy Rule (45 CFR Part 160, 164) | Governs use and disclosure of PHI |
| HIPAA Security Rule (45 CFR Part 164, Subpart C) | Technical safeguards for ePHI |
| 42 CFR Part 455 (Medicaid) | Fraud and abuse detection requirements |
| 42 CFR Part 1001 (OIG) | Provider exclusion and investigation authority |
| False Claims Act (31 U.S.C. §§ 3729–3733) | Civil liability for fraudulent claims |

## Contact

For questions about data handling practices in this project, contact the
author via the repository's issue tracker.
