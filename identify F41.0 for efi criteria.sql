-- Step 1: Eligible Billing Accounts with ICD F41.0
WITH EligibleBillingAccounts AS (
    SELECT 
        ba.BillingAccountKey,
        ba.PatientKey,
        ba.PrimaryEncounterKey,
        ba.CodingDateKey,
        dtd.Value AS ICD_Code
    FROM CDW.FilteredAccess.BillingAccountFact ba
    JOIN CDW.FilteredAccess.DiagnosisBridge db 
        ON ba.DiagnosisComboKey = db.DiagnosisComboKey
    JOIN CDW.FilteredAccess.DiagnosisDim dd 
        ON db.DiagnosisKey = dd.DiagnosisKey
    JOIN CDW.FilteredAccess.DiagnosisTerminologyDim dtd
        ON dd.DiagnosisKey = dtd.DiagnosisKey
    WHERE dtd.Type = 'ICD-10-CM' 
      AND dtd.Value = 'F41.0'
      AND ba.CodingDateKey BETWEEN 20210328 AND 20230228
      AND dtd.Value IS NOT NULL
),
-- Step 2: Patients with at least 2 F41.0 codes
QualifiedPatients AS (
    SELECT PatientKey
    FROM EligibleBillingAccounts
    GROUP BY PatientKey
    HAVING COUNT(DISTINCT BillingAccountKey) >= 2
),
-- Step 3: ICD summary
PatientICDData AS (
    SELECT 
        eba.PatientKey,
        MIN(eba.CodingDateKey) AS FirstBillingDate,
        STRING_AGG(eba.ICD_Code, ', ') AS ICD_Codes
    FROM EligibleBillingAccounts eba
    JOIN QualifiedPatients qp ON eba.PatientKey = qp.PatientKey
    GROUP BY eba.PatientKey
),
-- Step 4: Vitals as of 20230228
LatestVitals AS (
    SELECT vf.PatientKey,
           vf.WeightInGrams,
           vf.HeightInCentimeters,
           vf.BodyMassIndex,
           ROW_NUMBER() OVER (PARTITION BY vf.PatientKey ORDER BY vf.EncounterDateKey DESC) AS rn
    FROM CDW.FilteredAccess.VisitFact vf
    WHERE vf.EncounterDateKey <= 20230228
),
-- Step 5: ADI Score
ADI_Info AS (
    SELECT 
        p.PatientKey,
        adi.NationalPercentileRank,
        adi.StateDecileRank
    FROM CDW.FilteredAccess.PatientDim p
    JOIN CDW.FilteredAccess.AreaDeprivationIndexFact adi
        ON p.AreaDeprivationIndexKey = adi.AreaDeprivationIndexKey
),
-- Step 6: eFI Score
EFI_Score AS (
    SELECT *
    FROM (
        SELECT 
            pavd.PatientDurableKey,
            LEFT(pavd.Value, CHARINDEX('(', pavd.Value) - 1) AS Score,
            SUBSTRING(pavd.Value, CHARINDEX('=', pavd.Value) + 2, CHARINDEX(')', pavd.Value) - CHARINDEX('=', pavd.Value) - 2) AS Percentile,
            ROW_NUMBER() OVER (PARTITION BY pavd.PatientDurableKey ORDER BY dates.DateValue DESC) AS ROWNUM
        FROM CDW.FilteredAccess.PatientAttributeValueDim pavd
        JOIN CDW.FilteredAccess.AttributeDim adim ON pavd.AttributeKey = adim.AttributeKey
        JOIN CDW.FilteredAccess.DateDim dates ON pavd.DateKey = dates.DateKey
        WHERE adim.SmartDataElementEpicId = 'ATRIUM#1822'
    ) efi
    WHERE ROWNUM = 1
),
-- Step 7: Medications
Medications AS (
    SELECT 
        mof.PatientKey,
        MAX(CASE WHEN md.GenericName LIKE '%tiotropium%' THEN 'Y' ELSE 'N' END) AS LAMA,
        MAX(CASE WHEN md.GenericName LIKE '%salmeterol%' THEN 'Y' ELSE 'N' END) AS LABA,
        MAX(CASE WHEN md.GenericName LIKE '%budesonide%' THEN 'Y' ELSE 'N' END) AS ICS
    FROM CDW.FilteredAccess.MedicationOrderFact mof
    JOIN CDW.FilteredAccess.MedicationDim md ON mof.MedicationKey = md.MedicationKey
    WHERE mof.OrderedDateKey < 20230228 AND NOT md.Route LIKE '%nasal%'
    GROUP BY mof.PatientKey
),
-- Step 8: Imaging/Tests
ProcedureLookup AS (
    SELECT ProcedureKey, ProcedureName
    FROM CDW.FilteredAccess.ProcedureDim
    WHERE ProcedureName LIKE '%CT Chest%' OR ProcedureName LIKE '%Pulmonary Function%'
),
MatchedProcedures AS (
    SELECT 
        pf.PatientKey,
        pf.ProcedureKey,
        pf.ProcedureDateKey,
        pl.ProcedureName
    FROM CDW.FilteredAccess.ProcedureFact pf
    JOIN ProcedureLookup pl ON pf.ProcedureKey = pl.ProcedureKey
    WHERE pf.ProcedureDateKey < 20230228
),
RankedProcedures AS (
    SELECT *,
           CASE 
               WHEN ProcedureName LIKE '%CT Chest%' THEN 'CT Chest'
               WHEN ProcedureName LIKE '%Pulmonary Function%' THEN 'PFT'
           END AS ProcedureType,
           ROW_NUMBER() OVER (
               PARTITION BY PatientKey, 
                            CASE 
                                WHEN ProcedureName LIKE '%CT Chest%' THEN 'CT Chest'
                                WHEN ProcedureName LIKE '%Pulmonary Function%' THEN 'PFT'
                            END
               ORDER BY ProcedureDateKey DESC
           ) AS rn
    FROM MatchedProcedures
),
ProcedureFinal AS (
    SELECT 
        PatientKey,
        MAX(CASE WHEN ProcedureType = 'CT Chest' THEN 'Y' ELSE 'N' END) AS CTChestPerformed,
        MAX(CASE WHEN ProcedureType = 'CT Chest' AND rn = 1 THEN ProcedureDateKey END) AS CTChestDate,
        MAX(CASE WHEN ProcedureType = 'PFT' THEN 'Y' ELSE 'N' END) AS PFTPerformed,
        MAX(CASE WHEN ProcedureType = 'PFT' AND rn = 1 THEN ProcedureDateKey END) AS PFTDate
    FROM RankedProcedures
    GROUP BY PatientKey
)

