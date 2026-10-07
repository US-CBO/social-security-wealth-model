/********************************************************************************
* Program:    2.calculate_individual_SSW.do
* Purpose:    Compute individual-level Social Security Wealth (SSW) for SCF
*             respondents and spouses. Assumes AIME, PIA, and annual SS
*             benefit streams have already been computed by
*             1.calculate_individual_SS_benefits.do and are in memory. Specifically:
*             (1) Merge differential mortality rates (by gender, cohort,
*                 education, marital status, race, and income).
*             (2) Convert mortality rates to annual survival probabilities
*                 by calendar year.
*             (3) Construct mortality-adjusted benefit streams (own,
*                 spousal, and survivor) for all claiming ages (AGE1–AGE2),
*                 looping over each possible claiming age.
*             (4) Discount benefit streams to NPV under one of four methods:
*                 "y"  - nominal yield-curve discount factors
*                 "tr" - 20-year Treasury rate
*                 "cr" - CBO real discount rate
*                 "r"  - risk-adjusted yield-curve discount factors
*             (5) Replace projected benefits with reported SCF benefits for
*                 individuals already receiving SS
*             (6) Compute NPV of future payroll taxes (OASI, employee +
*                 employer share) and net SSW (SSW minus payroll taxes).
*             (7) Save year-specific persons, head, and spouse
*                 datasets including life expectancy.
* Simplifying assumptions:
*   - For individuals not yet receiving benefits, survivor benefit flows are
*     modeled starting at AGE1 (age 62), reflecting 62 as the earliest claiming age.
*     Ages 60-61 and potential survivor benefits at those ages are excluded from the
*     projected stream.
*   - For individuals ALREADY receiving benefits, benefits past age 60 are considered,
*     allowing for potential survivor benefit 
*
* Inputs:     (in memory)                       - Pre-computed SS benefits
*                                                 from 1.calculate_individual_SS_benefits.do
*             inputs/data/survival_rates`yearloop'.csv   // year-specific- Differential mortality rates
* Outputs:    outputs/data/program2_output_persons{year}.dta - Person-level SSW file by wave
*             outputs/data/program2_output_spouse{year}.dta - Spouse-level SSW output by wave
*             outputs/data/program2_output_head{year}.dta   - Head-level SSW output by wave
*
* Args:       1 yearloop      Survey year (numeric, e.g., 2022)
*             2 rate       Real discount rate
*             3 fyr        First calendar year for SS calculation (1951)
*             4 lyr        Last year for projection matrices (2100)
*             5 AGE1       Minimum claiming age (62)
*             6 AGE2       Maximum claiming age (70)
*             7 baseNRA    First age at which benefits can be received (= AGE1)
*             8 agesurv    Earliest claiming age for survivor benefits (60)
*             9 discnt     Discount method: "y", "tr", "cr", or "r"
* Called by:  0.main.do
********************************************************************************/

* Pass on local variables from the main file.
args yearloop rate fyr lyr AGE1 AGE2 baseNRA agesurv discnt


/*******************************************************************************
    SECTION 1. MERGE WITH SURVIVAL DATA
*******************************************************************************/

/* Merges differential mortality rates into the person-level dataset and
   constructs annual survival and mortality probability vectors (ages 30–119)
   for both the respondent and spouse.

   Mortality methodology follows Cristia (2007), with survival rates that vary
    by gender, cohort, education, marital status, race, and income.
*/   

sort Y1 year
tempfile survival_rates

import delimited using ///
    "$datainputs\survival_rates`yearloop'.csv", case(preserve) clear
save `survival_rates'

use "$datarelease\program1_output`yearloop'.dta", clear

merge m:1 Y1 year using `survival_rates'
tab _merge
assert _merge == 3 
drop if _merge ~= 3
drop _merge

* Switch from survival rates to mortality rates and label variables for clarity. 

forv i = 30/119 {  
	* Cristia differential mortality rates
	gen rcsurv`i' = 1 - cmsurv`i' if sex == 1
	qui replace rcsurv`i' = 1 - cfsurv`i' if sex == 2

	gen rcmort`i' = cmsurv`i' if sex == 1
	qui replace rcmort`i' = cfsurv`i' if sex == 2

	gen spcsurv`i' = 1 - cmsurv`i' if sexs == 1
	qui replace spcsurv`i' = 1 - cfsurv`i' if sexs == 2

	gen spcmort`i' =  cmsurv`i' if sexs == 1
	qui replace spcmort`i' = cfsurv`i' if sexs == 2
    
    label var rcsurv`i' "Survival rate at age `i'"
    label var rcmort`i' "Mortality rate at age `i'"
    label var spcsurv`i' "Survival rate of spouse at age `i'"
    label var spcmort`i' "Mortality rate of spouse at age `i'"

}


* make sure birthyear is not missing 
assert BIRTHYR!=. 

capture egen MX = max(BIRTHYR + 119)
sort MX
local mx = MX[_N]

* Generate respondent age-by-calendar-year vectors (ageX) for years yearloop–mx.
forvalues i = `fyr'/`mx' {
	qui replace age`i' = `i' - BIRTHYR if age`i' == .
}

sort Y1 rstat
forvalues i = `fyr'/`mx' {
	qui gen ages`i' = 0
}
forvalues i = `fyr'/`mx' {
	qui replace ages`i' = max(0, `i' - BIRTHYR[_n-1]) if Y1 == Y1[_n-1] & rstat == 2
}
forvalues i = `fyr'/`mx' {
	qui replace ages`i' = max(0, `i' - BIRTHYR[_n+1]) if Y1 == Y1[_n+1] & rstat == 1
}

* Map the age-indexed Cristia survival/mortality rates (rcsurv`age', etc.)
* to calendar-year-indexed vectors (rcsurvy`y', spcsurvy`y', etc.) for years
* yearloop–mx. 

* Assignment rules:
*   age <= 30 : survival = 1 (mortality negligible; treat as certain)
*   age > 30  : survival = rcsurv`age' where the individual turns `age' in year `y'
*               (i.e., BIRTHYR + age == y for respondent; BIRTHYRs + age == y for spouse)

