#constructing the cohort query for “≥55 years old with 2+ billing codes J41–J44
-- Step 1: Get DiagnosisKeys for COPD-related ICD-10-CM codes (J41–J44)
SELECT DISTINCT dt.DiagnosisKey
INTO #COPD_Diagnoses
FROM FilteredAccess.DiagnosisTerminologyDim dt
WHERE dt.Type = 'ICD-10-CM'
  AND dt.Value LIKE 'J41%' OR dt.Value LIKE 'J42%' OR dt.Value LIKE 'J43%' OR dt.Value LIKE 'J44%';

-- Step 2: Pull qualifying patient records
SELECT baf.PatientKey
INTO #EligiblePatients
FROM FilteredAccess.BillingAccountFact baf
JOIN CDW.FilteredAccess.DiagnosisBridge db ON baf.DiagnosisComboKey = db.DiagnosisComboKey
WHERE db.DiagnosisKey IN (SELECT DiagnosisKey FROM #COPD_Diagnoses)
  AND baf.AccountCreateDateKey BETWEEN 20050328 AND 20120228
GROUP BY baf.PatientKey
HAVING COUNT(DISTINCT baf.AccountCreateDateKey) >= 2;

-- Step 3: Join to PatientDim for demographics
SELECT
  p.DurableKey,
  p.PatientKey,
  p.AgeInYears,
  p.Sex,
  p.FirstRace,
  p.SecondRace,
  p.ThirdRace,
  p.FourthRace,
  p.FifthRace,
  p.MultiRacial,
  p.BirthDate
FROM FilteredAccess.PatientDim p
WHERE p.PatientKey IN (SELECT PatientKey FROM #EligiblePatients)
  AND p.AgeInYears >= 55;
