SELECT CAST( Vitals.NUMERICBASEID AS numeric(18,0) ) NUMERICBASEID, 
       Vitals.CONTACTDATEREAL,
       CAST( Vitals.LINE AS int ) LINE,
       Vitals.TYPEABBREVIATION TYPEABBREVIATION,
       DOCS_RCVD.PAT_ID PATIENTID,
       Vitals.TAKENDATE,
       DOC_SOURCE.SOURCEID SOURCEID,
       DOC_SOURCE.SOURCEIDTYPE SOURCEIDTYPE,
       CASE WHEN Vitals.TYPEABBREVIATION IS NOT NULL THEN 'EpicFlowsheetRowId' ELSE 'NotApplicable' END FLOWSHEETROWIDTYPE,
       CASE WHEN Vitals.TYPEABBREVIATION = 'BMI' THEN '1570001000'
            WHEN Vitals.TYPEABBREVIATION = 'BP' THEN '5'
            WHEN Vitals.TYPEABBREVIATION = 'HEIGHT' THEN '11'
            WHEN Vitals.TYPEABBREVIATION = 'WEIGHT' THEN '14'
            WHEN Vitals.TYPEABBREVIATION = 'CIRCUMF' THEN '16'
            WHEN Vitals.TYPEABBREVIATION = 'PULSE' THEN '8'
            WHEN Vitals.TYPEABBREVIATION = 'TEMP' THEN '6'
            WHEN Vitals.TYPEABBREVIATION = 'RESP' THEN '9'
            WHEN Vitals.TYPEABBREVIATION = 'SPO2' THEN '10'
            ELSE NULL END FLOWSHEETROWID,
       Vitals.VALUE VALUE,
       CASE WHEN Vitals.TYPEABBREVIATION = 'BP' THEN NULL
            ELSE CAST( Vitals.VALUE as numeric(18,2) ) END NUMERICVALUE,
       CASE WHEN Vitals.TYPEABBREVIATION = 'BP'
         AND Vitals.VALUE = '*Unspecified' THEN 'Incomplete' ELSE '' END "COMMENT"
  FROM ( SELECT DOCS_RCVD_VTLS.DOCUMENT_ID NUMERICBASEID,
                CAST( CAST( DOCS_RCVD_VTLS.CONTACT_DATE_REAL AS numeric(7,2) ) AS varchar(9) ) CONTACTDATEREAL,
                DOCS_RCVD_VTLS.LINE LINE,
                DOCS_RCVD_VTLS.VTL_REF_ID REFID,
                DOCS_RCVD_VTLS.VTL_DATETIME TAKENDATE,
                CAST( CAST( DOCS_RCVD_VTLS.VTL_BMI AS numeric(18,2) ) AS varchar(50) ) BMI,
                CAST( TRY_CAST( DOCS_RCVD_VTLS.VTL_HEIGHT / 2.54 AS numeric(18,2) ) AS varchar(50) ) HEIGHT, 
                CAST( TRY_CAST( DOCS_RCVD_VTLS.VTL_WEIGHT / 0.02834952 AS numeric(18,2) ) AS varchar(50) ) WEIGHT,
                CAST( TRY_CAST( DOCS_RCVD_VTLS.VTL_CIRCUM / 2.54 AS numeric(18,2) ) AS varchar(50) ) CIRCUMF,
                CAST( CAST( DOCS_RCVD_VTLS.VTL_PULSE AS numeric(18,2) ) AS varchar(50) ) PULSE,
                CASE WHEN DOCS_RCVD_VTLS.VTL_SYSTOLIC_BP IS NOT NULL AND DOCS_RCVD_VTLS.VTL_DIASTOLIC_BP IS NOT NULL
                       THEN CAST( CONCAT( CONCAT( CAST( DOCS_RCVD_VTLS.VTL_SYSTOLIC_BP AS varchar(50) ), '/' ),
                                                  CAST( DOCS_RCVD_VTLS.VTL_DIASTOLIC_BP AS varchar(50) ) ) AS varchar(50) )
                     WHEN NOT ( DOCS_RCVD_VTLS.VTL_SYSTOLIC_BP IS NULL AND DOCS_RCVD_VTLS.VTL_DIASTOLIC_BP IS NULL )
                       THEN '*Unspecified'
                     ELSE NULL END BP,
                CAST( TRY_CAST( DOCS_RCVD_VTLS.VTL_TEMP * (9.00/5.00) + 32 AS numeric(18,2) ) AS varchar(50) ) TEMP,
                CAST( CAST( DOCS_RCVD_VTLS.VTL_RESP AS numeric(18,2) ) AS varchar(50) ) RESP,
                CAST( CAST( DOCS_RCVD_VTLS.VTL_SPO2 AS numeric(18,2) ) AS varchar(50) ) SPO2
           FROM DOCS_RCVD_VTLS
           WHERE DOCS_RCVD_VTLS.DOCUMENT_ID > <<LowerBound>> 
             AND DOCS_RCVD_VTLS.DOCUMENT_ID <= <<UpperBound>> ) VitalsPivot
           UNPIVOT ( Value FOR TypeAbbreviation IN ( BMI,
                                                     HEIGHT, 
                                                     WEIGHT, 
                                                     CIRCUMF,
                                                     PULSE,
                                                     BP,
                                                     TEMP,
                                                     RESP,
                                                     SPO2 ) ) Vitals
    INNER JOIN DOCS_RCVD                           
      ON DOCS_RCVD.DOCUMENT_ID = Vitals.NUMERICBASEID 
    INNER JOIN ( SELECT DOCS_RCVD_DEDUP_LNK.LOG_LNK_DDUP_REFIDS, 
                        CASE WHEN MIN( CASE WHEN DOCS_RCVD_DEDUP_LNK.LOG_LNK_SRC_TYPE_C = 400 THEN 1
                                            ELSE 0 END ) = 1 THEN '1|3'
                             WHEN MIN( DOCS_RCVD_DEDUP_LNK.LOG_LNK_SRC_TYPE_C ) IS NULL THEN NULL
                             WHEN MIN( DOCS_RCVD_DEDUP_LNK.LOG_LNK_SRC_ORG_ID ) <> MAX( DOCS_RCVD_DEDUP_LNK.LOG_LNK_SRC_ORG_ID ) THEN '1|2|multiple'
                             WHEN MIN( DOCS_RCVD_DEDUP_LNK.LOG_LNK_SRC_ORG_ID ) = MAX( DOCS_RCVD_DEDUP_LNK.LOG_LNK_SRC_ORG_ID )
                               THEN CONCAT( '1|2|', CAST( MIN( DOCS_RCVD_DEDUP_LNK.LOG_LNK_SRC_ORG_ID ) AS varchar(20) ) )
                             ELSE '1|2' END SOURCEID,
                        CASE WHEN MIN( CASE WHEN DOCS_RCVD_DEDUP_LNK.LOG_LNK_SRC_TYPE_C = 400 THEN 1
                                            ELSE 0 END ) = 1 THEN 1
                             WHEN MIN( DOCS_RCVD_DEDUP_LNK.LOG_LNK_SRC_TYPE_C ) IS NULL THEN NULL
                             WHEN MAX( DOCS_RCVD_DEDUP_LNK.LOG_LNK_SRC_ORG_ID ) IS NOT NULL THEN 0
                             ELSE 1 END SOURCEIDTYPE
                   FROM DOCS_RCVD_DEDUP_LNK
                   WHERE DOCS_RCVD_DEDUP_LNK.LOG_LNK_DDUP_REFIDS IS NOT NULL
                     AND DOCS_RCVD_DEDUP_LNK.LOG_LNK_DATA_TYPE_C IN ( 7 )
                     AND DOCS_RCVD_DEDUP_LNK.DOCUMENT_ID > <<LowerBound>>
                     AND DOCS_RCVD_DEDUP_LNK.DOCUMENT_ID <= <<UpperBound>>
                   GROUP BY DOCS_RCVD_DEDUP_LNK.LOG_LNK_DDUP_REFIDS ) DOC_SOURCE
       ON Vitals.REFID = DOC_SOURCE.LOG_LNK_DDUP_REFIDS
         AND DOC_SOURCE.SOURCEID IS NOT NULL
  WHERE DOCS_RCVD.TYPE_C = 51
    AND DOCS_RCVD.RECORD_STATE_C IS NULL 