-- Saves the tenant's setup check levels (needs settings.projects). @Levels is a JSON object of check code -> level, e.g.
-- {"PROJECT_MANAGER": "BLOCK", "PO_NUMBER": "WARN", "BUDGET": "OFF"}. Checks not sent are left as they are; a level equal
-- to the default removes the tenant's row so later default changes reach it.
CREATE PROCEDURE admin.usp_ProjectSetupCheck_Set
    @Levels     NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51403, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'settings.projects'))
        THROW 51404, N'You need permission to change settings to change project setup checks.', 1;
    IF ISJSON(@Levels) = 0 OR LEFT(LTRIM(@Levels), 1) <> N'{'
        THROW 51405, N'Setup check levels must be a JSON object of check code to OFF, WARN or BLOCK.', 1;

    CREATE TABLE #l (Code VARCHAR(30) NULL, DefaultLevel VARCHAR(5) NULL, Level VARCHAR(5) NULL);
    INSERT INTO #l (Code, DefaultLevel, Level)
    SELECT c.Code, c.DefaultLevel, UPPER(CONVERT(VARCHAR(5), j.value))
    FROM OPENJSON(@Levels) AS j
    LEFT JOIN admin.ProjectSetupCheck AS c ON c.Code = j.[key] COLLATE DATABASE_DEFAULT;

    IF EXISTS (SELECT 1 FROM #l WHERE Code IS NULL OR Level IS NULL OR NOT (Level = 'OFF' OR Level = 'WARN' OR Level = 'BLOCK'))
        THROW 51406, N'Each setup check needs a known code and OFF, WARN or BLOCK.', 1;

    BEGIN TRAN;

    DELETE t FROM admin.TenantProjectSetupCheck AS t
    JOIN #l AS l ON l.Code = t.CheckCode AND l.Level = l.DefaultLevel
    WHERE t.TenantId = @TenantId;

    MERGE admin.TenantProjectSetupCheck AS t
    USING (SELECT Code, Level FROM #l WHERE Level <> DefaultLevel) AS s
        ON t.TenantId = @TenantId AND t.CheckCode = s.Code
    WHEN MATCHED THEN UPDATE SET Level = s.Level, ModifiedAt = SYSUTCDATETIME(), ModifiedBy = @UserId
    WHEN NOT MATCHED THEN INSERT (TenantId, CheckCode, Level) VALUES (@TenantId, s.Code, s.Level);

    EXEC admin.usp_Audit_Write @Area = 'projects', @EntityType = 'SETUP_CHECK', @Action = 'UPDATE',
         @Summary = N'Changed project setup check levels', @ChangeJson = @Levels;

    COMMIT;
END;
