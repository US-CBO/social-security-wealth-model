/********************************************************************************
* Program:    1.calculate_individual_SS_benefits.do
* Purpose:    Compute individual-level Social Security benefit components for
*             SCF respondents and spouses. Assumes economic and program
*             parameter matrices are already in memory from
*             create_matrices.do. Specifically:
*             (1) Load SCF earnings histories and derive key demographic
*                 variables, including Normal Retirement Age (NRA).
*             (2) Construct annual earnings histories capped at the taxable
*                 maximum and convert them to age-indexed earnings vectors.
*             (3) Compute quarters of coverage by year and age, and create
*                 claiming-age-specific coverage indicators.
*             (4) Index earnings for AIME calculation, call
*                 ranking_earnings.do to compute AIME for claiming ages
*                 AGE1-AGE2, and compute AME for pre-1979 cohorts.
*             (5) Compute PIA using bend-point formulas or pre-1979 PIA tables,
*                 and apply inflation adjustments for delayed claiming.
*             (6) Compute annual retirement benefits at each possible claiming
*                 age, including early claiming reductions and delayed
*                 retirement credits.
*             (7) Compute spousal and survivor benefit amounts for all
*                 claiming-age combinations used downstream in SSW valuation.
*             (8) Save the person-level output used by
*                 2.calculate_individual_SSW.do.
*
* Inputs:     inputs/data/data{year}.csv      - SCF person-level input data
*             (in memory)                     - Economic and program matrices
*                                               created by create_matrices.do
*
* Outputs:    outputs/data/program1_output{year}.dta
*                                             - Person-level dataset containing
*                                               earnings histories, coverage
*                                               indicators, AIME/AME, PIA, and
*                                               retirement/spousal/survivor
*                                               benefit variables
*
* Intermediate:
*             outputs/data/program1_intermediate_input{year}.dta
*             outputs/data/program1_intermediate_output{year}.dta
*             (both erased at the end of the program)
*
* Args:       1  yearloop     SCF survey year (for example, 2022)
*             2  fyr          First calendar year used in SS calculations
*             3  maxretage    Maximum age for indexed earnings histories
*             4  AGE1         Minimum claiming age
*             5  AGE2         Maximum claiming age
*
* Calls:      ranking_earnings.do   (defines calculate_AIME)
*
* Called by:  0.main.do
********************************************************************************/

* Pass on local variables from the main file.
args yearloop fyr maxretage AGE1 AGE2

* A sample of SCF respondents 
import delimited using "$datainputs\data`yearloop'.csv", case(preserve) clear

* Define a local variable indicating the year in which the youngest person reaches age 75
* So this is the last year of analysis.
egen MAX= max(BIRTHYR) 
replace MAX = MAX + 75
label var MAX "Year Youngest Person Reaches age 75 in this SCF year"
local max=MAX[1]

/*******************************************************************************
    STEP 1: CREATE EARNINGS HISTORIES
*******************************************************************************/

qui gen NRA = 65 if BIRTHYR < 1941
qui replace NRA = 66 if BIRTHYR > 1940 & BIRTHYR < 1958
qui replace NRA = 67 if BIRTHYR > 1957
label var NRA "Normal Retirement Age"
* NRA stored as integer years only, rounded to whole years; 

/*******************************************************************************
		SECTION 1a: EARNINGS BY CALENDAR YEAR 
*******************************************************************************/

forvalues year = 1951/`max' {
	qui replace EARN`year' = 0 if EARN`year' == .
	qui gen EARNCAP`year' = min(EARN`year', taxmax[1,`year'-1950])  
	qui label var EARNCAP`year' "Earnings capped at taxable maximum in Year `year' in Year `year' dollars"
}

/*******************************************************************************
		 SECTION 1b.  EARNINGS VECTORS by AGE (EARN16-EARN85)
*******************************************************************************/

