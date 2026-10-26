-- Runs a validated import: creates a client or contact for every row without errors, records CreatedEntityId, and marks
-- the job IMPORTED with ImportedCount. Rows with errors are skipped (the UI says how many). Blank client codes get the
-- next CLIENT_CODE number (C00001...). New clients get their default billing profile from the usual trigger.
-- If anything fails (e.g. a client code taken since validation) nothing is imported, the job is FAILED and the error is
-- raised; re-stage and validate again. Needs client.edit. Audited under area 'import'.
CREATE PROCEDURE admin.usp_Import_Commit
    @JobId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Kind VARCHAR(10), @Status VARCHAR(10), @Need INT, @First INT, @Done INT,
            @AuditKey NVARCHAR(100) = CONVERT(NVARCHAR(100), @JobId), @AuditSummary NVARCHAR(400);
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51731, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'client.edit'))
        THROW 51732, N'You need permission to edit clients to import them.', 1;
    SELECT @Kind = Kind, @Status = Status FROM admin.ImportJob WHERE TenantId = @TenantId AND Id = @JobId;
    IF @Kind IS NULL THROW 51734, N'Import not found.', 1;
    IF @Status <> 'VALIDATED' THROW 51735, N'Validate the import before running it.', 1;

    DECLARE @Map TABLE (RowId INT PRIMARY KEY, EntityId INT NOT NULL);

    BEGIN TRY
        BEGIN TRAN;

        IF @Kind = 'CLIENTS'
        BEGIN
            CREATE TABLE #c (RowId INT PRIMARY KEY, Seq INT NULL, ClientCode NVARCHAR(20) NULL, Name NVARCHAR(200),
                             FirstName NVARCHAR(100), LastName NVARCHAR(100), TypeTxt NVARCHAR(400), StatusTxt NVARCHAR(400),
                             IndustryTxt NVARCHAR(400), TaxId NVARCHAR(30), Website NVARCHAR(300), Notes NVARCHAR(MAX));
            INSERT INTO #c (RowId, ClientCode, Name, FirstName, LastName, TypeTxt, StatusTxt, IndustryTxt, TaxId, Website, Notes)
            SELECT r.Id, NULLIF(LTRIM(RTRIM(j.clientCode)), N''), LTRIM(RTRIM(j.name)), NULLIF(LTRIM(RTRIM(j.firstName)), N''),
                   NULLIF(LTRIM(RTRIM(j.lastName)), N''), NULLIF(LTRIM(RTRIM(j.clientType)), N''), NULLIF(LTRIM(RTRIM(j.status)), N''),
                   NULLIF(LTRIM(RTRIM(j.industry)), N''), NULLIF(LTRIM(RTRIM(j.taxId)), N''), NULLIF(LTRIM(RTRIM(j.website)), N''),
                   NULLIF(j.notes, N'')
            FROM admin.ImportRow AS r
            CROSS APPLY OPENJSON(r.RawJson) WITH (clientCode NVARCHAR(20), name NVARCHAR(200), firstName NVARCHAR(100),
                lastName NVARCHAR(100), clientType NVARCHAR(400), status NVARCHAR(400), industry NVARCHAR(400),
                taxId NVARCHAR(30), website NVARCHAR(300), notes NVARCHAR(MAX)) AS j
            WHERE r.TenantId = @TenantId AND r.JobId = @JobId AND r.ErrorText IS NULL;

            -- blank codes take the next CLIENT_CODE numbers
            SELECT @Need = COUNT(*) FROM #c WHERE ClientCode IS NULL;
            IF @Need > 0
            BEGIN
                EXEC admin.usp_NextNumber @TenantId = @TenantId, @SequenceKey = 'CLIENT_CODE', @Count = @Need, @FirstValue = @First OUTPUT;
                WITH n AS (SELECT ClientCode, ROW_NUMBER() OVER (ORDER BY RowId) AS rn FROM #c WHERE ClientCode IS NULL)
                UPDATE n SET ClientCode = CONCAT(N'C', RIGHT(CONCAT(N'00000', @First + rn - 1), IIF(@First + rn - 1 > 99999, 10, 5)));
            END;

            MERGE crm.Client AS t
            USING (
                SELECT c.RowId, c.ClientCode, c.Name, c.FirstName, c.LastName, c.TaxId, c.Website, c.Notes,
                       COALESCE(ty.Id, dty.Id) AS ClientTypeId, COALESCE(st.Id, dst.Id) AS ClientStatusId, ind.Id AS IndustryId
                FROM #c AS c
                OUTER APPLY (SELECT TOP (1) Id FROM lkp.ClientType WHERE TenantId = @TenantId AND IsActive = 1
                             AND (Code = c.TypeTxt COLLATE DATABASE_DEFAULT OR Name = c.TypeTxt COLLATE DATABASE_DEFAULT)
                             ORDER BY IIF(Code = c.TypeTxt COLLATE DATABASE_DEFAULT, 0, 1)) AS ty
                OUTER APPLY (SELECT TOP (1) Id FROM lkp.ClientType WHERE TenantId = @TenantId AND IsActive = 1
                             ORDER BY IsDefault DESC, IIF(SystemCode = 'BUSINESS', 0, 1), SortOrder) AS dty
                OUTER APPLY (SELECT TOP (1) Id FROM lkp.ClientStatus WHERE TenantId = @TenantId AND IsActive = 1
                             AND (Code = c.StatusTxt COLLATE DATABASE_DEFAULT OR Name = c.StatusTxt COLLATE DATABASE_DEFAULT)
                             ORDER BY IIF(Code = c.StatusTxt COLLATE DATABASE_DEFAULT, 0, 1)) AS st
                OUTER APPLY (SELECT TOP (1) Id FROM lkp.ClientStatus WHERE TenantId = @TenantId AND IsActive = 1
                             ORDER BY IsDefault DESC, IIF(SystemCode = 'ACTIVE', 0, 1), SortOrder) AS dst
                OUTER APPLY (SELECT TOP (1) Id FROM lkp.Industry WHERE TenantId = @TenantId AND IsActive = 1
                             AND (Code = c.IndustryTxt COLLATE DATABASE_DEFAULT OR Name = c.IndustryTxt COLLATE DATABASE_DEFAULT)
                             ORDER BY IIF(Code = c.IndustryTxt COLLATE DATABASE_DEFAULT, 0, 1)) AS ind
            ) AS s ON 1 = 0
            WHEN NOT MATCHED THEN
                INSERT (TenantId, ClientCode, Name, FirstName, LastName, ClientTypeId, ClientStatusId, IndustryId, TaxId, Website, Notes)
                VALUES (@TenantId, s.ClientCode, s.Name, s.FirstName, s.LastName, s.ClientTypeId, s.ClientStatusId, s.IndustryId,
                        s.TaxId, s.Website, s.Notes)
            OUTPUT s.RowId, inserted.Id INTO @Map (RowId, EntityId);
        END
        ELSE
            MERGE crm.Contact AS t
            USING (
                SELECT r.Id AS RowId, c.Id AS ClientId, LTRIM(RTRIM(j.firstName)) AS FirstName, NULLIF(LTRIM(RTRIM(j.lastName)), N'') AS LastName,
                       NULLIF(LTRIM(RTRIM(j.title)), N'') AS Title, NULLIF(LTRIM(RTRIM(j.email)), N'') AS Email,
                       NULLIF(LTRIM(RTRIM(j.phone)), N'') AS Phone, NULLIF(LTRIM(RTRIM(j.mobile)), N'') AS Mobile, ro.Id AS ContactRoleId,
                       CONVERT(BIT, IIF(LOWER(LTRIM(RTRIM(j.isPrimary))) = N'true' OR LOWER(LTRIM(RTRIM(j.isPrimary))) = N'1' OR LOWER(LTRIM(RTRIM(j.isPrimary))) = N'yes', 1, 0)) AS IsPrimary
                FROM admin.ImportRow AS r
                CROSS APPLY OPENJSON(r.RawJson) WITH (clientCode NVARCHAR(20), firstName NVARCHAR(100), lastName NVARCHAR(100),
                    title NVARCHAR(100), email NVARCHAR(254), phone NVARCHAR(30), mobile NVARCHAR(30), role NVARCHAR(400),
                    isPrimary NVARCHAR(10)) AS j
                JOIN crm.Client AS c ON c.TenantId = r.TenantId AND c.DeletedAt IS NULL
                                    AND c.ClientCode = LTRIM(RTRIM(j.clientCode)) COLLATE DATABASE_DEFAULT
                OUTER APPLY (SELECT TOP (1) Id FROM lkp.ContactRole WHERE TenantId = @TenantId AND IsActive = 1
                             AND (Code = j.role COLLATE DATABASE_DEFAULT OR Name = j.role COLLATE DATABASE_DEFAULT)) AS ro
                WHERE r.TenantId = @TenantId AND r.JobId = @JobId AND r.ErrorText IS NULL
            ) AS s ON 1 = 0
            WHEN NOT MATCHED THEN
                INSERT (TenantId, ClientId, FirstName, LastName, Title, Email, Phone, Mobile, ContactRoleId, IsPrimary)
                VALUES (@TenantId, s.ClientId, s.FirstName, s.LastName, s.Title, s.Email, s.Phone, s.Mobile, s.ContactRoleId, s.IsPrimary)
            OUTPUT s.RowId, inserted.Id INTO @Map (RowId, EntityId);

        UPDATE r SET CreatedEntityId = m.EntityId FROM admin.ImportRow AS r JOIN @Map AS m ON m.RowId = r.Id;
        SET @Done = (SELECT COUNT(*) FROM @Map);
        UPDATE admin.ImportJob SET Status = 'IMPORTED', ImportedAt = SYSUTCDATETIME(), ImportedCount = @Done
        WHERE TenantId = @TenantId AND Id = @JobId;

        SET @AuditSummary = CONCAT(N'Imported ', @Done, IIF(@Kind = 'CLIENTS', N' clients', N' contacts'), N' from a CSV file');
        EXEC admin.usp_Audit_Write @Area = 'import', @EntityType = 'IMPORT', @EntityKey = @AuditKey, @Action = 'CREATE',
             @Summary = @AuditSummary;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK;
        UPDATE admin.ImportJob SET Status = 'FAILED' WHERE TenantId = @TenantId AND Id = @JobId;
        THROW;
    END CATCH;

    SELECT r.RowNumber, r.CreatedEntityId, r.ErrorText FROM admin.ImportRow AS r
    WHERE r.TenantId = @TenantId AND r.JobId = @JobId ORDER BY r.RowNumber;
END;
