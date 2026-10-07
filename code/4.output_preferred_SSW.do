/********************************************************************************
* Program:    4.output_preferred_SSW.do
* Purpose:    Select preferred SSW measures from the household-level dataset
*             and convert them to real-year dollars. Specifically:
*             (1) Load the merged household SSW dataset.
*             (2) Deflate all SSW, payroll tax, and net SSW variables from
*                 survey-year dollars to real `realyear' dollars using the
*                 PCE price index.
*             (3) Initialize preferred head, spouse, and household SSW
*                 variables.
*             (4) Assign preferred SSW based on the claiming-age assumption:
*                   1 = claim at age 62
*                   2 = claim at Normal Retirement Age (NRA)
*                   3 = claim at self-reported planned stop-work age
*                       (bounded to ages 62–70; falls back to NRA or age 70
*                       if missing)
*             (5) Aggregate preferred head and spouse measures to the
*                 household level.
*             (6) Save the final output dataset and remove the intermediate
*                 household file.
*
* Inputs:     outputs/data/program3_output.dta   - Household-level SSW dataset
*                                                  produced by
*                                                  3.calculate_household_SSW.do
*
* Outputs:    outputs/data/output_data.csv       - Final preferred SSW measures
*                                                  in real `realyear' dollars
*
* Args:       1  realyear      Dollar year for real conversion (e.g., 2022)
*             2  claiming_age  Claiming-age rule: 1=age 62, 2=NRA, 3=stop-work
*             3  discnt        Discount method: "y", "tr", "cr", or "r"
*             4  fyr           First year used in SS benefit calculations
*             5  AGE1          Minimum claiming age
*             6  AGE2          Maximum claiming age
* Called by:  0.main.do
********************************************************************************/

* Pass on local variables from the main file.
args realyear claiming_age discnt fyr AGE1 AGE2

use "$datarelease\program3_output.dta", clear



/*******************************************************************************
    SECTION 1: Convert All SSW to Real-Year Dollars
*******************************************************************************/

* Currently, all SSW, payroll tax, and net SSW variables are deflated to the survey year.

#delimit ;

foreach YEAR of numlist `AGE1'/`AGE2' {;

	foreach i in  SSW`discnt'`YEAR' SSW`discnt'`YEAR'_s 
				  PSSW`discnt'`YEAR' PSSW`discnt'`YEAR'_s
				  SSWnet`discnt'`YEAR' SSWnet`discnt'`YEAR'_s
				  PAYROLL`discnt'`YEAR' PAYROLL`discnt'`YEAR'_s
				  PSSWpay`discnt'`YEAR' PSSWpay`discnt'`YEAR'_s
				  SSWnetpay`discnt'`YEAR' SSWnetpay`discnt'`YEAR'_s
				  SSWpay`discnt'`YEAR' SSWpay`discnt'`YEAR'_s {;

		replace `i' = `i' * 
					  (PCE[`realyear'-`fyr'+1,1] /
					   PCE[year-`fyr'+1,1]);

	};
};

#delimit cr



/*******************************************************************************
    SECTION 2: Initialize Preferred Variables
*******************************************************************************/

foreach i in PSSW SSW SSWnet PAYROLL PSSWpay SSWnetpay SSWpay {
    
    foreach s in "" "_s" "_hh" {
        gen `i'`s'_pre = 0

    }
    
}



/*******************************************************************************
    SECTION 3: Claiming-Age Selection
*******************************************************************************/

* Assign preferred SSW based on claiming-age assumption:
* 1 = claim at age 62
* 2 = claim at Normal Retirement Age (NRA) (defined as age 65 for those born
*     in 1937 or earlier, increasing by 2 months per year for those born
*     1938–1942, age 66 for those born 1943–1954, increasing by 2 months per
*     year for those born 1955–1960, and age 67 for those born 1960 or later)
* 3 = claim at self-reported planned stop-work age (bounded by ages 62–70; falls back to NRA or 70 if missing)

if `claiming_age' == 1 {

	foreach i in PSSW SSW SSWnet PAYROLL PSSWpay SSWnetpay SSWpay {

		replace `i'_pre = `i'`discnt'`AGE1'
		replace `i'_s_pre = `i'`discnt'`AGE1'_s

	}
			
}

else if `claiming_age' == 2 {

	foreach j of numlist `AGE1'/`AGE2' {

		foreach i in PSSW SSW SSWnet PAYROLL PSSWpay SSWnetpay SSWpay {

			replace `i'_pre = `i'`discnt'`j' if NRA==`j'
			replace `i'_s_pre = `i'`discnt'`j'_s if NRA_s==`j'

		}
	}
}

