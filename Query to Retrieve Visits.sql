SELECT ef.PatientKey, ef.DateKey, ef.PrimaryDiagnosisKey, ef.EncounterKey,
       vt.VisitType, ef.EndDateKey
FROM CDW.FilteredAccess.EncounterFact ef
JOIN CDW.FilteredAccess.VisitTypeDim vt
    ON ef.VisitTypeKey = vt.VisitTypeKey
WHERE ef.PatientKey IN (SELECT PatientKey FROM EligiblePatients)
    AND ef.DateKey BETWEEN 20230301 AND 20240229;
