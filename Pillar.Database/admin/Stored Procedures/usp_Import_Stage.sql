-- Stages a mapped CSV for import: @Rows is a JSON array of objects (see admin.ImportRow for the field names), in file
-- order; RowNumber counts from 2 (line 1 is the header). Needs client.edit. Up to 5,000 rows. Errors 51731-51735.
CREATE PROCEDURE admin.usp_Import_Stage
    @Kind       VARCHAR(10),
    @Rows       NVARCHAR(MAX),
    @FileName   NVARCHAR(260) = NULL,
    @JobId      INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')), @Count INT;
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51731, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'client.edit'))
        THROW 51732, N'You need permission to edit clients to import them.', 1;
    IF @Kind IS NULL OR NOT (@Kind = 'CLIENTS' OR @Kind = 'CONTACTS') THROW 51733, N'Import CLIENTS or CONTACTS.', 1;
    IF ISJSON(@Rows) = 0 OR LEFT(LTRIM(@Rows), 1) <> N'[' THROW 51733, N'Rows must be a JSON array of objects.', 1;
    SELECT @Count = COUNT(*) FROM OPENJSON(@Rows);
    IF @Count = 0 OR @Count > 5000 THROW 51733, N'Import between 1 and 5,000 rows at a time.', 1;
    IF EXISTS (SELECT 1 FROM OPENJSON(@Rows) WHERE [type] <> 5) THROW 51733, N'Each row must be a JSON object.', 1;

    BEGIN TRAN;
    INSERT INTO admin.ImportJob (TenantId, Kind, FileName, TotalRows) VALUES (@TenantId, @Kind, @FileName, @Count);
    SET @JobId = SCOPE_IDENTITY();
    INSERT INTO admin.ImportRow (TenantId, JobId, RowNumber, RawJson)
    SELECT @TenantId, @JobId, CONVERT(INT, [key]) + 2, value FROM OPENJSON(@Rows);
    COMMIT;
END;