else if `claiming_age' == 3 {

	gen stopworkyear = willstopworkALL
	replace stopworkyear = . if stopworkyear == 9999
	replace stopworkyear = willstopworkFT if stopworkyear == .
	replace stopworkyear = . if stopworkyear == 9999

	replace stopworkyear = max(year,stopworkyear) if stopworkyear < . & stopworkyear < 9999
	replace stopworkyear = max(BIRTHYR+62,stopworkyear) if stopworkyear < . & stopworkyear < 9999
	replace stopworkyear = min(BIRTHYR+70,stopworkyear) if stopworkyear < . & stopworkyear < 9999
	
	gen stopworkyear_s = willstopworkALL_s
	replace stopworkyear_s = . if stopworkyear_s == 9999
	replace stopworkyear_s = willstopworkFT_s if stopworkyear_s == .
	replace stopworkyear_s = . if stopworkyear_s ==9999

	replace stopworkyear_s = max(year,stopworkyear_s) ///
		if stopworkyear_s < . & stopworkyear_s < 9999
	replace stopworkyear_s = max(BIRTHYR_s+62, stopworkyear_s) ///
		if stopworkyear_s<. & stopworkyear_s<9999
	replace stopworkyear_s = min(BIRTHYR_s+70, stopworkyear_s) ///
		if stopworkyear_s<. & stopworkyear_s<9999
	
	replace stopworkyear = (BIRTHYR+NRA) ///
		if receives_SS == 1 & marital == 0
	replace stopworkyear = (BIRTHYR+NRA) ///
		if receives_SS == 1 & sreceives_SS == 1 & marital == 1
	replace stopworkyear = max(BIRTHYR+62, min(stopworkyear, BIRTHYR+70)) ///
		if receives_SS == 1 & sreceives_SS == 0 & marital == 1

 	replace stopworkyear = (BIRTHYR + NRA) if stopworkyear == . & age < NRA & age < .
	replace stopworkyear_s =(BIRTHYR_s + NRA_s) if stopworkyear_s == . & ages < NRA_s & ages < .
	replace stopworkyear = (BIRTHYR + 70) if stopworkyear == . & age >= NRA & age < .
	replace stopworkyear_s = (BIRTHYR_s + 70) if stopworkyear_s == . & ages >= NRA_s & ages < .
		
	foreach j of numlist `AGE1'/`AGE2' {

		foreach i in PSSW SSW SSWnet PAYROLL PSSWpay SSWnetpay SSWpay {
			replace `i'_pre = `i'`discnt'`j' if stopworkyear == (`j' + BIRTHYR)
			replace `i'_s_pre = `i'`discnt'`j'_s if stopworkyear_s == (`j' + BIRTHYR_s)
			replace `i'_s_pre = 0 if marital == 0


		}

	}
}		


	
/*******************************************************************************
    SECTION 4: Household measures
*******************************************************************************/

foreach i in PSSW SSW SSWnet PAYROLL PSSWpay SSWnetpay SSWpay {

	replace `i'_pre = 0 if `i'_pre == .
	replace `i'_s_pre = 0 if `i'_s_pre == .
	replace `i'_hh_pre = `i'_pre + `i'_s_pre
}



/*******************************************************************************
    SECTION 5: Output Final Dataset
*******************************************************************************/

keep Y1 YY1 year ///
    PSSW_pre PSSW_s_pre PSSW_hh_pre ///
    SSW_pre SSW_s_pre SSW_hh_pre ///
	SSWnet_pre SSWnet_s_pre SSWnet_hh_pre ///   
    PAYROLL_pre PAYROLL_s_pre PAYROLL_hh_pre ///
	PSSWpay_pre PSSWpay_s_pre PSSWpay_hh_pre ///
    SSWnetpay_pre SSWnetpay_s_pre SSWnetpay_hh_pre ///
    SSWpay_pre SSWpay_s_pre SSWpay_hh_pre 


foreach i in "pre" "s_pre" "hh_pre" {

    if "`i'" == "pre" {
        local id "worker"
    }
    else if "`i'" == "s_pre" {
        local id "spouse"
    }
    else if "`i'" == "hh_pre" {
        local id "household"
    }

    if "`discnt'" == "y" {
        local d "nominal yield curve"
    }
    else if "`discnt'" == "cr" {
        local d "CBO real rate"
    }
    else if "`discnt'" == "tr" {
        local d "treasury rate"
    }
    else if "`discnt'" == "r" {
        local d "risk-adjusted yield curve"
    }

    label var PSSW_`i' "Prorated Social Security wealth (`id'), discounted with `d'"
    label var SSW_`i' "Continuation Social Security wealth (`id'), discounted with `d'"
    label var SSWnet_`i' "SSW net of future payroll taxes (`id'), discounted with `d'"
    label var PAYROLL_`i' "NPV of future payroll taxes (`id'), discounted with `d'"
    label var PSSWpay_`i' "Payable prorated Social Security wealth (`id'), discounted with `d'"
    label var SSWnetpay_`i' "Payable SSW net of future payroll taxes (`id'), discounted with `d'"
    label var SSWpay_`i' "Payable Continuation Social Security wealth (`id'), discounted with `d'"
	
}

    
compress
export delimited using "$datarelease\output_data.csv", replace

erase "$datarelease\program3_output.dta"