forvalues age = 16/85 {
	qui gen EARN`age' = 0
	qui label var EARN`age' "Earnings at Age `age' in Age `age' dollars"
}
foreach t of numlist 1951/`max' {
    forvalues i = 16/85 {
        qui replace EARN`i' = EARNCAP`t' if `t' - BIRTHYR == `i'
    }
}


/*******************************************************************************
	SECTION 2. QUARTERS OF COVERAGE (QOC)
*******************************************************************************/	 

foreach i of numlist 1951/`max' {
	gen qoc`i' = 0 if  EARNCAP`i' < QC[`i'-`fyr'+ 1, 1] | EARNCAP`i' == .
       
	replace qoc`i' = 1 if  EARNCAP`i' >=     QC[`i'-`fyr'+1, 1] &  EARNCAP`i' < .
	replace qoc`i' = 2 if  EARNCAP`i' >= 2 * QC[`i'-`fyr'+1, 1] & ///
                           EARNCAP`i' <  3 * QC[`i'-`fyr'+1, 1] &  EARNCAP`i' < . 
	replace qoc`i' = 3 if  EARNCAP`i' >= 3 * QC[`i'-`fyr'+1, 1] & ///
                           EARNCAP`i' <  4 * QC[`i'-`fyr'+1, 1] &  EARNCAP`i' < . 
	replace qoc`i' = 4 if  EARNCAP`i' >= 4 * QC[`i'-`fyr'+1, 1] &  EARNCAP`i' < .
}

forvalues i = 16/85 {
    qui gen QUARTERS`i' = .
}
foreach t of numlist 1951/`max' {
    forvalues i = 16/85 {
        qui replace QUARTERS`i' = qoc`t' if `t' - BIRTHYR == `i'
    }
}

forvalues i = 22/75 {
    local qvars
    forvalues j = 22/`i' {
        local qvars `qvars' QUARTERS`j'
    }
    qui egen totalquarters`i' = rowtotal(`qvars')
}


forvalues claimage = `AGE1'/`AGE2' {
    gen covered`claimage' = 0

    local agebc = `claimage' - 1   // Last age of earnings
                                   // Assume no earnings in the year of claiming

    replace covered`claimage' = 1 if totalquarters`agebc' < . & (BIRTHYR + 22 >= `fyr') & (totalquarters`agebc' >= 40)
	replace covered`claimage' = 1 if totalquarters`agebc' < . & (BIRTHYR + 22 <  `fyr') & (totalquarters`agebc' >= min(1, (`claimage' - (`fyr' - BIRTHYR)) / (`claimage' - 22)) * 40)
    label var covered`claimage' ///
        "Coverage-eligible at claiming age `claimage'"
}



/******************************************************************************
		SECTION 3. AIME CALCULATION - AVERAGE of TOP 35 YEARS
*******************************************************************************/
/* SSA wage-indexing rule for AIME: earnings in years through the year the
   worker turns 60 are scaled by AWI(age 60) / AWI(earnings year); earnings
   after age 60 enter at nominal value. This places older earnings on a
   comparable footing with more recent ones, reflecting economy-wide wage
   growth over the career. */

local aimeyear = 60

qui capture gen indxwg = .
label var indxwg "Wages indexed to the Age 60 for AIME calculation"
replace indxwg = .
forvalues i = 1951/`max' {
    qui replace indxwg = AWI[`i' - 1950, 1] if `i' == `aimeyear' + BIRTHYR
}

forvalues i = 1951/`max' {
    qui capture gen wage`i' = .
}
forvalues i = 1951/`max' {
    qui replace wage`i' = EARNCAP`i' * indxwg / AWI[`i' - 1950, 1] if `i' <= `aimeyear' + BIRTHYR
}
forvalues i = 1951/`max' {
    qui replace wage`i' = EARNCAP`i' if `i' > `aimeyear' + BIRTHYR
}
forvalues i = 1951/`max' {
    qui replace wage`i' = 0 if wage`i' < 0 | wage`i' == . | `i' >= BIRTHYR + `maxretage'
}
forvalues i = 1951/`max' {
    qui label var wage`i' "Wages at year `i'"
}

forvalues i = 16/85 {
    qui gen EARNwg`i' = 0
}
foreach t of numlist 1951/`max' {
    forvalues i = 16/`maxretage' {
        qui replace EARNwg`i' = wage`t' if `t' - BIRTHYR == `i'
    }
}
forvalues i = 16/`maxretage' {
    qui label var EARNwg`i' "Indexed wage at Age `i' in Age `i' dollars"
}

compress  
save "$datarelease\program1_intermediate_input`yearloop'.dta", replace

do "$codedir/ranking_earnings.do" 

calculate_AIME `AGE1' `AGE2' "program1_intermediate_input`yearloop'" "program1_intermediate_output`yearloop'"

use "$datarelease\program1_intermediate_input`yearloop'.dta", clear
merge 1:1 Y1 rstat using "$datarelease\program1_intermediate_output`yearloop'", assert(3) nogen