foreach y of numlist `yearloop'/`mx' {
    
    gen rcsurvy`y' = 0
    gen spcsurvy`y' = 0
    gen rcmorty`y' = 0
    gen spcmorty`y' = 0

    foreach age of numlist 30/119 {
		 * Ages 30 and below: assume certain survival
        replace rcsurvy`y' = 1 if age`y' <= 30 & age`y' > 0 & age`y' != .
		replace spcsurvy`y' = 1 if ages`y' <= 30 & ages`y' > 0 & ages`y' != .

		* Ages above 30: assign survival probabilities from the Cristia rates based on the age reached in year `y'.
		replace rcsurvy`y' = rcsurv`age' if age`y' > 30 & age`y' < . & `y' == BIRTHYR + `age'
		replace spcsurvy`y' = spcsurv`age' if ages`y' > 30 & ages`y' < . & `y' == BIRTHYRs + `age'
	
		replace rcmorty`y' = 0 if age`y' <= 30 & age`y' > 0 & age`y' != .
		replace spcmorty`y' = 0 if ages`y' <= 30 & ages`y' > 0 & ages`y' != .
		replace rcmorty`y' = rcmort`age' if age`y' > 30 & age`y' < . & `y' == BIRTHYR + `age'
		replace spcmorty`y' = spcmort`age' if ages`y' > 30 & ages`y' < . & `y' == BIRTHYRs + `age'
	}
    
}

/* To estimate the present value (PV) of benefits for each respondent and spouse,
   multiply the expected benefit in each year by the probability of being alive
   in that year, then discount back to the present (`yearloop').
*/

forvalues i = `yearloop'/`mx' {
	qui gen prob_alive_r`i' = 1
}
forvalues i = `yearloop'/`mx' {
	qui gen prob_alive_s`i' = 1
}
* Iterative update: prob(alive in y) = prob(alive in y-1) * P(survive through y)
local y = `yearloop' + 1
qui while `y' <= `mx' {
    local lag_y = `y' - 1
    replace prob_alive_r`y' = prob_alive_r`lag_y' * rcsurvy`y'
    replace prob_alive_s`y' = prob_alive_s`lag_y' * spcsurvy`y'
    local y = `y' + 1
}


/*******************************************************************************
    SECTION 2. CALCULATED EXPECTED SOCIAL SECURITY WEALTH
*******************************************************************************/	

sort Y1 rstat 
gen sNRA = .
bys Y1 : replace sNRA = NRA[_n-1] if rstat == 2 & Y1[_n] == Y1[_n-1]
bys Y1 : replace sNRA = NRA[_n+1] if rstat == 1 & Y1[_n] == Y1[_n+1]
label var sNRA "Normal Retirement Age (spouse)"

* Initialize values
gen SSWBEN = 0
gen s_SSWBEN = 0
label var SSWBEN "Individual's reported annual SS benefit (SCF year dollars)"
label var s_SSWBEN "Partner's reported annual SS benefit (SCF year dollars)"
    
capture drop retage
foreach YEAR of numlist `AGE1'/`AGE2' {
    
    
    /***************************************************************************
        SECTION 2a. INFLATION-ADJUSTED ANNUAL BENEFITS (OWN, SPOUSE, SURVIVOR)
    ***************************************************************************/	

	gen retage = `YEAR'
	sort Y1 rstat, stable
	gen sretage = retage[_n-1] if Y1 == Y1[_n-1] & rstat == 2
	replace sretage = retage[_n+1] if Y1 == Y1[_n+1] & rstat == 1

	/* baseNRA represents the first age at which benefits can be received.
       The loop below constructs annual benefit flows for ages baseNRA–110:
       - ownBEN`y'  : respondent's own retirement benefit
       - spousalBEN`y' : spousal benefit when both spouses are alive

    */

    foreach y of numlist `baseNRA'/110 {
            
        gen ownBEN`y' = 0
        gen spousalBEN`y' = 0

        replace ownBEN`y' = SSWBEN`YEAR' if `y' >= retage

        * Spousal benefits require that both spouses have reached claiming age 
        * and that the individual is married. The spousal benefit is based on 
        * the spouse's claiming age (sretage) plus the age difference 
        * between the respondent and spouse (agediff).
        replace spousalBEN`y' = s_SSWBEN`YEAR' if `y' >= retage & `y' >= sretage + agediff & marital == 1
                
        * Adjust benefits to nominal dollars at each age using the CPI forecast. 
        * The adjustment scales benefits from the year of claiming (retage) 
        * to the year corresponding to age `y'.
        replace ownBEN`y' = ownBEN`y' * CPI_forecast[BIRTHYR + `y' - 1950, year - 1989 + 1] ///
            / CPI_forecast[BIRTHYR + retage - 1950, year - 1989 + 1] if `y' >= retage

        replace spousalBEN`y' = spousalBEN`y' * CPI_forecast[BIRTHYR + `y' - 1950, year - 1989 + 1] ///
            / CPI_forecast[BIRTHYR + retage - 1950, year - 1989 + 1] if `y' >= retage & marital == 1
            
    }			
		
    * Expected Survivor Benefit Calculation *
 
    * Initialize probabilities of dying before retirement age
    gen prob_die_bretage_r = 0   // respondent
    gen prob_die_bretage_s = 0   // spouse

    * Identify the probability that each individual dies before reaching their claiming age (retage or sretage). 
    local y = `yearloop' + 1
    qui while `y' <= `mx' {
        replace prob_die_bretage_r = (1 - prob_alive_r`y') if BIRTHYR  + retage  == `y'
        replace prob_die_bretage_s = (1 - prob_alive_s`y') if BIRTHYRs + sretage == `y'
        local y = `y' + 1
    }

    * Containers for survivor benefit amounts under two scenarios
    gen surv_SSWBEN_die_bretage = 0   // spouse dies before claiming
    gen surv_SSWBEN_die_aretage = 0   // spouse dies after claiming

    *Retrieve the relevant survivor benefit values from the pre-computed survivor benefit arrays (surv_SSWBEN`y'`yy')
       
    foreach y of numlist `AGE1'/`AGE2' {
        
        foreach yy of numlist `AGE1'/`AGE2' {

            replace surv_SSWBEN_die_bretage = surv_SSWBEN`y'`yy' if retage == `y' & `yy' == sNRA
            replace surv_SSWBEN_die_aretage = surv_SSWBEN`y'`yy' if retage == `y' & `yy' == sretage
        }
    }

    * Compute expected survivor benefit for married individuals 

    gen exp_surv_SSWBEN = prob_die_bretage_s * surv_SSWBEN_die_bretage ///
                        + (1 - prob_die_bretage_s) * surv_SSWBEN_die_aretage ///
                        if marital == 1
    replace exp_surv_SSWBEN = 0 if marital == 0

    * Construct annual survivor benefit flows for ages baseNRA–110.
    foreach y of numlist `baseNRA'/110 {
        gen survBEN`y' = 0        
        replace survBEN`y' = ///
            exp_surv_SSWBEN * ///
            CPI_forecast[BIRTHYR + `y' - 1950, year - 1989 + 1] / ///
            CPI_forecast[BIRTHYR + retage - 1950, year - 1989 + 1] ///
            if `y' >= retage
   }

	* Benefits are  age at this point, convert to calendar year **
    forvalues i = `yearloop'/`mx' {
        qui gen ownBENyear`i' = 0
    }
    forvalues i = `yearloop'/`mx' {
        qui gen spousalBENyear`i' = 0
    }
    forvalues i = `yearloop'/`mx' {
        qui gen survBENyear`i' = 0
    }
	
    local t = `baseNRA'
    qui while (`t' <= 110) {
        forvalues i = `yearloop'/`mx' {
            qui replace ownBENyear`i' = ownBEN`t' if `t' == `i' - BIRTHYR
        }
        forvalues i = `yearloop'/`mx' {
            qui replace spousalBENyear`i' = spousalBEN`t' if `t' == `i' - BIRTHYR
        }
        forvalues i = `yearloop'/`mx' {
            qui replace survBENyear`i' = survBEN`t' if `t' == `i' - BIRTHYR
        }

        local t = `t' + 1
    }
    
    
    /***************************************************************************
        SECTION 2b. MORTALITY-ADJUSTED ANNUAL BENEFITS (OWN, SPOUSE, SURVIVOR)
    ***************************************************************************/		
		
	* Initialize yearly Social Security benefit vectors (yearloop-mx)
    * SBX: expected benefit flow in year X (adjusted for survival probabilities)
    * SBpayX: benefit flow in year X after applying the share of benefits payable

    * Initialize yearly benefit vectors
    foreach p in SB SBpay {
        forvalues i = `yearloop'/`mx' {
            qui gen `p'`i' = 0
        }
    }
    forvalues i = `yearloop'/`mx' {
        qui label var SB`i' "Expected Social Security benefits in year `i'"
        qui label var SBpay`i' "Expected Social Security benefits payable in year `i'"
    }
    * Replace missing benefit values with zero
    foreach p in ownBENyear spousalBENyear survBENyear {
        forvalues i = `yearloop'/`mx' {
            qui replace `p'`i' = 0 if `p'`i' == .
        }
    }
    * Construct expected annual Social Security benefits (SBX)
    * These benefit streams apply to households where both partners are NOT yet receiving
    * benefits in the SCF interview year.

    * Case 1: Unmarried individuals
    * Benefit equals own retirement benefit weighted by probability of being alive
    forvalues i = `yearloop'/`mx' {
        qui replace SB`i' = ownBENyear`i' * prob_alive_r`i' ///
            if (`i' >= BIRTHYR + retage) & marital == 0
    }

    * Case 2: Married, spouse has not yet reached claiming age
    * Benefit equals own benefit if both alive; survivor benefit if spouse dies
    forvalues i = `yearloop'/`mx' {
        qui replace SB`i' = ///
            ownBENyear`i' * prob_alive_r`i' * prob_alive_s`i' ///
            + max(ownBENyear`i', survBENyear`i') * prob_alive_r`i' * (1 - prob_alive_s`i') ///
            if (`i' >= BIRTHYR + retage & `i' < sretage + BIRTHYRs) & marital == 1
    }
    * Case 3: Married, both spouses have reached claiming age
    * Benefit equals max(own, spousal) if both alive; survivor benefit if spouse dies
    forvalues i = `yearloop'/`mx' {
        qui replace SB`i' = ///
            max(ownBENyear`i', spousalBENyear`i') * prob_alive_r`i' * prob_alive_s`i' ///
            + max(ownBENyear`i', survBENyear`i') * prob_alive_r`i' * (1 - prob_alive_s`i') ///
            if (`i' >= BIRTHYR + retage & `i' >= sretage + BIRTHYRs) & marital == 1
    }

    * Apply the share of scheduled benefits payable in each year
    * (e.g., adjustments reflecting projected trust fund solvency)
    forvalues i = `yearloop'/`mx' {
        qui replace SBpay`i' = SB`i' * payable[min(`lyr', `i') - 1950, 1]
    }
	
	/***************************************************************************
        SECTION 2c. RISK-ADJUSTED ANNUAL BENEFITS (OWN, SPOUSE, SURVIVOR)
    ***************************************************************************/

    if "`discnt'" == "y" {

        * Discount each year's expected benefit (SBX) to NPV using nominal
        * yield-curve factors from the y_discount matrix.
        forvalues i = `yearloop'/`mx' {
            qui gen SB`discnt'`i' = ///
                SB`i' * `discnt'_discount[(year - `discnt'_discount[1,1]) / 3 + 1, min(92, max(2, `i' - `yearloop' + 2))]
        }
        * Sum discounted annual benefits across all projection years to get SSW
        egen SSW`discnt'`YEAR' = rsum(SB`discnt'*)
        label var SSW`discnt'`YEAR' "SS Wealth individual `discnt' discount "

        * Repeat discounting for the payable benefit stream (SBpayX), which
        * scales scheduled benefits by the projected SS trust-fund payable share
        forvalues i = `yearloop'/`mx' {
            qui gen SBpay`discnt'`i' = ///
                SBpay`i' * `discnt'_discount[(year - `discnt'_discount[1,1]) / 3 + 1, min(92, max(2, `i' - `yearloop' + 2))]
        }
        egen SSWpay`discnt'`YEAR' = rsum(SBpay`discnt'*)
        label var SSWpay`discnt'`YEAR' "SS Wealth individual PAYABLE `discnt' discount "
        
        * Prorate SSW by fraction of a 40-year career completed (ages 22–62).
        * min(40,...) caps years worked; max(0,...) prevents negatives;
        * outer min(1,...) caps ratio at 1 for those with a full career.
        gen PSSW`discnt'`YEAR' = ///
            SSW`discnt'`YEAR' * min(1, max(0, min(40, `yearloop' - BIRTHYR - 22)) / 40)
        label var PSSW`discnt'`YEAR' "Prorated SS Wealth, head `discnt' discount"

        * Prorate payable SSW using the same 40-year career assumption
        gen PSSWpay`discnt'`YEAR' = SSWpay`discnt'`YEAR' * min(1, max(0, min(40, `yearloop' - BIRTHYR - 22)) / 40)
        label var PSSWpay`discnt'`YEAR' "Prorated SS Wealth Payable, head `discnt' discount"
        

    }
        
    else if "`discnt'" == "tr" {

        * Discount using the 20-year nominal Treasury yield (column 22 of y_rate).
        * Standard present-value formula: 1 / (1 + r)^t, where t = years ahead.
        forvalues i = `yearloop'/`mx' {
            qui gen SB`discnt'`i' = ///
                SB`i' * (1 / ((1 + y_rate[(year - y_rate[1,1]) / 3 + 1, 22])^(`i' - `yearloop')))
        }
        * Sum discounted annual benefits across all projection years to get SSW
        egen SSW`discnt'`YEAR' = rsum(SB`discnt'*)
        label var SSW`discnt'`YEAR' "SS Wealth individual `discnt' discount "

        * Repeat for the payable benefit stream
        forvalues i = `yearloop'/`mx' {
            qui gen SBpay`discnt'`i' = ///
                SBpay`i' * (1 / ((1 + y_rate[(year - y_rate[1,1]) / 3 + 1, 22])^(`i' - `yearloop')))
        }
        egen SSWpay`discnt'`YEAR' = rsum(SBpay`discnt'*)
        label var SSWpay`discnt'`YEAR' "SS Wealth individual Payable `discnt' discount "

        * Prorate SSW by fraction of a 40-year career completed (ages 22–62)
        gen PSSW`discnt'`YEAR' = SSW`discnt'`YEAR' * min(1, max(0, min(40, `yearloop' - BIRTHYR - 22)) / 40)
        label var PSSW`discnt'`YEAR' "Prorated SS Wealth, head `discnt' discount "
        
        * Prorate payable SSW using the same 40-year career assumption
        gen PSSWpay`discnt'`YEAR' = SSWpay`discnt'`YEAR' * min(1, max(0, min(40, `yearloop' - BIRTHYR - 22)) / 40)
        label var PSSWpay`discnt'`YEAR' "Prorated SS Wealth Payable, head `discnt' discount"
        

    }

    else if "`discnt'" == "cr" {

        * Two-step CBO real discounting:
        *   Step 1 - Convert nominal benefits to `yearloop' (survey-year) constant dollars
        *            using the ratio of CPI in `yearloop' to CPI in payment year X.
        *            Both values are drawn from CPI_forecast: rows index calendar year
        *            (relative to `fyr') and columns index scenario year (relative to 1989).
        *   Step 2 - Apply the real discount rate `rate': divide by (1 + rate)^(X - yearloop).
        forvalues i = `yearloop'/`mx' {
            qui gen SB`discnt'`i' = ///
                SB`i' * CPI_forecast[`yearloop' - 1950, year - 1989 + 1] / CPI_forecast[`i' - 1950, year - 1989 + 1]
        }
        forvalues i = `yearloop'/`mx' {
            qui replace SB`discnt'`i' = ///
                SB`discnt'`i' / ((1 + `rate')^(`i' - `yearloop'))
        }
        
        * Sum real-discounted annual benefits across all projection years to get SSW
        egen SSW`discnt'`YEAR' = rsum(SB`discnt'*)
        label var SSW`discnt'`YEAR' "SS Wealth individual `discnt' discount"

        * Repeat two-step real discounting for the payable benefit stream
        forvalues i = `yearloop'/`mx' {
            qui gen SBpay`discnt'`i' = ///
                SBpay`i' * CPI_forecast[`yearloop' - 1950, year - 1989 + 1] / CPI_forecast[`i' - 1950, year - 1989 + 1]
        }
        forvalues i = `yearloop'/`mx' {
            qui replace SBpay`discnt'`i' = ///
                SBpay`discnt'`i' / ((1 + `rate')^(`i' - `yearloop'))
        }
        * Sum across all projection years to get payable SSW
        egen SSWpay`discnt'`YEAR' = rsum(SBpay`discnt'*)
        label var SSWpay`discnt'`YEAR' "SS Wealth individual Payable `discnt' discount"

        * Prorate SSW by fraction of a 40-year career completed (ages 22–62)
        gen PSSW`discnt'`YEAR' = ///
            SSW`discnt'`YEAR' * min(1, max(0, min(40, `yearloop' - BIRTHYR - 22)) / 40)
        label var PSSW`discnt'`YEAR' "Prorated SS Wealth, head `discnt' discount "

        * Prorate payable SSW using the same 40-year career assumption
        gen PSSWpay`discnt'`YEAR' = ///
            SSWpay`discnt'`YEAR' * min(1, max(0, min(40, `yearloop' - BIRTHYR - 22)) / 40)
        label var PSSWpay`discnt'`YEAR' "Prorated SS Wealth Payable, head  `discnt' discount"
        

    }
    
    else if "`discnt'" == "r" {

        * Risk-adjusted discounting multiplies two matrix factors per payment year X:
        *   y_discount - nominal yield-curve factor for year X (same as "y" method)
        *   y_adj      - market-risk adjustment factor indexed to the individual's
        *                SS claiming age (`YEAR') rather than payment year X.
        *                Using BIRTHYR + `YEAR' aligns the adjustment to the year
        *                benefits are first claimed, reflecting that SS benefit risk
        *                is resolved at the claiming decision, not at each payment.
        forvalues i = `yearloop'/`mx' {
            qui gen SB`discnt'`i' = ///
                SB`i' * y_discount[(year - y_discount[1,1]) / 3 + 1, min(92, max(2, `i' - `yearloop' + 2))] * ///
                y_adj[(year - y_discount[1,1]) / 3 + 1, min(92, max(2, BIRTHYR + `YEAR' - `yearloop' + 2))]
        }
        * Sum risk-adjusted discounted benefits across all projection years to get SSW
        egen SSW`discnt'`YEAR' = rsum(SB`discnt'*)
        label var SSW`discnt'`YEAR' "SS Wealth individual `discnt' discount "

        * Repeat risk-adjusted discounting for the payable benefit stream
        forvalues i = `yearloop'/`mx' {
            qui gen SBpay`discnt'`i' = ///
                SBpay`i' * y_discount[(year - y_discount[1,1]) / 3 + 1, min(92, max(2, `i' - `yearloop' + 2))] * ///
                y_adj[(year - y_discount[1,1]) / 3 + 1, min(92, max(2, BIRTHYR + `YEAR' - `yearloop' + 2))]
        }
        egen SSWpay`discnt'`YEAR' = rsum(SBpay`discnt'*)
        label var SSWpay`discnt'`YEAR' "SS Wealth individual Payable `discnt' discount "

        * Prorate SSW by fraction of a 40-year career completed (ages 22–62)
        gen PSSW`discnt'`YEAR' = SSW`discnt'`YEAR' * min(1, max(0, min(40, `yearloop' - BIRTHYR - 22)) / 40)
        label var PSSW`discnt'`YEAR' "Prorated SS Wealth, head `discnt' discount"

        * Prorate payable SSW using the same 40-year career assumption
        gen PSSWpay`discnt'`YEAR' = SSWpay`discnt'`YEAR' * min(1, max(0, min(40, `yearloop' - BIRTHYR - 22)) / 40)
        label var PSSWpay`discnt'`YEAR' "Prorated SS Wealth Payable, head `discnt' discount"
        

    }
		

	/***************************************************************************
		SECTION 2d. REPLACE ESTIMATED BENEFITS WITH ACTUAL BENEFITS RECEIVED (SURVEY)
	***************************************************************************/

	/* For individuals already receiving SS at the time of the SCF interview,
       replace projected benefit amounts with self-reported benefit amounts.

       Limitations of this approach:
       (1) Disability (DI) and qualifying child benefits are excluded 
       (2) For married couples where only one spouse is currently claiming,
           the non-claiming spouse's projected spousal benefit is based on our
           projected benefit, NOT a reported benefit amount.
       (3) Survivor benefits for currently-receiving individuals ARE based on
           reported benefit amounts (see survivorBEN below).

       SCF benefit variables used:
         X5304 / X5309 - Benefit type code (rstat==1 / rstat==2):
                         1=retirement, 3=survivor/dependent, 6=other SS
         X5306 / X5311 - Reported benefit amount
         X5307 / X5312 - Benefit payment frequency code:
                         4=monthly, 5=quarterly, 6=annual, 12=bi-monthly
    */

	replace SSWBEN = 0

	* Set SSWBEN to the reported benefit amount for retirement, survivor,
    * and other SS recipients (excludes DI, type code 2)
	replace SSWBEN = X5306 if (X5304 == 1 | X5304 == 3 | X5304 == 6) & rstat == 1
	replace SSWBEN = X5311 if (X5309 == 1 | X5309 == 3 | X5309 == 6) & rstat == 2

	* Convert reported benefit amounts to annual dollars using payment frequency codes
    * (X5307 for head, X5312 for spouse)
    * Frequency codes: 4=monthly (*12), 5=quarterly (*4), 6=annual (*1), 12=bi-monthly (*6)
	replace SSWBEN = SSWBEN * 12 if X5307 == 4 & (X5304 == 1 | X5304 == 3 | X5304 == 6) & rstat == 1
	replace SSWBEN = SSWBEN * 4 if X5307 == 5 & (X5304 == 1 | X5304 == 3 | X5304 == 6) & rstat == 1
	replace SSWBEN = SSWBEN * 1 if X5307 == 6 & (X5304 == 1 | X5304 == 3 | X5304 == 6) & rstat == 1
	replace SSWBEN = SSWBEN * 6 if X5307 == 12 & (X5304 == 1 | X5304 == 3 | X5304 == 6) & rstat == 1

	replace SSWBEN = SSWBEN * 12 if X5312 == 4 & (X5309 == 1 | X5309 == 3 | X5309 == 6) & rstat == 2
	replace SSWBEN = SSWBEN * 4 if X5312 == 5 & (X5309 == 1 | X5309 == 3 | X5309 == 6) & rstat == 2
	replace SSWBEN = SSWBEN * 1 if X5312 == 6 & (X5309 == 1 | X5309 == 3 | X5309 == 6) & rstat == 2
	replace SSWBEN = SSWBEN * 6 if X5312 == 12 & (X5309 == 1 | X5309 == 3 | X5309 == 6) & rstat == 2
	
	* Flag individuals currently receiving any SS benefit (retirement, survivor, or other)
    * receives_SS: used downstream to switch from projected to reported benefit streams
    * receives_RET: same scope as receives_SS here (DI excluded); retained for compatibility
	gen receives_SS = 0
		replace receives_SS = 1 if X5306 != . & (X5304 == 1 | X5304 == 3 | X5304 == 6) & rstat == 1
		replace receives_SS = 1 if X5311 != . & (X5309 == 1 | X5309 == 3 | X5309 == 6) & rstat == 2
	
	* Cross-fill spouse's benefit-receipt status within each household (Y1).
    * sreceives_SS / sreceives_RET = 1 only for married individuals (marital==1).
    * Row _n-1 is the partner when rstat==2 (spouse record follows head);
    * row _n+1 is the partner when rstat==1 (head record precedes spouse).	
	sort Y1 rstat
    gen sreceives_SS = 0 
	bys Y1 : replace sreceives_SS = receives_SS[_n-1] if rstat == 2 & Y1[_n] == Y1[_n-1] & marital == 1
	bys Y1 : replace sreceives_SS = receives_SS[_n+1] if rstat == 1 & Y1[_n] == Y1[_n+1] & marital == 1
	
	* Cross-fill the partner's annual benefit amount for use in spousal/survivor
    * benefit calculations later in the loop
	replace s_SSWBEN = 0
	sort Y1 rstat
	bys Y1 : replace s_SSWBEN = SSWBEN[_n-1] if rstat == 2 & Y1[_n] == Y1[_n-1] & marital == 1
	bys Y1 : replace s_SSWBEN = SSWBEN[_n+1] if rstat == 1 & Y1[_n] == Y1[_n+1] & marital == 1
		
	label var receives_SS "Receives any SS benefits"
	label var sreceives_SS "Spouse receives any SS and marital=1"
	label var s_SSWBEN "Spouse's SS benefits in full in SCF year dollars"


	* Convert reported benefits to nominal dollars at each age `y' (agesurv–110),
    * growing with CPI from the SCF interview year (`yearloop') forward.
    * Benefits before agesurv (earliest survivor claiming age) are set to 0.

	local y = `agesurv'

	* Initialize benefit-by-age vectors based on the individual's reported SS benefit
    forvalues i = `y'/110 {
        qui gen BEN`i' = 0
        qui label var BEN`i' "Nominal SS Benefit of Head at age `i'"
    }

	* Inflate reported benefit (SSWBEN) to nominal dollars at each future age
    * using the ratio of the CPI forecast at age `y' to the CPI at interview year.
    * Only applied for calendar years at or after the interview year.
	qui while (`y' <= 110) {
		** This restricts actual benefits to start at age 60
		if `y' < `agesurv' {
			replace BEN`y' = 0
		}
		** This extends benefits into the future with the CPI adjustment for those receiving benefits.
		** Those not receiving benefits will just have 0s
		replace BEN`y' = ///
            SSWBEN * CPI_forecast[BIRTHYR + `y' - 1950, year - 1989 + 1] / ///
            CPI_forecast[`yearloop' - 1950, year - 1989 + 1] ///
            if `y' + BIRTHYR >= `yearloop'
		local y = `y' + 1
	}			

	* Map age-indexed benefit vectors to calendar-year-indexed vectors (yBENX)
    * so they align with the discount factor matrices indexed by calendar year X
    forvalues i = `yearloop'/`mx' {
        qui gen yBEN`i' = 0
        qui gen prob_yBEN`i' = 0
    }
 
    local t = `agesurv'
    while (`t' <= 110) {
        forvalues i = `yearloop'/`mx' {
            qui replace yBEN`i' = BEN`t' if BIRTHYR + `t' == `i'
        }
        local t = `t' + 1
    }

	* Compute spousal benefit (50% of partner's reported benefit) and survivor
    * benefit (100% of partner's reported benefit) for married individuals.
    * Restricted to cases where the partner is currently receiving SS (receives_SS==1)
    * and the individual is married (marital==1). This ensures we only assign spousal/survivor
	* benefits based on actual reported benefits for current recipients, and only for married 
	* individuals.* NOTE: Simplifying assumption as the the partner's PIA is not observable in the SCF.
  
    * 0.5 * SSWBEN halves the partner's own REPORTED benefit to derive the spousal
    * benefit. For PROJECTED benefits this is already done upstream in do-file 1
    * (Section 6), so s_SSWBEN is not halved again here.

	sort Y1 rstat
	bys Y1: gen spousalBEN = 0.5 * SSWBEN[_n-1] ///
        if rstat == 2 & Y1[_n] == Y1[_n-1] & receives_SS[_n-1] == 1 & marital == 1
	bys Y1: replace spousalBEN = 0.5 * SSWBEN[_n+1] ///
        if rstat == 1 & Y1[_n] == Y1[_n+1] & receives_SS[_n+1] == 1 & marital == 1
		
	bys Y1: gen survivorBEN = SSWBEN[_n-1] ///
        if rstat == 2 & Y1[_n] == Y1[_n-1] & receives_SS[_n-1] == 1 & marital == 1
	bys Y1: replace survivorBEN = SSWBEN[_n+1] ///
        if rstat == 1 & Y1[_n] == Y1[_n+1] & receives_SS[_n+1] == 1 & marital == 1

	* Inflate spousal and survivor benefits to nominal dollars for each future
    * calendar year, starting from the individual's claiming age (retage + BIRTHYR).	 
	forvalues i = `yearloop'/`mx' {
    qui gen yspousalBEN`i' = 0
    qui gen ysurvivorBEN`i' = 0
    }

	local y = `yearloop'
	qui while `y' <= `mx' {
		replace yspousalBEN`y' = ///
            spousalBEN * CPI_forecast[`y' - 1950, year - 1989 + 1] / ///
            CPI_forecast[`yearloop' - 1950, year - 1989 + 1] ///
            if `y' >= retage + BIRTHYR & marital == 1
		replace ysurvivorBEN`y' = ///
            survivorBEN * CPI_forecast[`y' - 1950, year - 1989 + 1] / ///
            CPI_forecast[`yearloop' - 1950, year - 1989 + 1] ///
            if `y' >= retage + BIRTHYR & marital == 1
		local y = `y' + 1
	}


* =========================
* Preconditions
* =========================

assert BIRTHYR!=. & retage!=.
capture assert BIRTHYRs!=. & sretage!=. if marital==1
if _rc!=0 {
    notes _dta: Some people are missing spouse records but are marked as married
}

* Replace missing benefit components with 0 for max() to work
foreach p in yBEN yspousalBEN ysurvivorBEN {
    forvalues i = `yearloop'/`mx' {
        qui replace `p'`i' = 0 if `p'`i' == .
    }
}

* =========================
* Single (retirement only)
* =========================

forvalues i = `yearloop'/`mx' {
    replace prob_yBEN`i' = yBEN`i'*prob_alive_r`i' ///
    if marital==0 & receives_SS==1
}
* =========================
* Married, person receives retirement, spouse receives nothing
* =========================

* Before age 60
forvalues i = `yearloop'/`mx' {
    replace prob_yBEN`i' = yBEN`i'*prob_alive_r`i' ///
    if marital==1 & receives_SS==1 & sreceives_SS==0 & `i'<BIRTHYR+60
}

* Age 60 to when both have retired
forvalues i = `yearloop'/`mx' {
    qui replace prob_yBEN`i' = yBEN`i' * prob_alive_r`i' + ///
        max(yBEN`i', survBENyear`i') * prob_alive_r`i' * (1 - prob_alive_s`i') ///
        if marital==1 & receives_SS==1 & sreceives_SS==0 & ///
        inrange(`i', BIRTHYR+60, max(BIRTHYR+retage, BIRTHYRs+sretage))
}
* After both have retired
forvalues i = `yearloop'/`mx' {
    qui replace prob_yBEN`i' = max(yBEN`i',spousalBENyear`i')*prob_alive_r`i'*prob_alive_s`i' + ///
        max(yBEN`i',survBENyear`i')*prob_alive_r`i'*(1-prob_alive_s`i') ///
        if marital==1 & receives_SS==1 & sreceives_SS==0 & ///
        `i'>=BIRTHYR+retage & `i'>=BIRTHYRs+sretage
}

* =========================
* Married, both receive retirement
* =========================

* Before age 60
forvalues i = `yearloop'/`mx' {
    qui replace prob_yBEN`i' = yBEN`i' * prob_alive_r`i' ///
        if marital==1 & receives_SS==1 & sreceives_SS==1 & `i' < BIRTHYR+60
}

* Age 60 and beyond
forvalues i = `yearloop'/`mx' {
    qui replace prob_yBEN`i' = yBEN`i' * prob_alive_r`i' + ///
        max(yBEN`i', ysurvivorBEN`i') * prob_alive_r`i' * (1 - prob_alive_s`i') ///
        if marital==1 & receives_SS==1 & sreceives_SS==1 & `i' >= BIRTHYR+60
}

* =========================
* Married, person does NOT receive retirement, spouse does
* =========================

* After person retires but before spouse
forvalues i = `yearloop'/`mx' {
    qui replace prob_yBEN`i' = ownBENyear`i' * prob_alive_r`i' + ///
        ysurvivorBEN`i' * prob_alive_r`i' * (1 - prob_alive_s`i') ///
        if marital==1 & receives_SS==0 & sreceives_SS==1 & ///
        `i' >= BIRTHYR+retage & `i' < BIRTHYRs+sretage
}

* After both have retired
forvalues i = `yearloop'/`mx' {
    qui replace prob_yBEN`i' = max(ownBENyear`i', yspousalBEN`i') * prob_alive_r`i' * prob_alive_s`i' + ///
        max(ownBENyear`i', ysurvivorBEN`i') * prob_alive_r`i' * (1 - prob_alive_s`i') ///
        if marital==1 & receives_SS==0 & sreceives_SS==1 & ///
        `i' >= BIRTHYR+retage & `i' >= BIRTHYRs+sretage
}
			
				
	/* DISCOUNTING (currently-receiving individuals)
       Discounts the mortality-weighted reported benefit stream (prob_yBENX) to NPV
       using the same four methods as the projected benefit section above (Section 2b).
       SSW and PSSW are overwritten only for individuals currently receiving SS
       (receives_SS==1 | sreceives_SS==1). No prorating is applied here because
       earnings histories are complete for those already receiving benefits.
       Payable variants apply the trust-fund solvency adjustment (payable matrix). */
   
	if "`discnt'" == "y" {

		* Discount reported benefit stream using nominal yield-curve factors
        forvalues i = `yearloop'/`mx' {
            qui gen yBEN`discnt'`i' = prob_yBEN`i' * ///
                `discnt'_discount[(year - `discnt'_discount[1,1]) / 3 + 1, min(92, max(2, `i' - `yearloop' + 2))]
        }
        egen temp`discnt' = rsum(yBEN`discnt'*)

		* Overwrite projected SSW and PSSW with reported-benefit NPV for recipients
		replace SSW`discnt'`YEAR' = temp`discnt' ///
            if receives_SS == 1 | sreceives_SS == 1
		replace PSSW`discnt'`YEAR' = SSW`discnt'`YEAR' ///
            if receives_SS == 1 | sreceives_SS == 1
		
		* Payable variant: multiply discount factor by trust-fund payable share
		forvalues i = `yearloop'/`mx' {
            qui gen yBENpay`discnt'`i' = prob_yBEN`i' * ///
                `discnt'_discount[(year - `discnt'_discount[1,1]) / 3 + 1, min(92, max(2, `i' - `yearloop' + 2))] * payable[min(`lyr', `i') - 1950, 1]
        }
		egen temppay`discnt' = rsum(yBENpay`discnt'*)
		replace SSWpay`discnt'`YEAR' = temppay`discnt' ///
            if receives_SS == 1 | sreceives_SS == 1
		replace PSSWpay`discnt'`YEAR' = SSWpay`discnt'`YEAR' ///
            if receives_SS == 1 | sreceives_SS == 1

	}

	else if "`discnt'" == "tr" {

		* Discount reported benefit stream using the 20-year nominal Treasury yield
        forvalues i = `yearloop'/`mx' {
            qui gen yBEN`discnt'`i' = prob_yBEN`i' * ///
                (1 / ((1 + y_rate[(year - y_rate[1,1]) / 3 + 1, 22])^(`i' - `yearloop')))
        }
		egen temp`discnt' = rsum(yBEN`discnt'*)
		replace SSW`discnt'`YEAR' = temp`discnt' ///
            if receives_SS == 1 | sreceives_SS == 1
		replace PSSW`discnt'`YEAR' = SSW`discnt'`YEAR' ///
            if receives_SS == 1 | sreceives_SS == 1

		* Payable variant
		forvalues i = `yearloop'/`mx' {
            qui gen yBENpay`discnt'`i' = prob_yBEN`i' * ///
                (1 / ((1 + y_rate[(year - y_rate[1,1]) / 3 + 1, 22])^(`i' - `yearloop'))) * payable[min(`lyr', `i') - 1950, 1]
        }
		egen temppay`discnt' = rsum(yBENpay`discnt'*)
		replace SSWpay`discnt'`YEAR' = temppay`discnt' ///
            if receives_SS == 1 | sreceives_SS == 1
		replace PSSWpay`discnt'`YEAR' = SSWpay`discnt'`YEAR' ///
            if receives_SS == 1 | sreceives_SS == 1

	}

	else if "`discnt'" == "cr" {

		* Two-step CBO real discounting for reported benefits:
        *   Step 1 - Convert to survey-year (`yearloop') constant dollars using CPI ratio
        *   Step 2 - Apply real discount rate `rate': divide by (1 + rate)^(X - yearloop)
        * No prorating is applied because earnings histories are complete for recipients.	   
		forvalues i = `yearloop'/`mx' {
            qui gen yBEN`discnt'`i' = prob_yBEN`i' * ///
                CPI_forecast[`yearloop' - 1950, year - 1989 + 1] / CPI_forecast[`i' - 1950, year - 1989 + 1]
        }
		forvalues i = `yearloop'/`mx' {
            qui replace yBEN`discnt'`i' = ///
                yBEN`discnt'`i' / ((1 + `rate')^(`i' - `yearloop'))
        }
		egen temp`discnt' = rsum(yBEN`discnt'*)
		replace SSW`discnt'`YEAR' = temp`discnt' ///
            if receives_SS == 1 | sreceives_SS == 1
		replace PSSW`discnt'`YEAR' = SSW`discnt'`YEAR' ///
            if receives_SS == 1 | sreceives_SS == 1
		
		* Payable variant: apply trust-fund payable share before real discounting
        forvalues i = `yearloop'/`mx' {
            qui gen yBENpay`discnt'`i' = prob_yBEN`i' * ///
                (CPI_forecast[`yearloop' - 1950, year - 1989 + 1] / ///
                CPI_forecast[`i' - 1950, year - 1989 + 1]) * ///
                payable[min(`lyr', `i') - 1950, 1]
        }
        forvalues i = `yearloop'/`mx' {
            qui replace yBENpay`discnt'`i' = ///
                yBENpay`discnt'`i' / ((1 + `rate')^(`i' - `yearloop'))
        }
		egen temppay`discnt' = rsum(yBENpay`discnt'*)
		replace SSWpay`discnt'`YEAR' = temppay`discnt' ///
            if receives_SS == 1 | sreceives_SS == 1
		replace PSSWpay`discnt'`YEAR' = SSWpay`discnt'`YEAR' ///
            if receives_SS == 1 | sreceives_SS == 1

	}

	else if "`discnt'" == "r" {

		* Risk-adjusted discounting for reported benefits.
        * y_adj is NOT applied here: these are actual observed benefits, not projected
        * ones, so the market risk associated with the claiming decision has already
        * been resolved. Only the nominal yield-curve factor (y_discount) is used.
		forvalues i = `yearloop'/`mx' {
            qui gen yBEN`discnt'`i' = prob_yBEN`i' * ///
                y_discount[(year - y_discount[1,1]) / 3 + 1, min(92, max(2, `i' - `yearloop' + 2))]
        }
		egen temp`discnt' = rsum(yBEN`discnt'*)
		replace SSW`discnt'`YEAR' = temp`discnt' ///
            if receives_SS == 1 | sreceives_SS == 1
		replace PSSW`discnt'`YEAR' = SSW`discnt'`YEAR' ///
            if receives_SS == 1 | sreceives_SS == 1
		
		* Payable variant 
		forvalues i = `yearloop'/`mx' {
            qui gen yBENpay`discnt'`i' = prob_yBEN`i' * ///
                y_discount[(year - y_discount[1,1]) / 3 + 1, min(92, max(2, `i' - `yearloop' + 2))] * payable[min(`lyr', `i') - 1950, 1]
        }
		egen temppay`discnt' = rsum(yBENpay`discnt'*)
		replace SSWpay`discnt'`YEAR' = temppay`discnt' ///
            if receives_SS == 1 | sreceives_SS == 1
		replace PSSWpay`discnt'`YEAR' = SSWpay`discnt'`YEAR' ///
            if receives_SS == 1 | sreceives_SS == 1

	}	


	/*******************************************************************************
		SECTION 2e. PAYROLL TAXES
	*******************************************************************************/

	/* Computes the NPV of future OASI payroll taxes for each individual,
       discounted using the same method as the SSW calculation above.
        
       Tax base: EARNCAPX vectors (lifetime earnings), already capped at the
       taxable maximum (taxmax). Taxes are set to zero after the individual's
       claiming age (`YEAR') or if they are already receiving SS.
        
       Tax rate: oasi[X - 1950, 1] gives the OASI rate (employee share only)
       for calendar year X. Multiplied by 2 to include the employer share.
       Medicare and DI taxes are excluded.
        
       Output variables:
         PAYROLL`discnt'`YEAR' - NPV of future payroll taxes (mortality-adjusted)
         PPAYROLL`discnt'`YEAR' - set to 0 (prorated version; placeholder) */

	* The variable is defined earlier: the year in which the youngest person reaches age 75
	* Note that earoX vectors are ALREADY capped at the tax max.
	local max = MAX[1]
	local max1 = `max' + 1

	* Initialize the payroll earnings vector across all projection years
    forvalues i = `fyr'/`mx' {
        qui gen payrollearncap`i' = 0
    }
    forvalues i = `yearloop'/`max' {
        qui replace payrollearncap`i' = EARNCAP`i'  // use actual earnings within horizon
    }
    forvalues i = `max1'/`mx' {
        qui replace payrollearncap`i' = 0        // zero out beyond age-75 horizon
    }
	* Zero out earnings at or after the individual's claiming age (`YEAR'),
    * and for those already receiving SS (no further tax contributions assumed)
    forvalues i = `yearloop'/`max' {
        qui replace payrollearncap`i' = 0 ///
            if (`i' - BIRTHYR >= `YEAR' | receives_SS == 1)
    }

	if "`discnt'" == "y" {

		* Apply OASI rate and double for combined employee + employer share
        forvalues i = `yearloop'/`mx' {
            qui gen yPAYROLL`discnt'`i' = payrollearncap`i' * cond(inlist(`i', 2011, 2012), 0.0889, oasi[`i' - 1950, 1] * 2)
        }

		* Discount to NPV using nominal yield-curve factors (same matrix as SSW)
        forvalues i = `yearloop'/`mx' {
            qui replace yPAYROLL`discnt'`i' = yPAYROLL`discnt'`i' * ///
                `discnt'_discount[(year - `discnt'_discount[1,1]) / 3 + 1, min(92, max(2, `i' - `yearloop' + 2))]
        }
		* Weight by survival probability, then sum across all projection years
        forvalues i = `yearloop'/`mx' {
            qui replace yPAYROLL`discnt'`i' = yPAYROLL`discnt'`i' * prob_alive_r`i'
        }
		egen PAYROLL`discnt'`YEAR' = rsum(yPAYROLL`discnt'*)
		gen PPAYROLL`discnt'`YEAR' = 0   // placeholder; prorating not applied to taxes

	}

	else if "`discnt'" == "tr" {

		* Apply OASI rate and double for combined employee + employer share
        forvalues i = `yearloop'/`mx' {
            qui gen yPAYROLL`discnt'`i' = payrollearncap`i' * cond(inlist(`i', 2011, 2012), 0.0889, oasi[`i' - 1950, 1] * 2)
        }
		* Standard PV formula: 1 / (1 + r)^t using column 22 of y_rate
		forvalues i = `yearloop'/`mx' {
            qui replace yPAYROLL`discnt'`i' = yPAYROLL`discnt'`i' * ///
                (1 / ((1 + y_rate[(year - y_rate[1,1]) / 3 + 1, 22])^(`i' - `yearloop')))
        }

		* Weight by survival probability, then sum across all projection years
		forvalues i = `yearloop'/`mx' {
            qui replace yPAYROLL`discnt'`i' = yPAYROLL`discnt'`i' * prob_alive_r`i'
        }
		egen PAYROLL`discnt'`YEAR' = rsum(yPAYROLL`discnt'*)
		gen PPAYROLL`discnt'`YEAR' = 0

	}

	else if "`discnt'" == "cr" {

		* Apply OASI rate and double for combined employee + employer share
       forvalues i = `yearloop'/`mx' {
           qui gen yPAYROLL`discnt'`i' = payrollearncap`i' * cond(inlist(`i', 2011, 2012), 0.0889, oasi[`i' - 1950, 1] * 2)
       }

		* Step 1: Convert nominal earnings to survey-year (`yearloop') constant dollars using CPI ratio
		forvalues i = `yearloop'/`mx' {
            qui replace yPAYROLL`discnt'`i' = yPAYROLL`discnt'`i' * ///
                CPI_forecast[`yearloop' - 1950, year - 1989 + 1] / CPI_forecast[`i' - 1950, year - 1989 + 1]
        }
		* Step 2: Discount to NPV using real discount rate `rate'
		forvalues i = `yearloop'/`mx' {
            qui replace yPAYROLL`discnt'`i' = yPAYROLL`discnt'`i' / ///
                ((1 + `rate')^(`i' - `yearloop'))
        }

		* Weight by survival probability, then sum across all projection years
		forvalues i = `yearloop'/`mx' {
            qui replace yPAYROLL`discnt'`i' = yPAYROLL`discnt'`i' * prob_alive_r`i'
        }
		egen PAYROLL`discnt'`YEAR' = rsum(yPAYROLL`discnt'*)
		gen PPAYROLL`discnt'`YEAR' = 0

	}

	else if "`discnt'" == "r" {

		* Apply OASI rate and double for combined employee + employer share
        forvalues i = `yearloop'/`mx' {
            qui gen yPAYROLL`discnt'`i' = payrollearncap`i' * cond(inlist(`i', 2011, 2012), 0.0889, oasi[`i' - 1950, 1] * 2)
        }

		* Discount using both the nominal yield-curve factor (y_discount) and the
        * market-risk adjustment (y_adj), both indexed to payment year X here
        * (unlike SSW, where y_adj is indexed to the claiming age)
		forvalues i = `yearloop'/`mx' {
            qui replace yPAYROLL`discnt'`i' = yPAYROLL`discnt'`i' * ///
                y_discount[(year - y_discount[1,1]) / 3 + 1, min(92, max(2, `i' - `yearloop' + 2))] * ///
                y_adj[(year - y_adj[1,1]) / 3 + 1, min(92, max(2, `i' - `yearloop' + 2))]
        }

		* Weight by survival probability, then sum across all projection years
		forvalues i = `yearloop'/`mx' {
            qui replace yPAYROLL`discnt'`i' = yPAYROLL`discnt'`i' * prob_alive_r`i'
        }
		egen PAYROLL`discnt'`YEAR' = rsum(yPAYROLL`discnt'*)
		gen PPAYROLL`discnt'`YEAR' = 0

	}	
	
	* Net SSW = gross SSW minus NPV of future payroll taxes
    * SSWnet    uses scheduled benefits; SSWnetpay uses trust-fund-payable benefits
	gen SSWnet`discnt'`YEAR' = SSW`discnt'`YEAR' - PAYROLL`discnt'`YEAR'
	gen SSWnetpay`discnt'`YEAR' = SSWpay`discnt'`YEAR' - PAYROLL`discnt'`YEAR'

	* Validation: retain predicted benefit at this claiming age and the corresponding
    * calendar year so that downstream checks can verify dollar-year alignment
	gen PREDownBEN`YEAR' = ownBEN`YEAR' // projected retirement benefit at age `YEAR'
	gen year`YEAR' = BIRTHYR + `YEAR'   // calendar year individual turns age `YEAR'

	* Drop within-loop intermediate variables to prevent name collisions on
    * subsequent YEAR iterations. On the final iteration (YEAR == AGE2), also
    * drop the benefit-receipt flags carried through from Section 2c.
	if `YEAR' < `AGE2' {
		drop temp* spousalBEN survivorBEN BEN* receives_SS sreceives_SS ///
             yBEN* prob_yBEN*
	}	
	drop retage sretage SB* ownBEN* spousalBENyear* survBENyear* ///
        exp_surv_SSWBEN surv_SSWBEN_die_bretage surv_SSWBEN_die_aretage ///
        prob_die_bretage_r prob_die_bretage_s spousalBEN* ///
        survBEN* yspousalBEN* ysurvivorBEN* payrollearncap* yPAYROLL*

}  // End YEAR loop

**** KEEP ONLY NECESSARY VARIABLES 
keep year V1 V3 Y1 MX rstat wgt BIRTHYR NRA marital receives_SS sreceives_SS ///
    SSW* PSSW* SSWnet* PAYROLL* PSSWpay* SSWpay* ///
    willstopworkALL willstopworkFT
order year V1 V3 Y1 MX rstat wgt BIRTHYR NRA marital receives_SS sreceives_SS ///
    SSW* PSSW* SSWnet* PAYROLL* PSSWpay* SSWpay* ///
    willstopworkALL willstopworkFT

compress
save "$datarelease\program2_output_persons`yearloop'.dta", replace 

 

/*******************************************************************************
	SECTION 3. SPLIT INTO SPOUSE AND HEAD DATASETS 
*******************************************************************************/

** SPOUSE ONLY first 


use "$datarelease\program2_output_persons`yearloop'.dta", clear

keep if V1 >= 200000

** Add _s to all variable names in spouse file
rename * *_s

*Remove _s from merging variables 
rename Y1_s Y1
rename year_s year

compress
save "$datarelease\program2_output_spouse`yearloop'.dta", replace 

** HEAD ONLY

use "$datarelease\program2_output_persons`yearloop'.dta", clear

keep if V1 <200000

compress

save "$datarelease\program2_output_head`yearloop'.dta", replace


erase "$datarelease\program1_output`yearloop'.dta"
