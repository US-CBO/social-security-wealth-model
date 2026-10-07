/********************************************************************************
* Program:    matrix_programs.do
* Purpose:    Define Stata programs used to build the economic and program
*             parameter matrices for Social Security Wealth (SSW) calculations.
*             These programs are loaded into memory by create_matrices.do.
*             No matrices are constructed until the programs are called.
*
* Programs defined:
*               cr_matrix_pce         - PCE price index
*               cr_matrix_cpi         - CPI price index
*               cr_matrix_wage        - Average Wage Index (AWI)
*               cr_matrix_taxmax      - Taxable earnings maximum
*               cr_matrix_b1          - First PIA bend point
*               cr_matrix_b2          - Second PIA bend point
*               cr_matrix_qc          - Quarters-of-coverage thresholds
*               cr_matrix_y_rate      - Yield-curve rates
*               cr_matrix_y_discount  - Yield-curve discount factors
*               cr_matrix_y_adj       - Risk-adjustment factors
*               cr_matrix_oasi        - OASI payroll tax rates (employee share)
*               cr_matrix_di          - DI payroll tax rates (employee share)
*               cr_matrix_cpi_cbo_f   - CPI forecast by SCF survey wave
*               cr_matrix_payable     - Benefit payability ratios
*               cr_matrix_PIApre1979  - PIA tables for pre-1979 cohorts
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
*
* Outputs:    Program definitions loaded into memory. When called from
*             create_matrices.do, these programs construct in-memory
*             matrices such as:
*               PCE, CPI, AWI, taxmax, B1, B2, QC,
*               y_rate, y_discount, y_adj,
*               oasi, dirate, CPI_forecast, payable, PIAtable*
*
* Called by:  create_matrices.do   (via include)
********************************************************************************/
* SSA Parameters: All SSA-sourced parameters (AWI, taxable maximum, bend
* points, quarters of coverage) reflect values published at the time of this
* analysis. Years not yet published were projected using long-run growth
* assumptions, so some now-published years (e.g., 2024-2026) hold projected
* rather than actual values and will not match the current SSA website.

/*******************************************************************************
    MATRIX: PCE Price Index
*******************************************************************************/
set matsize 800