forvalues YEAR = `AGE1'/`AGE2' {
	gen AME`YEAR' = 0
	local a = `YEAR'
		qui while `a' >= 22 {
			replace AME`YEAR' = AME`YEAR' + EARN`a' if (BIRTHYR + 62) < 1979
	local a = `a' - 1
	}
	gen yearsAME`YEAR' = min(max(5, BIRTHYR + `YEAR' - max(1950, BIRTHYR + 22) - 5), 35)
	replace AME`YEAR' = AME`YEAR' / (yearsAME`YEAR' * 12)
}



/*******************************************************************************
		SECTION 4. PIA CALCULATION 
*******************************************************************************/

forvalues i = `AGE1'/`AGE2' {
    qui gen PIA`i' = 0
    qui label var PIA`i' "Nominal PIA at age `i'"
}
local piaage = 62

foreach y of numlist `AGE1'/`AGE2' {
 
	replace PIA`y' = (0.90 * min(AIME`y', B1[1,BIRTHYR+`piaage'-1978]) ///
	                + 0.32 * min(max(0, AIME`y' - B1[1, BIRTHYR+`piaage'-1978]), B2[1, BIRTHYR+`piaage'-1978] - B1[1, BIRTHYR+`piaage'-1978]) ///
	                + 0.15 * max(0, AIME`y'-B2[1, BIRTHYR+`piaage'-1978]))

     foreach j of numlist 1978(-1)1959 {
		local dim = PIAtable`j'[1, 5]
        foreach i of numlist 1/`dim' {
            replace PIA`y' = PIAtable`j'[`i', 3] if AME`y' >= PIAtable`j'[`i', 1] & AME`y' < PIAtable`j'[`i', 2] & BIRTHYR + `piaage' == `j'
		}
	    replace PIA`y' = PIAtable`j'[`dim', 3] if AME`y' > PIAtable`j'[`dim', 2] & AME`y' < . & BIRTHYR + `piaage' == `j'
	}
    
	replace PIA`y' = PIA`y' * CPI_forecast[BIRTHYR + `y' - `fyr' + 1, year - 1989 + 1] / CPI_forecast[BIRTHYR + `piaage' - `fyr' + 1, year - 1989 + 1] if `y' > `piaage'
	replace PIA`y' =  floor(PIA`y'*10)/10
    
}
	
gen ARI = 0.03
label var ARI "Annual Rate of Increase of PIA for delayed retirement"

qui replace ARI = 3/100   if BIRTHYR + `piaage' >= 1979 & BIRTHYR + `piaage' <= 1986
qui replace ARI = 3.5/100 if BIRTHYR + `piaage' >= 1987 & BIRTHYR + `piaage' <= 1988
qui replace ARI = 4/100   if BIRTHYR + `piaage' >= 1989 & BIRTHYR + `piaage' <= 1990
qui replace ARI = 4.5/100 if BIRTHYR + `piaage' >= 1991 & BIRTHYR + `piaage' <= 1992
qui replace ARI = 5/100   if BIRTHYR + `piaage' >= 1993 & BIRTHYR + `piaage' <= 1994
qui replace ARI = 5.5/100 if BIRTHYR + `piaage' >= 1995 & BIRTHYR + `piaage' <= 1996
qui replace ARI = 6/100   if BIRTHYR + `piaage' >= 1997 & BIRTHYR + `piaage' <= 1998
qui replace ARI = 6.5/100 if BIRTHYR + `piaage' >= 1999 & BIRTHYR + `piaage' <= 2000
qui replace ARI = 7/100   if BIRTHYR + `piaage' >= 2001 & BIRTHYR + `piaage' <= 2002
qui replace ARI = 7.5/100 if BIRTHYR + `piaage' >= 2003 & BIRTHYR + `piaage' <= 2004
qui replace ARI = 8/100   if BIRTHYR + `piaage' >= 2005



/*******************************************************************************
        SECTION 5. CALCULATE BENEFITS AT ALL POSSIBLE RETIREMENTS 
*******************************************************************************/

forvalues i = `AGE1'/`AGE2' {
    qui gen SSWBEN`i' = 0
    qui label var SSWBEN`i' "Social Security Annual Benefit - Retirement at `i'"
}
gen SSWBENNRA = .

