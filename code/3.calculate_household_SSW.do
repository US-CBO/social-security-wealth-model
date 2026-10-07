/********************************************************************************
* Program:    3.calculate_household_SSW.do
* Purpose:    Aggregate individual-level Social Security Wealth (SSW) results
*             to the household level and merge them back to the SCF data.
*             Specifically:
*             (1) Append year-specific spouse output files into a single file.
*             (2) Append year-specific head output files into a single file.
*             (3) Merge head and spouse SSW files to create a household-level
*                 SSW file.
*             (4) Append SCF input data across survey waves and retain the
*                 household-level SCF records used for merging.
*             (5) Merge household-level SSW results back to the SCF data.
*             (6) Save the merged household dataset for the final output step
*                 and remove intermediate files.
*
* Inputs:     outputs/data/program2_output_head{year}.dta
*                                             - Head-level SSW output by wave
*             outputs/data/program2_output_spouse{year}.dta
*                                             - Spouse-level SSW output by wave
*             outputs/data/program2_output_persons{year}.dta
*                                             - Person-level SSW file by wave
*                                               (deleted after use)
*             inputs/data/data{year}.csv     - SCF input data by wave
*
* Outputs:    outputs/data/program3_output.dta
*                                             - Household-level SCF dataset
*                                               merged with SSW results
*
* Intermediate:
*             outputs/data/program2_output_head_all.dta
*             outputs/data/program2_output_spouse_all.dta
*             outputs/data/program2_output_household.dta
*             outputs/data/data1989-`lastyear'.dta
*             (all erased at the end of the program)
*
* Args:       1  lastyear   Last SCF survey year to process
*
* Called by:  0.main.do
********************************************************************************/

args lastyear

/*******************************************************************************
    SECTION 1: Append Spouse Files Across Waves
*******************************************************************************/

use "$datarelease\program2_output_spouse1989.dta", clear

forvalues yearloop = 1992(3)`lastyear' {
    append using "$datarelease\program2_output_spouse`yearloop'.dta"
}

sort Y1 year
save "$datarelease\program2_output_spouse_all.dta", replace



/*******************************************************************************
    SECTION 2: Append Head Files Across Waves
*******************************************************************************/

use "$datarelease\program2_output_head1989.dta", clear

forvalues yearloop = 1992(3)`lastyear' {
    append using "$datarelease\program2_output_head`yearloop'.dta"
}

sort Y1 year
save "$datarelease\program2_output_head_all.dta", replace

* Clean up per-wave intermediate files
forvalues yearloop = 1989(3)`lastyear' {
    erase "$datarelease\program2_output_head`yearloop'.dta"
    erase "$datarelease\program2_output_spouse`yearloop'.dta"
    erase "$datarelease\program2_output_persons`yearloop'.dta"
}

/*******************************************************************************
    SECTION 3: Merge Head and Spouse
*******************************************************************************/

use "$datarelease\program2_output_head_all.dta", clear
sort Y1 year

merge 1:1 Y1 year using "$datarelease\program2_output_spouse_all.dta"  
tab _merge
drop _merge

save "$datarelease\program2_output_household.dta", replace



/*******************************************************************************
    SECTION 4: Merge Household SSW Back to SCF Data
*******************************************************************************/

import delimited using "$datainputs\data1989.csv", case(preserve) clear

tempfile scf_all
save `scf_all'

forvalues yy = 1992(3)`lastyear' {

    tempfile current_wave

    import delimited using "$datainputs\data`yy'.csv", case(preserve) clear
    save `current_wave'

    use `scf_all', clear
    append using `current_wave'
    save `scf_all', replace
}

use `scf_all', clear
keep if rstat==1
save "$datarelease\data1989-`lastyear'.dta", replace
sort Y1 year

merge 1:1 Y1 year using "$datarelease\program2_output_household.dta" 
tab _merge
drop _merge

save "$datarelease\program3_output.dta", replace

erase "$datarelease\program2_output_head_all.dta"
erase "$datarelease\program2_output_spouse_all.dta"
erase "$datarelease\program2_output_household.dta"
erase "$datarelease\data1989-`lastyear'.dta"

