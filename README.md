# CBO's Social Security Wealth Model
This codebase constructs individual and household Social Security Wealth (SSW) measures using earnings history data from the [Federal Reserve Board's Survey of Consumer Finances](https://www.federalreserve.gov/econres/scfindex.htm) (SCF), Social Security program rules, survival probabilities, and discounting assumptions. The method is described in:

> Ash and Karamcheva. 2026. ["Social Security and the Distribution of Family Wealth,"](https://www.cbo.gov/publication/62263) Congressional Budget Office Working Paper 2026-5.

## Software requirements
CBO's Social Security Wealth Model was written and tested using Stata 18 MP for Windows, although it should be compatible with other versions of that program. [Stata 18](https://www.stata.com/stata18/). Because of the number of variables processed in the model, **Stata/SE** or **Stata/MP** is required to run the model. (**Stata/BE** will not be able to run the model.)
 
## Input files
- `inputs/data/`
  - `data{year}.csv`: SCF input data by survey year
  - `survival_rates{year}.csv`: mortality inputs by year

- `inputs/parameters/`
  - Inflation, wage, taxable maximum, bend point, discount-factor, and payability inputs
  - `CPI_U/{scf_year}.csv`: CPI inflation forecast, one file per SCF survey wave (1989, 1992, 1995, ..., 2022). Each file contains the CBO CPI forecast vintage available as of that survey wave's interview period.

**Data note:** This release runs on a small random demo sample. Raw SCF files alone are not sufficient; required `inputs/data/` files are pre-processed outputs from an upstream earnings-history simulation process (not included in this repository).

**Inputs note:** The CPI inflation forecast in this public release reflects values previously published by CBO, stored as one file per SCF survey wave in `inputs/parameters/CPI_U/`. Where the model requires values beyond the published forecast horizon, the last published value is carried forward. As a result, the forecast series in this release may differ from the series used internally in CBO's projections. Note that a value of 0 in a forecast file indicates that no value is provided for that year, not that the forecasted rate is zero.

## Key parameters
Parameters are set in `code/0.main.do`.

- `lastyear`: Last SCF survey year processed
- `realyear`: Base year for real-dollar outputs
- `AGE1`, `AGE2`: Claiming-age range evaluated
- `discnt`: Discounting method
- `claiming_age`: Preferred claiming-age rule
- `inf`: Long-run inflation assumption
- `wg`: Long-run wage growth assumption

## How to run the model
There are four main steps in the model, the code for which can be found in the `code/` directory. To run the entire model, however, running only a single file is necessary:
```stata
do "code/0.main.do"
```

> **Important:** Before running the model, open `code/0.main.do` and update the `cd` command at the top of the file to reflect your local directory path. For example:
> ```stata
> cd "C:/Users/yourname/your-local-path/social-security-wealth-model"
> ```
> Failure to set the correct working directory will cause file path errors.

## Output files
Examples of generated outputs include:

- `outputs/data/program1_output{year}.dta`
- `outputs/data/program2_output_persons{year}.dta`
- `outputs/data/program2_output_head{year}.dta`
- `outputs/data/program2_output_spouse{year}.dta`
- `outputs/data/data1989-2022.dta` is created and erased during program 3 as an intermediate file.
- `outputs/data/output_data.csv`

`output_data.csv` is the main output file containing preferred SSW measures.

## Acknowledgments
CBO's Social Security Wealth Model was developed by **Elizabeth Ash** (formerly of CBO) and **Nadia Karamcheva**. **Jessica Liu** and **Victoria Perez-Zetune** (both formerly of CBO) made important contributions at earlier stages of the project. **Xiaotong Niu**, **Kevin Perese**, **Ian Shayne**, and **Julie Topoleski** reviewed the code.

CBO staff used generative artificial intelligence tools to help write or review the code and documentation in this repository.Staff reviewed all materials here and CBO is responsible for the final work. Results and analytic appropriateness were verified only for the analyses identified in this repository.

## Contact
Questions may be directed to CBO's Office of Communications at [communications@cbo.gov](mailto:communications@cbo.gov). CBO will respond to inquiries as its workload permits.