capture program drop cr_matrix_pce
program define cr_matrix_pce
*Source: CBO, "Historical Data and Economic Projections," May 2022 baseline
* (https://www.cbo.gov/data/budget-economic-data#11). Historical PCE 
* inflation for years through 2021 and CBO's forecast for 2022 and beyond
* are both taken from this same May 2022 vintage, for internal consistency.
       args fyr lyr inf 

    preserve
    import delimited "${parameters}inflation_forecast.csv", clear
    sort year
    drop if year < `fyr'

    quietly summarize year
    local MAD_lyr = r(max)
    local year_range = r(N)

    rename pc pce_var

    capture matrix drop PCE
    matrix PCE = J(`lyr'-`fyr'+1,1,.)

    assert `MAD_lyr' <= `lyr'

    forvalues i = 1/`year_range' {
        matrix PCE[`i',1] = pce_var[`i']
    }

    if `lyr' > `MAD_lyr' {
        local i = `MAD_lyr' + 1
        while `i' <= `lyr' {
            matrix PCE[`i'-`fyr'+1,1] = ///
                PCE[`i'-`fyr',1]*(1+`inf')
            local i = `i' + 1
        }
    }

   
        
   

    restore

end


/*******************************************************************************
    MATRIX: CPI Price Index
*******************************************************************************/
capture program drop cr_matrix_cpi
program define cr_matrix_cpi
*Source: CBO, "Historical Data and Economic Projections," May 2022 baseline
* (https://www.cbo.gov/data/budget-economic-data#11). Historical CPI-U
* inflation for years through 2021 and CBO's forecast for 2022 and beyond
* are both taken from this same May 2022 vintage, for internal consistency.
    * NOTE: building block only -- fills the realized-history part of CPI_forecast
    * (see cr_matrix_cpi_cbo_f)


    args fyr lyr inf 

    preserve
    import delimited "${parameters}inflation_forecast.csv", clear
    sort year
    drop if year < `fyr'
    
    quietly summarize year
    local MAD_lyr = r(max)
    local year_range = r(N)

    rename cpiu cpi_var

    capture matrix drop CPI
    matrix CPI = J(`lyr'-`fyr'+1,1,.)

    assert `MAD_lyr' <= `lyr'

    forvalues i = 1/`year_range' {
        matrix CPI[`i',1] = cpi_var[`i']
    }

    if `lyr' > `MAD_lyr' {
        local i = `MAD_lyr' + 1
        while `i' <= `lyr' {
            matrix CPI[`i'-`fyr'+1,1] = ///
                CPI[`i'-`fyr',1]*(1+`inf')
            local i = `i' + 1
        }
    }

    restore

end

/*******************************************************************************
    MATRIX: Average Wage Index (AWI)
*******************************************************************************/
capture program drop cr_matrix_wage
program define cr_matrix_wage
    * Source: Social Security Administration, Office of the Chief Actuary, "National Average Wage Index."
    * URL: https://www.ssa.gov/oact/cola/AWI.html
    args fyr lyr wg

    preserve
    import delimited "${parameters}OASDI_parameters1.csv",  clear

  

    drop if year==.
    sort year
    drop if year < `fyr'

    quietly summarize year
    local data_fyr = r(min)
    local data_lyr = r(max)
    local year_range = r(N)

    capture matrix drop AWI
    matrix AWI = J(`lyr'-`fyr'+1,1,.)

    assert `data_fyr' == 1975

    matrix AWI[1,1]  = 2799
    matrix AWI[2,1]  = 2973
    matrix AWI[3,1]  = 3139
    matrix AWI[4,1]  = 3156
    matrix AWI[5,1]  = 3301
    matrix AWI[6,1]  = 3532
    matrix AWI[7,1]  = 3642
    matrix AWI[8,1]  = 3674
    matrix AWI[9,1]  = 3856
    matrix AWI[10,1] = 4007
    matrix AWI[11,1] = 4087
    matrix AWI[12,1] = 4291
    matrix AWI[13,1] = 4397
    matrix AWI[14,1] = 4576
    matrix AWI[15,1] = 4659
    matrix AWI[16,1] = 4938
    matrix AWI[17,1] = 5213
    matrix AWI[18,1] = 5572
    matrix AWI[19,1] = 5894
    matrix AWI[20,1] = 6186
    matrix AWI[21,1] = 6497
    matrix AWI[22,1] = 7134
    matrix AWI[23,1] = 7580
    matrix AWI[24,1] = 8031

    local stop = 25 + `year_range'
    forvalues i = 25/`stop' {
        matrix AWI[`i',1] = awi_amt[`i'-24]
    }

    if `lyr' > `data_lyr' {
        local i = `data_lyr' + 1
        while `i' <= `lyr' {
            matrix AWI[`i'-`fyr'+1,1] = ///
                AWI[`i'-`fyr',1]*(1+`wg')
            local i = `i' + 1
        }
    }

    restore

end


/*******************************************************************************
    MATRIX: Taxable Earnings Maximum
*******************************************************************************/
capture program drop cr_matrix_taxmax
program define cr_matrix_taxmax
    * Source: SSA OACT, "Contribution and Benefit Base."
    * URL: https://www.ssa.gov/oact/cola/cbb.html
    args fyr lyr

    preserve
    import delimited "${parameters}OASDI_parameters1.csv", clear 
	destring, replace

    sort year
    drop if year < `fyr'

    quietly summarize year
    local data_fyr = r(min)
    local data_lyr = r(max)
    local year_range = r(N)

    capture matrix drop taxmax
    matrix taxmax = J(1,`lyr'-`fyr'+1,.)

    assert `data_fyr' == 1975

    matrix taxmax[1,1]  = 3600
    matrix taxmax[1,2]  = 3600
    matrix taxmax[1,3]  = 3600
    matrix taxmax[1,4]  = 3600
    matrix taxmax[1,5]  = 4200
    matrix taxmax[1,6]  = 4200
    matrix taxmax[1,7]  = 4200
    matrix taxmax[1,8]  = 4200
    matrix taxmax[1,9]  = 4800
    matrix taxmax[1,10] = 4800
    matrix taxmax[1,11] = 4800
    matrix taxmax[1,12] = 4800
    matrix taxmax[1,13] = 4800
    matrix taxmax[1,14] = 4800
    matrix taxmax[1,15] = 4800
    matrix taxmax[1,16] = 6600
    matrix taxmax[1,17] = 6600
    matrix taxmax[1,18] = 7800
    matrix taxmax[1,19] = 7800
    matrix taxmax[1,20] = 7800
    matrix taxmax[1,21] = 7800
    matrix taxmax[1,22] = 9000
    matrix taxmax[1,23] = 10800
    matrix taxmax[1,24] = 13200

    local stop = 25 + `year_range'
    forvalues i = 25/`stop' {
        matrix taxmax[1,`i'] = contribution_benefit_base[`i'-24]
    }

    if `lyr' > `data_lyr' {

        local i = `data_lyr' + 1
        while `i' <= `lyr' {

            assert taxmax[1,`i'-`fyr'+1]==.

            matrix taxmax[1,`i'-`fyr'+1] = ///
                taxmax[1,`data_lyr'-`fyr'+1] * ///
                (AWI[`i'-`fyr'+1,1] / AWI[`data_lyr'-`fyr'+1,1])

            matrix taxmax[1,`i'-`fyr'+1] = ///
                round(taxmax[1,`i'-`fyr'+1]/100)*100

            local i = `i' + 1
        }
    }

    restore

end


/*******************************************************************************
    MATRIX: B1 (First Bendpoint for PIA Calculation)
*******************************************************************************/
capture program drop cr_matrix_b1
program define cr_matrix_b1
    * Source: SSA OACT, "Benefit Formula Bend Points."
    * URL: https://www.ssa.gov/oact/cola/bendpoints.html
    args fyr lyr wg
    assert `fyr' >= 1979

    preserve
    import delimited "${parameters}OASDI_parameters2.csv", clear
    sort year
    drop if year < `fyr'

    quietly summarize year
    local data_lyr = r(max)
    local year_range = r(N)

    capture matrix drop B1
    matrix B1 = J(1,`lyr'-`fyr'+1,.)

    forvalues i = 1/`year_range' {
        matrix B1[1,`i'] = bendpoint1[`i']
    }

    if `lyr' > `data_lyr' {
        local i = `data_lyr' + 1
        while `i' <= `lyr' {

            assert B1[1,`i'-`fyr'+1]==.

            matrix B1[1,`i'-`fyr'+1] = ///
                round(B1[1,`i'-`fyr']*(1+`wg'))

            local i = `i' + 1
        }
    }

    restore

end
/*******************************************************************************
    MATRIX: B2 (Second Bendpoint for PIA Calculation)
*******************************************************************************/
capture program drop cr_matrix_b2
program define cr_matrix_b2
    * Source: SSA OACT, "Benefit Formula Bend Points."
    * URL: https://www.ssa.gov/oact/cola/bendpoints.html
    args fyr lyr wg
    assert `fyr' >= 1979

    preserve
    import delimited "${parameters}OASDI_parameters2.csv",clear

    sort year
    drop if year < `fyr'

    quietly summarize year
    local data_lyr = r(max)
    local year_range = r(N)

    capture matrix drop B2
    matrix B2 = J(1, `lyr'-`fyr'+1, .)

    forvalues i = 1/`year_range' {
        matrix B2[1,`i'] = bendpoint2[`i']
    }

    if `lyr' > `data_lyr' {
        local i = `data_lyr' + 1
        while `i' <= `lyr' {
            matrix B2[1,`i'-`fyr'+1] = ///
                round(B2[1,`i'-`fyr']*(1+`wg'))
            local i = `i' + 1
        }
    }

    restore
end


/*******************************************************************************
    MATRIX: Quarters of Coverage (QC)
*******************************************************************************/
capture program drop cr_matrix_qc
program define cr_matrix_qc
    * Source: SSA OACT, "Quarter of Coverage."
    * URL: https://www.ssa.gov/oact/cola/QC.html

    args fyr lyr

    preserve
    import delimited "${parameters}OASDI_parameters2.csv", clear
	destring, replace
	
    sort year
    drop if year < `fyr' | year == .

    summarize year
    local data_fyr = r(min)
    local data_lyr = r(max)
    local year_range = r(N)

    capture matrix drop QC
    matrix QC = J(`lyr'-`fyr'+1,1,.)

    assert `data_fyr' == 1975
        * Historical note: For years before 1978, a quarter of coverage was
        * credited for each quarter with $50+ in wages. Beginning in 1978, the
        * threshold became annual and indexed to the national average wage index
        * (loaded from OASDI_parameters2.csv below). The loop below fills in $50
    local y = `fyr'
    while `y' <= `data_fyr' {
        matrix QC[`y'-(`fyr'-1),1] = 50
        local y = `y' + 1
    }

    local stop = 25 + `year_range'
    forvalues i = 25/`stop' {
        matrix QC[`i',1] = quarters_cov[`i'-24]
    }

    if `lyr' > `data_lyr' {
        local i = `data_lyr' + 1
        while `i' <= `lyr' {

            matrix QC[`i'-`fyr'+1,1] = ///
                max(QC[`i'-`fyr',1], ///
                    (AWI[`i'-`fyr'-1,1] / AWI[1976-`fyr'+1,1]) ///
                    * QC[1978-`fyr'+1,1])

            matrix QC[`i'-`fyr'+1,1] = ///
                round(QC[`i'-`fyr'+1,1]/10)*10

            local i = `i' + 1
        }
    }

    restore
end


/*******************************************************************************
    MATRIX: Risk free Rates
********************************************************************************/
capture program drop cr_matrix_y_rate
program define cr_matrix_y_rate
*Source: CBO
    import excel "${parameters}\Discount_factors.xlsx", ///
        cellrange(A1:M91) sheet(risk-free rates) firstrow clear

    * Relabel variables for reshaping
    rename B y_1989
    rename C y_1992
    rename D y_1995
    rename E y_1998
    rename F y_2001
    rename G y_2004
    rename H y_2007
    rename I y_2010
    rename J y_2013
    rename K y_2016
    rename L y_2019
    rename M y_2022

    * Reshape the file, so rows are survey years and columns are years ahead
    reshape long y_, i(Yearsahead) j(year)
    replace y_ = y_/100  // Convert from percentage points
    reshape wide y_, i(year) j(Yearsahead)
    gen y_0 = 0

    * Save the data in a matrix
    mkmat year y_0 y_1-y_90, mat(y_rate) nomiss

end


/*******************************************************************************
    MATRIX: Risk free discount factors
********************************************************************************/
capture program drop cr_matrix_y_discount
program define cr_matrix_y_discount
*Source: CBO
    import excel "${parameters}\Discount_factors.xlsx", ///
        cellrange(A1:M91) sheet(risk-free discount factors) firstrow clear

    * Relabel variables for reshaping
    rename B d_1989
    rename C d_1992
    rename D d_1995
    rename E d_1998
    rename F d_2001
    rename G d_2004
    rename H d_2007
    rename I d_2010
    rename J d_2013
    rename K d_2016
    rename L d_2019
    rename M d_2022
    
    * Reshpe the file, so rows are survey years and columns are years ahead
    reshape long d_, i(Yearsahead) j(year)
    reshape wide d_, i(year) j(Yearsahead)
    gen d_0 = 1

    mkmat year d_0 d_1-d_90, mat(y_discount) nomiss

end


********************************************************************************
** Risk adjustment factors **
********************************************************************************
capture program drop cr_matrix_y_adj
program define cr_matrix_y_adj
*Source: CBO
    import excel "${parameters}\Discount_factors.xlsx", ///
        cellrange(A1:M91) sheet(risk adjustment factors) firstrow clear

    * Relabel variables for reshaping
    rename B adj_1989
    rename C adj_1992
    rename D adj_1995
    rename E adj_1998
    rename F adj_2001
    rename G adj_2004
    rename H adj_2007
    rename I adj_2010
    rename J adj_2013
    rename K adj_2016
    rename L adj_2019
    rename M adj_2022
    
    * Reshpe the file, so rows are survey years and columns are years ahead
    reshape long adj_, i(Yearsahead) j(year)
    reshape wide adj_, i(year) j(Yearsahead)
    gen adj_0 = 1

    mkmat year adj_0 adj_1-adj_90, mat(y_adj) nomiss

end

/*******************************************************************************
    MATRIX: OASI Payroll Tax (Employee Share)
*******************************************************************************/
capture program drop cr_matrix_oasi
program define cr_matrix_oasi
    * Source: SSA OACT, "Social Security and Medicare Tax Rates."
    * URL: https://www.ssa.gov/oact/progdata/oasdiRates.html
    local oasi_default = 0.053
    matrix oasi = J(2090-1951+1,1,.)

    matrix oasi[1951-1950,1]=.01500
    matrix oasi[1952-1950,1]=.01500
    matrix oasi[1953-1950,1]=.01500
    matrix oasi[1954-1950,1]=.02000
    matrix oasi[1955-1950,1]=.02000
    matrix oasi[1956-1950,1]=.02000
    matrix oasi[1957-1950,1]=.02000
    matrix oasi[1958-1950,1]=.02000
    matrix oasi[1959-1950,1]=.02250
    matrix oasi[1960-1950,1]=.02750
    matrix oasi[1961-1950,1]=.02750
    matrix oasi[1962-1950,1]=.02875
    matrix oasi[1963-1950,1]=.03375
    matrix oasi[1964-1950,1]=.03375
    matrix oasi[1965-1950,1]=.03375
    matrix oasi[1966-1950,1]=.03500
    matrix oasi[1967-1950,1]=.03550
    matrix oasi[1968-1950,1]=.03325
    matrix oasi[1969-1950,1]=.03725
    matrix oasi[1970-1950,1]=.03650
    matrix oasi[1971-1950,1]=.04050
    matrix oasi[1972-1950,1]=.04050
    matrix oasi[1973-1950,1]=.04300
    matrix oasi[1974-1950,1]=.04375
    matrix oasi[1975-1950,1]=.04375
    matrix oasi[1976-1950,1]=.04375
    matrix oasi[1977-1950,1]=.04375
    matrix oasi[1978-1950,1]=.04275
    matrix oasi[1979-1950,1]=.04330
    matrix oasi[1980-1950,1]=.04520
    matrix oasi[1981-1950,1]=.04700
    matrix oasi[1982-1950,1]=.04575
    matrix oasi[1983-1950,1]=.04775
    matrix oasi[1984-1950,1]=.05200
    matrix oasi[1985-1950,1]=.05200
    matrix oasi[1986-1950,1]=.05200
    matrix oasi[1987-1950,1]=.05200
    matrix oasi[1988-1950,1]=.05530
    matrix oasi[1989-1950,1]=.05530
    matrix oasi[1990-1950,1]=.05600
    matrix oasi[1991-1950,1]=.05600
    matrix oasi[1992-1950,1]=.05600
    matrix oasi[1993-1950,1]=.05600
    matrix oasi[1994-1950,1]=.05260
    matrix oasi[1995-1950,1]=.05260
    matrix oasi[1996-1950,1]=.05260
    matrix oasi[1997-1950,1]=.05350
    matrix oasi[1998-1950,1]=.05350
    matrix oasi[1999-1950,1]=.05350
    matrix oasi[2000-1950,1]=.05300

    local y = 2001
    while `y' <= 2090 {
        matrix oasi[`y'-1950,1] = `oasi_default'
        local y = `y' + 1
    }

    matrix oasi[2011-1950,1] = .03590 /*OASDI rate reduced by 2pp in 2011 and 2012 due to payroll tax holiday https://www.ssa.gov/oact/TR/2013/II_B_cyoper.html*/
    matrix oasi[2012-1950,1] = .03590

end


/*******************************************************************************
    MATRIX: DI Payroll Tax (Employee Share)
*******************************************************************************/
capture program drop cr_matrix_di
program define cr_matrix_di
    * Source: SSA OACT, "Social Security and Medicare Tax Rates."
    * URL: https://www.ssa.gov/oact/progdata/oasdiRates.html
    local di_default = 0.009
    matrix dirate = J(2090-1951+1,1,.)

    matrix dirate[1951-1950,1]=0
    matrix dirate[1952-1950,1]=0
    matrix dirate[1953-1950,1]=0
    matrix dirate[1954-1950,1]=0
    matrix dirate[1955-1950,1]=0
    matrix dirate[1956-1950,1]=0
    matrix dirate[1957-1950,1]=0.00250
    matrix dirate[1958-1950,1]=0.00250
    matrix dirate[1959-1950,1]=0.00250
    matrix dirate[1960-1950,1]=0.00250
    matrix dirate[1961-1950,1]=0.00250
    matrix dirate[1962-1950,1]=0.00250
    matrix dirate[1963-1950,1]=0.00250
    matrix dirate[1964-1950,1]=0.00250
    matrix dirate[1965-1950,1]=0.00250
    matrix dirate[1966-1950,1]=0.00350
    matrix dirate[1967-1950,1]=0.00350
    matrix dirate[1968-1950,1]=0.00475
    matrix dirate[1969-1950,1]=0.00475
    matrix dirate[1970-1950,1]=0.00550
    matrix dirate[1971-1950,1]=0.00550
    matrix dirate[1972-1950,1]=0.00550
    matrix dirate[1973-1950,1]=0.00550
    matrix dirate[1974-1950,1]=0.00575
    matrix dirate[1975-1950,1]=0.00575
    matrix dirate[1976-1950,1]=0.00575
    matrix dirate[1977-1950,1]=0.00575
    matrix dirate[1978-1950,1]=0.00775
    matrix dirate[1979-1950,1]=0.00750
    matrix dirate[1980-1950,1]=0.00560
    matrix dirate[1981-1950,1]=0.00650
    matrix dirate[1982-1950,1]=0.00825
    matrix dirate[1983-1950,1]=0.00625
    matrix dirate[1984-1950,1]=0.00500
    matrix dirate[1985-1950,1]=0.00500
    matrix dirate[1986-1950,1]=0.00500
    matrix dirate[1987-1950,1]=0.00500
    matrix dirate[1988-1950,1]=0.00530
    matrix dirate[1989-1950,1]=0.00530
    matrix dirate[1990-1950,1]=0.00600
    matrix dirate[1991-1950,1]=0.00600
    matrix dirate[1992-1950,1]=0.00600
    matrix dirate[1993-1950,1]=0.00600
    matrix dirate[1994-1950,1]=0.00940
    matrix dirate[1995-1950,1]=0.00940
    matrix dirate[1996-1950,1]=0.00940
    matrix dirate[1997-1950,1]=0.00850
    matrix dirate[1998-1950,1]=0.00850
    matrix dirate[1999-1950,1]=0.00850
    matrix dirate[2000-1950,1]=0.00900

    local y = 2001
    while `y' <= 2090 {
        matrix dirate[`y'-1950,1] = `di_default'
        local y = `y' + 1
    }

    matrix dirate[2011-1950,1] = .00610 /*OASDI rate reduced by 2pp in 2011 and 2012 due to payroll tax holiday https://www.ssa.gov/policy/docs/statcomps/supplement/2011/index.html*/
    matrix dirate[2012-1950,1] = .00610

end





/*******************************************************************************
    MATRIX: Payable Ratio (CBO Long-Term Projections)
*******************************************************************************/
capture program drop cr_matrix_payable
program define cr_matrix_payable
*Source: CBO
    args fyr lyr


    import delimited "${parameters}OASDI_long_term_projection.csv", clear
       * cellrange(A11:D74) sheet("6") clear

   * rename (A B C D) (year oasi di oasdi)
    gen payable_ratio = 1 - (oasdi/100)

    capture matrix drop payable
    matrix payable = J(`lyr'-`fyr'+1,1,.)

    sort year
    quietly summarize year
    local fyr_pay = r(min)
    local lyr_pay = r(max)

    forvalues year = `fyr'/`fyr_pay' {
        matrix payable[`year'-`fyr'+1,1] = 1
    }

    forvalues year = `fyr_pay'/`lyr_pay' {
        matrix payable[`year'-`fyr'+1,1] = ///
            payable_ratio[`year'-`fyr_pay'+1]
    }

    local next = `lyr_pay' + 1
    forvalues year = `next'/`lyr' {
        matrix payable[`year'-`fyr'+1,1] = ///
            payable_ratio[`lyr_pay'-`fyr_pay'+1]
    }

end


/*******************************************************************************
    MATRIX: PIA Tables for Pre-1979 Eligibility
*******************************************************************************/
/* Workers who reached age 62 (or died/became disabled) before 1979 have
   their PIA computed under pre-1979 "old-law" rules: PIA is read directly
   from a statutory benefit table that maps Average Monthly Wage (AMW) to
   PIA and maximum family benefit. A separate table exists for each year
   from 1959 to 1978, reflecting periodic benefit increases.

   This program loads each year's table from Excel into its own matrix
   (PIAtable1959, ..., PIAtable1978) for downstream lookup. Columns:
   lb/up = AMW bounds, pia = primary insurance amount, maxben = max family
   benefit, count = number of rows (used to bound the lookup loop). */
capture program drop cr_matrix_PIApre1979
program define cr_matrix_PIApre1979
*Source: "Pre-1979 PIA benefit tables for 1959–1978 from SSA, Annual Statistical Supplement to the Social Security Bulletin,
* historical editions (https://www.ssa.gov/policy/docs/statcomps/supplement/).

    local year = 1978

    while `year' >= 1959 {

        import excel "${parameters}PIA_tables_pre1979_for_import.xlsx", ///
            sheet("`year'") firstrow clear

        gen count = _N
        mkmat lb up pia maxben count, mat(PIAtable`year') nomiss
        clear

        local year = `year' - 1
    }

end
/*******************************************************************************
    MATRIX: CPI Forecast by SCF Wave
*******************************************************************************/
capture program drop cr_matrix_cpi_cbo_f
program define cr_matrix_cpi_cbo_f
*Source: CBO
/* CPI vs CPI_forecast:
   We inflate each respondent's future benefits using the CBO CPI forecast
   available at the time of their SCF survey. At interview, the future is
   unknown, so using a later vintage or realized CPI would inject hindsight.

   Each SCF-vintage forecast file (inputs/parameters/CPI_U/{scf_year}.csv)
   contains the CBO CPI-U forecast vintage available as of that survey's
   interview period. Historical CPI-U values within each of these files
   (i.e., years prior to that vintage's forecast horizon) are taken from
   the same historical CPI-U series CBO published in its May 2022
   "Historical Data and Economic Projections" release (see
   inputs/parameters/CPI_U/README.md) for consistency across vintages.

   Beyond the published forecast horizon, values are forward-filled with
   the last published value.
*/
    args fyr lyr inf 

    cr_matrix_cpi `fyr' `lyr' `inf'

    local lastyear = ${lastyear}

    * Read each vintage CSV and merge into a single wide dataset,
    * then convert to decimals and carry last value forward --
    * producing the same structure as the original CPI_forecasts.csv.
    local scf_years "1989 1992 1995 1998 2001 2004 2007 2010 2013 2016 2019 2022"

    clear
    set obs `= `lyr' - 1989 + 1'
    gen year = 1988 + _n
    * Generate all columns 1989-2022 so f1989-f2022 range and
    * yy-1989+2 column index arithmetic work as in the original.
    * Survey year columns will be filled from CSVs; intervening
    * years stay 0 and are carried forward by the loop below.
    forvalues y = 1989/`lastyear' {
        gen f`y' = .
    }

    foreach scf_yr of local scf_years {
        preserve
            import delimited "${parameters}CPI_U/`scf_yr'.csv", ///
                clear encoding(UTF-8) varnames(1)
            tempfile tmp_`scf_yr'
            save `tmp_`scf_yr''
        restore
        merge 1:1 year using `tmp_`scf_yr'', nogenerate update
    }

    sort year
    local y = 1989
    while `y' <= `lastyear' {
        replace f`y' = f`y'/100
        * Forward-fill in one pass, then set any leading missings to 0
        replace f`y' = f`y'[_n-1] if missing(f`y') & !missing(f`y'[_n-1])
        replace f`y' = 0 if missing(f`y')
        local y = `y' + 1
    }

    mkmat year f1989-f`lastyear', mat(cpi_forecast) nomiss

    capture matrix drop CPI_forecast
    matrix CPI_forecast = J(`lyr'-`fyr'+1, `lastyear'-1989+1, .)

    local y = 1951
    while `y' <= 2100 {

        local yy = 1989
        while `yy' <= `lastyear' {

            if `y' < `yy' {
                matrix CPI_forecast[`y'-`fyr'+1, `yy'-1989+1] = ///
                    CPI[`y'-`fyr'+1,1]
            }
             else {
                matrix CPI_forecast[`y'-`fyr'+1, `yy'-1989+1] = ///
                    CPI_forecast[`y'-`fyr', `yy'-1989+1] * ///
                    (1 + cpi_forecast[`y'-1989+1, `yy'-1989+2])
            }

            local yy = `yy' + 1
        }

        local y = `y' + 1
    }
	
	* Set non-SCF year columns of CPI_forecast to 0
	forvalues yy = 1989/`lastyear' {
		local is_scf = 0
		foreach scf_yr of local scf_years {
			if `yy' == `scf_yr' local is_scf = 1
		}
		if `is_scf' == 0 {
			forvalues row = 1/`= `lyr' - `fyr' + 1' {
				matrix CPI_forecast[`row', `yy'-1989+1] = 0
			}
		}
}

end





