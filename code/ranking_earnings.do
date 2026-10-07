
/********************************************************************************
* Program:    ranking_earnings.do
* Purpose:    Define the Stata program calculate_AIME, which computes
*             Average Indexed Monthly Earnings (AIME) for each individual
*             at each claiming age in the range [min_retage, max_retage].
*             Specifically:
*             (1) Load age-indexed wage-indexed earnings (EARNwg) from the
*                 input dataset.
*             (2) Reshape earnings to long format by age.
*             (3) Merge in birth year and claiming-age-specific coverage
*                 indicators.
*             (4) Exclude earnings before 1951.
*             (5) For each claiming age from max to min:
*                 - Drop earnings at or after the claiming age.
*                 - Rank earnings within person and retain the top 35 years.
*                 - Collapse retained earnings to the person level.
*                 - Compute AIME using the prorated 35-year divisor formula.
*                 - Set AIME to zero for individuals not meeting the
*                   coverage requirement at that claiming age.
*             (6) Merge claiming-age-specific AIME files and save the result.
*
* Inputs:     outputs/data/{inputfile}.dta   - Person-level earnings dataset
*                                             containing:
*                                               Y1, rstat, BIRTHYR,
*                                               EARNwg18-EARNwg{max_retage},
*                                               covered*
*
* Outputs:    outputs/data/{outputfile}.dta  - Person-level dataset with
*                                             AIME{age} variables for each
*                                             claiming age in the requested
*                                             range
*
* Args (to calculate_AIME):
*             1  min_retage   Minimum claiming age (e.g., 62)
*             2  max_retage   Maximum claiming age (e.g., 70)
*             3  inputfile    Input dataset name (without .dta extension)
*             4  outputfile   Output dataset name (without .dta extension)
*
* Called by:  1.calculate_individual_SS_benefits.do   (via do)
********************************************************************************/

capture program drop calculate_AIME
program define calculate_AIME

    *------------------------------------------------------------*
    * Parse arguments
    *------------------------------------------------------------*

    args min_retage max_retage inputfile outputfile

    *------------------------------------------------------------*
    * Load required variables
    *------------------------------------------------------------*

    use Y1 rstat EARNwg18-EARNwg`max_retage' ///
        using "$datarelease/`inputfile'", clear

    *------------------------------------------------------------*
    * Reshape to long format (earnings by age)
    *------------------------------------------------------------*

    reshape long EARNwg, i(Y1 rstat) j(age)

    merge m:1 Y1 rstat using "$datarelease/`inputfile'", ///
        keepusing(BIRTHYR covered*) assert(3) nogen

    *------------------------------------------------------------*
    * Exclude earnings prior to 1951
    *------------------------------------------------------------*

    gen byte pre1951 = (BIRTHYR + age < 1951)

    *------------------------------------------------------------*
    * Loop over retirement ages
    *------------------------------------------------------------*

    forvalues retage = `max_retage'(-1)`min_retage' {

        preserve

        gen coveredtemp = covered`retage'

        * Drop earnings at or after retirement age and pre-1951
        drop if age >= `retage' | pre1951

        * Rank earnings (lowest = 1)
        bys Y1 rstat: egen rank_rev = rank(EARNwg), unique
        bys Y1 rstat: egen maxrank = max(rank_rev)

        gen rank`retage' = maxrank - rank_rev + 1

        drop rank_rev maxrank

        * Keep top 35 years
        drop if rank`retage' > 35

        collapse (sum) EARNwg (mean) coveredtemp BIRTHYR, by(Y1 rstat)

        * Prorated AIME formula
        * AIME denominator with proration for data availability. Earnings histories
        * only go back to 1951, so for workers whose careers began earlier the
        * divisor is scaled by the share of an assumed career (age 22 to retage)
        * falling in the post-1951 era. The min(1, ...) cap leaves the standard
        * 420-month divisor in place for workers born 1929 or later.
                    gen AIME`retage' = floor( ///
            EARNwg / ///
            ((35 * min(1, (`retage' - (1951 - BIRTHYR)) / (`retage' - 22))) * 12) ///
        )

        * Zero AIME for ineligible individuals
        replace AIME`retage' = 0 if coveredtemp == 0

        drop EARNwg coveredtemp

        tempfile AIME`retage'
        save `AIME`retage''

        restore
    }

    *------------------------------------------------------------*
    * Merge AIME files across retirement ages
    *------------------------------------------------------------*

    local min_retage_plus1 = `min_retage' + 1

    use `AIME`min_retage'', clear

    forvalues age = `min_retage_plus1'/`max_retage' {
        merge 1:1 Y1 rstat using `AIME`age'', nogen assert(3)
    }

    save "$datarelease/`outputfile'.dta", replace

end