-- Final Output
SELECT 
    icd.PatientKey,
    p.DurableKey AS WakeOneMRN,
    p.PrimaryMRN AS AHMRN,
    p.AgeInYears AS Age,
    p.BirthDate,
    p.Sex,
    p.Ethnicity,
    p.FirstRace, p.SecondRace, p.ThirdRace, p.FourthRace, p.FifthRace, p.MultiRacial,
    lv.WeightInGrams / 1000.0 AS WeightInKg,
    lv.HeightInCentimeters,
    lv.BodyMassIndex,
    p.HighestLevelOfEducation,
    p.SmokingStatus,
    adi.NationalPercentileRank,
    adi.StateDecileRank,
    efi.Score AS eFI_Score,
    efi.Percentile AS eFI_Percentile,
    icd.FirstBillingDate,
    icd.ICD_Codes,
    meds.LAMA,
    meds.LABA,
    meds.ICS,
    proc.CTChestPerformed,
    proc.CTChestDate,
    proc.PFTPerformed,
    proc.PFTDate
FROM PatientICDData icd
JOIN CDW.FilteredAccess.PatientDim p ON icd.PatientKey = p.PatientKey
LEFT JOIN LatestVitals lv ON icd.PatientKey = lv.PatientKey AND lv.rn = 1
LEFT JOIN ADI_Info adi ON icd.PatientKey = adi.PatientKey
LEFT JOIN EFI_Score efi ON p.DurableKey = efi.PatientDurableKey
LEFT JOIN Medications meds ON icd.PatientKey = meds.PatientKey
LEFT JOIN ProcedureFinal proc ON icd.PatientKey = proc.PatientKey
WHERE p.AgeInYears IS NOT NULL