foreach y of numlist `AGE1'/`AGE2' {
    
	replace SSWBEN`y' = PIA`y' - ///
                        PIA`y' * 0.0666 * min(max(0, NRA-`y'), 3) - ///
                        PIA`y' * 0.05 * max(0, NRA-`y'-3) + ///
                        PIA`y' * ARI * min(70 - NRA, max(0, `y'-NRA))
		                 
    qui replace SSWBEN`y' = SSWBEN`y' * 12
    qui replace SSWBENNRA = SSWBEN`y' if NRA == `y'

}



/*******************************************************************************
        SECTION 6. CALCULATE SPOUSE AND SURVIVOR BENEFITS 
*******************************************************************************/

sort Y1 rstat

gen agediff = age - ages if ages > 0 & age > 0

* Initialize potential spousal benefits
forvalues k = `AGE1'/`AGE2' {
	gen s_SSWBEN`k' = 0
}

* Assume simultaneous claiming of spouses.
forvalues k = `AGE1'/`AGE2' {
	replace s_SSWBEN`k' = 0
	forvalues d = `AGE1'/`AGE2' {
        bys Y1: replace s_SSWBEN`k' = PIA`d'[_n-1] * 12 if rstat == 2 & `d' == NRA[_n-1] & Y1[_n] == Y1[_n-1]
        bys Y1: replace s_SSWBEN`k' = PIA`d'[_n+1] * 12 if rstat == 1 & `d' == NRA[_n+1] & Y1[_n] == Y1[_n+1]
       } 
	replace s_SSWBEN`k' = 0 if s_SSWBEN`k' == .
}
* The * 0.5 below applies the 50% spousal share, so PROJECTED spousal benefits
* are halved HERE before being saved. Do-file 2 does not halve them again.
forvalues y = `AGE1'/`AGE2' {
	replace s_SSWBEN`y' = (1 - 0.01 * 25/36 * min(max(0, NRA - `y') * 12, 36) ///
                             - 0.01 * 5/12 * min(max(0, NRA - `y' - 3) * 12, 24))  * 0.5 * s_SSWBEN`y'
}

* Initialize survivor benefit
local agesurv = 60
forvalues k = `agesurv'/`AGE2' {
	forvalues j = `AGE1'/`AGE2' {
	gen surv_SSWBEN`k'`j' = 0
	}
}

gen FRA_surv = .

replace FRA_surv = 65                    if BIRTHYR <= 1939
replace FRA_surv = 65 + 2/12             if BIRTHYR == 1940
replace FRA_surv = 65 + 4/12             if BIRTHYR == 1941
replace FRA_surv = 65 + 6/12             if BIRTHYR == 1942
replace FRA_surv = 65 + 8/12             if BIRTHYR == 1943
replace FRA_surv = 65 + 10/12            if BIRTHYR == 1944
replace FRA_surv = 66                    if inrange(BIRTHYR,1945,1956)
replace FRA_surv = 66 + 2/12             if BIRTHYR == 1957
replace FRA_surv = 66 + 4/12             if BIRTHYR == 1958
replace FRA_surv = 66 + 6/12             if BIRTHYR == 1959
replace FRA_surv = 66 + 8/12             if BIRTHYR == 1960
replace FRA_surv = 66 + 10/12            if BIRTHYR == 1961
replace FRA_surv = 67                    if BIRTHYR >= 1962

* months between 60 and FRA
gen M = (FRA_surv - 60) * 12

* exact SSA monthly reduction
gen SBR = 0.285 / M

label var SBR "Survivor benefit reduction for each month of early claiming by Birthyear"

foreach k of numlist `agesurv'/`AGE2' {

    foreach j of numlist `AGE1'/`AGE2' {
* Note: uses integer NRA rather than FRA_surv as the early-claiming threshold.
* This is consistent with the integer claiming-age assumption throughout
        replace surv_SSWBEN`k'`j' = max(SSWBEN`j'[_n-1],0.825*PIA`j'[_n-1]) * (1 - max(0, (NRA - `k') * 12) * SBR) if rstat == 2 & Y1[_n] == Y1[_n-1]
        replace surv_SSWBEN`k'`j' = max(SSWBEN`j'[_n+1],0.825*PIA`j'[_n+1]) * (1 - max(0, (NRA - `k') * 12) * SBR) if rstat == 1 & Y1[_n] == Y1[_n+1]

	}	

}	




compress
save "$datarelease\program1_output`yearloop'.dta", replace
erase "$datarelease\program1_intermediate_input`yearloop'.dta"
erase "$datarelease\program1_intermediate_output`yearloop'.dta"
