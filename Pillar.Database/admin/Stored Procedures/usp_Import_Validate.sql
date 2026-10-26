-- Dry run of a staged import: marks every row's problems in ImportRow.ErrorText and sets the job VALIDATED with its
-- ErrorCount. Returns the rows with errors (RowNumber, ErrorText) for the review screen. Needs client.edit.
-- Clients: name required; clientCode (optional, generated if blank) unique in Pillar and in the file, 20 characters max;
-- clientType/status/industry must match the tenant's lists when given. Contacts: clientCode must match a client;
-- firstName required; email must look like one; at most one isPrimary per client, and none if the client already has one.
CREATE PROCEDURE admin.usp_Import_Validate
    @JobId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')), @Kind VARCHAR(10), @Status VARCHAR(10);
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51731, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'client.edit'))
        THROW 51732, N'You need permission to edit clients to import them.', 1;
    SELECT @Kind = Kind, @Status = Status FROM admin.ImportJob WHERE TenantId = @TenantId AND Id = @JobId;
    IF @Kind IS NULL THROW 51734, N'Import not found.', 1;
    IF @Status = 'IMPORTED' THROW 51734, N'This import has already run.', 1;

    CREATE TABLE #r (Id INT PRIMARY KEY, Code NVARCHAR(400), Name NVARCHAR(400), TypeTxt NVARCHAR(400), StatusTxt NVARCHAR(400),
                     IndustryTxt NVARCHAR(400), FirstName NVARCHAR(400), Email NVARCHAR(400), RoleTxt NVARCHAR(400),
                     IsPrimary NVARCHAR(10), Err NVARCHAR(1000) NOT NULL DEFAULT (N''));
    INSERT INTO #r (Id, Code, Name, TypeTxt, StatusTxt, IndustryTxt, FirstName, Email, RoleTxt, IsPrimary)
    SELECT r.Id, NULLIF(LTRIM(RTRIM(j.clientCode)), N''), NULLIF(LTRIM(RTRIM(j.name)), N''), NULLIF(LTRIM(RTRIM(j.clientType)), N''),
           NULLIF(LTRIM(RTRIM(j.status)), N''), NULLIF(LTRIM(RTRIM(j.industry)), N''), NULLIF(LTRIM(RTRIM(j.firstName)), N''),
           NULLIF(LTRIM(RTRIM(j.email)), N''), NULLIF(LTRIM(RTRIM(j.role)), N''), LOWER(LTRIM(RTRIM(j.isPrimary)))
    FROM admin.ImportRow AS r
    CROSS APPLY OPENJSON(r.RawJson) WITH (clientCode NVARCHAR(400), name NVARCHAR(400), clientType NVARCHAR(400),
        status NVARCHAR(400), industry NVARCHAR(400), firstName NVARCHAR(400), email NVARCHAR(400), role NVARCHAR(400),
        isPrimary NVARCHAR(10)) AS j
    WHERE r.TenantId = @TenantId AND r.JobId = @JobId;

    IF @Kind = 'CLIENTS'
    BEGIN
        UPDATE #r SET Err += N'Name is required; ' WHERE Name IS NULL;
        UPDATE #r SET Err += N'Name is longer than 200 characters; ' WHERE LEN(Name) > 200;
        UPDATE #r SET Err += N'Client code is longer than 20 characters; ' WHERE LEN(Code) > 20;
        UPDATE x SET Err += N'Client code already exists; ' FROM #r AS x
        WHERE EXISTS (SELECT 1 FROM crm.Client AS c WHERE c.TenantId = @TenantId AND c.ClientCode = x.Code COLLATE DATABASE_DEFAULT);
        UPDATE x SET Err += N'Client code appears more than once in the file; ' FROM #r AS x
        WHERE x.Code IS NOT NULL AND (SELECT COUNT(*) FROM #r AS y WHERE y.Code = x.Code) > 1;
        UPDATE x SET Err += N'Unknown client type; ' FROM #r AS x WHERE x.TypeTxt IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM lkp.ClientType AS l WHERE l.TenantId = @TenantId AND l.IsActive = 1
                          AND (l.Code = x.TypeTxt COLLATE DATABASE_DEFAULT OR l.Name = x.TypeTxt COLLATE DATABASE_DEFAULT));
        UPDATE x SET Err += N'Unknown status; ' FROM #r AS x WHERE x.StatusTxt IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM lkp.ClientStatus AS l WHERE l.TenantId = @TenantId AND l.IsActive = 1
                          AND (l.Code = x.StatusTxt COLLATE DATABASE_DEFAULT OR l.Name = x.StatusTxt COLLATE DATABASE_DEFAULT));
        UPDATE x SET Err += N'Unknown industry; ' FROM #r AS x WHERE x.IndustryTxt IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM lkp.Industry AS l WHERE l.TenantId = @TenantId AND l.IsActive = 1
                          AND (l.Code = x.IndustryTxt COLLATE DATABASE_DEFAULT OR l.Name = x.IndustryTxt COLLATE DATABASE_DEFAULT));
    END
    ELSE
    BEGIN
        UPDATE #r SET Err += N'First name is required; ' WHERE FirstName IS NULL;
        UPDATE x SET Err += N'Client code doesn''t match a client; ' FROM #r AS x
        WHERE NOT EXISTS (SELECT 1 FROM crm.Client AS c
                          WHERE c.TenantId = @TenantId AND c.DeletedAt IS NULL AND c.ClientCode = x.Code COLLATE DATABASE_DEFAULT);
        UPDATE #r SET Err += N'Email doesn''t look valid; ' WHERE Email IS NOT NULL AND Email NOT LIKE N'_%@_%._%';
        UPDATE x SET Err += N'Unknown contact role; ' FROM #r AS x WHERE x.RoleTxt IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM lkp.ContactRole AS l WHERE l.TenantId = @TenantId AND l.IsActive = 1
                          AND (l.Code = x.RoleTxt COLLATE DATABASE_DEFAULT OR l.Name = x.RoleTxt COLLATE DATABASE_DEFAULT));
        UPDATE x SET Err += N'Only one primary contact per client; ' FROM #r AS x
        WHERE (x.IsPrimary = N'true' OR x.IsPrimary = N'1' OR x.IsPrimary = N'yes')
          AND ((SELECT COUNT(*) FROM #r AS y WHERE y.Code = x.Code AND (y.IsPrimary = N'true' OR y.IsPrimary = N'1' OR y.IsPrimary = N'yes')) > 1
               OR EXISTS (SELECT 1 FROM crm.Contact AS k JOIN crm.Client AS c ON c.TenantId = k.TenantId AND c.Id = k.ClientId
                          WHERE k.TenantId = @TenantId AND k.IsPrimary = 1 AND k.DeletedAt IS NULL
                            AND c.ClientCode = x.Code COLLATE DATABASE_DEFAULT));
    END;

    BEGIN TRAN;
    UPDATE r SET ErrorText = CASE WHEN x.Err = N'' THEN NULL ELSE LEFT(x.Err, LEN(x.Err) - 1) END
    FROM admin.ImportRow AS r JOIN #r AS x ON x.Id = r.Id;
    UPDATE admin.ImportJob
    SET Status = 'VALIDATED', ValidatedAt = SYSUTCDATETIME(),
        ErrorCount = (SELECT COUNT(*) FROM #r WHERE Err <> N'')
    WHERE TenantId = @TenantId AND Id = @JobId;
    COMMIT;

    SELECT RowNumber, ErrorText FROM admin.ImportRow
    WHERE TenantId = @TenantId AND JobId = @JobId AND ErrorText IS NOT NULL ORDER BY RowNumber;
END;
