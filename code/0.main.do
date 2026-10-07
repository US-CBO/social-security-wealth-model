/********************************************************************************
* Program:    0.main.do
* Purpose:    (1) Define global paths, model parameters, and discount settings.
*             (2) Execute sequential do-files to construct Social Security
*                 Wealth (SSW):
*                 - Build economic and program parameter matrices once.
*                 - For each SCF survey year (1989–2022, step 3): set
*                   year-specific locals, compute individual SS benefits,
*                   and compute individual SSW.
*                 - Aggregate to household level.
*                 - Construct preferred SSW measures.
*
* Inputs:     None
*
* Outputs:    Logs: outputs/log/main.log
*
* Calls:      create_matrices.do                      (once)
*             1.calculate_individual_SS_benefits.do   (once per year)
*             2.calculate_individual_SSW.do           (once per year)
*             3.calculate_household_SSW.do            (once)
*             4.output_preferred_SSW.do               (once)
********************************************************************************/

clear all
capture log close
set more off
set maxvar 30000
set matsize 200
pause off
version 18.0

* Set seed to ensure the numbers don't change between runs.
set seed 16


/*******************************************************************************
    STEP 1: PROJECT PATHS
*******************************************************************************/

* Set your working directory here before running. All paths are defined relative to the working directory.
cd "C:/your/path/to/project"

local start_time $S_TIME

global codedir "code"
global datainputs "inputs\data"
global parameters  "inputs\parameters\"
global datarelease "outputs\data"
global logfolder "outputs\log"

log using "$logfolder\main.log", replace text



/*******************************************************************************
    STEP 2: MODEL YEARS
*******************************************************************************/

global lastyear 2022
local lastyear = ${lastyear}  // local alias needed to pass lastyear as a positional arg
local realyear 2022           // base year for real (deflated) dollar output

local fyr 1951   // First year of earnings used to calculate Social Security benefits
local lyr 2100   // Last year for matrices



/*******************************************************************************
    STEP 3: ECONOMIC PARAMETERS
*******************************************************************************/

local inf 0.024      // Inflation rate
local wg 0.0355      // Wage growth



/*******************************************************************************
    STEP 4: DISCOUNTING ASSUMPTIONS
*******************************************************************************/

* Discount type options: "y"  = nominal yield curve
*                        "tr" = 20-year Treasury rate
*                        "cr" = CBO constant real rate
*                        "r"  = risk-adjusted yield curve
local discnt "r"
local rate 0.028     // constant real rate used in discounting



/*******************************************************************************
    STEP 5: AGE PARAMETERS
*******************************************************************************/

local maxretage 75         // Last age for earnings vectors
local claiming_age 3       // 1 = earliest (age 62); 2 = normal retirement age; 3 = stop-work age
local AGE1 62              // Minimal claim age for OASDI
local AGE2 70              // Maximal claim age for OASDI
local agesurv 60           // Earliest claiming age for survivor benefits
local baseNRA `AGE1'       // Earliest age at which benefits begin


                                             
/*******************************************************************************
    STEP 6: RUN SEQUENTIAL FILES
*******************************************************************************/

display "Starting SSW construction at `start_time'"

* Create matrices to hold parameters used in the calculations
do "$codedir/create_matrices.do" `fyr' `lyr' `wg' `inf' 

forvalues yearloop = `lastyear'(-3)1989 {

    display "Processing year `yearloop'"
    
     * Calculate annual Social Security benefits
    do "$codedir/1.calculate_individual_SS_benefits.do" ///
        `yearloop' `fyr' `maxretage' `AGE1' `AGE2'

    * Calculate lifetime SS benefits
    do "$codedir/2.calculate_individual_SSW.do" ///
        `yearloop' `rate' `fyr' `lyr' `AGE1' `AGE2' ///
        `baseNRA' `agesurv'  `discnt'
}

do "$codedir/3.calculate_household_SSW.do" `lastyear'

do "$codedir/4.output_preferred_SSW.do" ///
    `realyear' `claiming_age' `discnt' `fyr' `AGE1' `AGE2'

display "SSW construction completed."

log close
