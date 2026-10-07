# CPI-U Forecast Source Data

## Overview
This directory contains CPI-U inflation forecast data used to inflate future
Social Security benefits for respondents in each Survey of Consumer Finances
(SCF) survey wave. There is one CSV file per SCF survey year (every third
year from 1989 to 2022), reflecting the CBO baseline economic forecast
vintage that was publicly available around the time of that survey's
interview period.

## Why a separate file per SCF wave?
At the time a survey respondent was interviewed, only the CBO forecast
vintage published up to that point was available. Using a later CBO
forecast vintage (or realized/actual CPI) to inflate that respondent's
future benefits would introduce hindsight bias — it would assume the
respondent had information about the future that did not yet exist.

To avoid this, each SCF survey wave is paired with the CBO CPI-U forecast
that was current as of that survey period, and each forecast vintage is
stored in its own file rather than combined into a single manipulated
input file. This keeps the raw, publicly published CBO projections
separate from any model-specific transformations (see "Data manipulation"
below).

## File naming convention
```
CPI_U/{scf_year}.csv
```
where `{scf_year}` is one of: 1989, 1992, 1995, 1998, 2001, 2004, 2007,
2010, 2013, 2016, 2019, 2022.

## Source
- **Primary source (all years CBO currently hosts on this page):** CBO's
  published Key Budget and Economic Data, "Economic Projections":
  https://www.cbo.gov/data/budget-economic-data#4
- **Years not available at that link:** For SCF survey years whose
  corresponding CBO baseline vintage is no longer posted at the link
  above, data were collected from archived PDF versions of CBO's
  published economic outlook reports and hand-transcribed into CSV files
  using the naming convention described below.

### Source links by SCF survey year
CBO forecast series: **CPI-W for 1989; CPI-U for all other years (1992–2022).**

| SCF Year | Baseline Vintage Used | Index Used | Source |
|----------|------------------------|------------|--------|
| 1989     | January 1989 baseline  | CPI-W      | https://www.cbo.gov/sites/default/files/101st-congress-1989-1990/reports/89-cbo-032.pdf |
| 1992     | January 1992 baseline  | CPI-U      | https://www.cbo.gov/sites/default/files/102nd-congress-1991-1992/reports/1992_01_econoutlook.pdf |
| 1995     | January 1995 baseline  | CPI-U      | https://www.cbo.gov/sites/default/files/cbofiles/ftpdocs/55xx/doc5506/doc07-entire.pdf |
| 1998     | January 1998 baseline  | CPI-U      | https://www.cbo.gov/sites/default/files/105th-congress-1997-1998/reports/eb01-98.pdf |
| 2001     | January 2001 baseline  | CPI-U      | https://www.cbo.gov/data/budget-economic-data#4 |
| 2004     | January 2004 baseline  | CPI-U      | https://www.cbo.gov/data/budget-economic-data#4 |
| 2007     | January 2007 baseline  | CPI-U      | https://www.cbo.gov/data/budget-economic-data#4 |
| 2010     | January 2010 baseline  | CPI-U      | https://www.cbo.gov/data/budget-economic-data#4 |
| 2013     | February 2013 baseline | CPI-U      | https://www.cbo.gov/data/budget-economic-data#4 |
| 2016     | January 2016 baseline  | CPI-U      | https://www.cbo.gov/data/budget-economic-data#4 |
| 2019     | January 2019 baseline  | CPI-U      | https://www.cbo.gov/data/budget-economic-data#4 |
| 2022     | May 2022 baseline      | CPI-U      | https://www.cbo.gov/data/budget-economic-data#4 |

### Historical (actual/realized) CPI-U values
For years prior to each forecast's starting point (i.e., the historical/
actual CPI-U values included alongside the forward-looking forecast in
each file), historical values are **not** taken from each CBO baseline's
own historical section. Instead, all files use the same historical CPI-U
series, taken from CBO's **May 2022** "Historical Data and Economic
Projections" release:
https://www.cbo.gov/data/budget-economic-data#11

This is the same historical series used in
`inputs/parameters/inflation_forecast.csv`. Using a single,
consistent historical series across all vintage files avoids
discrepancies from historical data revisions that may differ across CBO
baseline releases.

### Baseline vintage notes
- The 1989 file uses **CPI-W**, not CPI-U, because CPI-W (not CPI-U) was
  the series published in the source document available for that year.
  All other years (1992–2022) use CPI-U forecasts.
- Where a survey year had multiple CBO baselines released in the same
  calendar year (2013, 2022), the specific vintage listed in the
  table above was selected as the source (e.g., February for 2013,
  May for 2022).


## Data manipulation
Beyond selecting the appropriate CBO baseline vintage and column(s) for
each survey year, the following transformations are applied in code
(see `cr_matrix_cpi_cbo_f` in `code/matrix_programs.do`):

1. Values are converted from percentage points to decimals (divided by
   100).
2. For years beyond the end of the published CBO forecast horizon, the
   last published value is held constant.
3. Non-SCF-wave columns (i.e., all years not among the 12 files listed
   above) are set to 0, since no forecast vintage exists for those years
   in this dataset.

As a result of these transformations, the forecast series used in this
model may differ from the series used internally in CBO's own baseline
projections at the time.

