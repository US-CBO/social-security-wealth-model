/********************************************************************************
* Program:    create_matrices.do
* Purpose:    Build all economic and program parameter matrices needed for
*             Social Security Wealth (SSW) calculations. Matrices are stored
*             in Stata memory and persist for the duration of the session.
*             Specifically:
*             (1) Load helper programs from matrix_programs.do.
*             (2) Construct historical and projected price-index matrices.
*             (3) Construct wage, taxable maximum, bend point, and
*                 quarters-of-coverage matrices.
*             (4) Construct discount-rate and discount-factor matrices.
*             (5) Construct OASI and DI payroll tax matrices.
*             (6) Construct CPI forecast matrices by SCF survey wave.
*             (7) Construct long-run benefit payability ratios.
*             (8) Construct pre-1979 PIA lookup tables.
*
* Inputs:     inputs/parameters/inflation_forecast.csv
*             inputs/parameters/OASDI_parameters1.csv
*             inputs/parameters/OASDI_parameters2.csv
*             inputs/parameters/Discount_factors.xlsx
*             inputs/parameters/CPI_U/{scf_year}.csv   (one file per SCF wave:
*                                 1989, 1992, 1995, 1998, 2001, 2004, 2007,
*                                 2010, 2013, 2016, 2019, 2022 — see
*                                 inputs/parameters/CPI_U/README.md for
*                                 source and vintage details)
*             inputs/parameters/OASDI_long_term_projection.csv
*             inputs/parameters/PIA_tables_pre1979_for_import.xlsx
*             code/matrix_programs.do
*
* Outputs:    In-memory Stata matrices used by downstream programs,
*             including:
*               PCE           - PCE price index
*               CPI           - CPI price index
*               AWI           - Average Wage Index
*               taxmax        - Taxable earnings maximum
*               B1            - First PIA bend point
*               B2            - Second PIA bend point
*               QC            - Quarters-of-coverage thresholds
*               y_rate        - Yield-curve rates
*               y_discount    - Yield-curve discount factors
*               y_adj         - Risk-adjustment factors
*               oasi          - OASI payroll tax rates
*               dirate        - DI payroll tax rates
*               CPI_forecast  - CPI forecast by SCF wave
*               payable       - Scheduled-benefit payability ratios
*               PIAtable*     - Pre-1979 PIA lookup tables
*
* Args:       1  fyr   First calendar year in the matrix range
*             2  lyr   Last calendar year in the matrix range
*             3  inf   Long-run inflation rate for extending price series
*             4  wg    Long-run wage growth rate for extending wage-indexed
*                      program parameters
*
* Called by:  0.main.do
********************************************************************************/


* Pass on local variables from the main file.
args fyr lyr wg inf 
** Call the programs from the cr_matrix.do do file 
include "$codedir/matrix_programs.do"

cr_matrix_pce  `fyr' `lyr' `inf' 
cr_matrix_wage `fyr' `lyr' `wg'
cr_matrix_cpi_cbo_f `fyr' `lyr' `inf' 
cr_matrix_qc   `fyr' `lyr' 
cr_matrix_taxmax `fyr' `lyr' 
cr_matrix_b1 1979 `lyr' `wg' //bendpoint matrices start at 1979
cr_matrix_b2 1979 `lyr' `wg' //bendpoint matrices start at 1979
cr_matrix_oasi
cr_matrix_di
cr_matrix_payable `fyr' `lyr'
cr_matrix_PIApre1979
* Discount rates and factors
cr_matrix_y_rate        // Risk-free rates
cr_matrix_y_discount    // Risk-free discount factors
cr_matrix_y_adj         // Risk-adjustment factors


