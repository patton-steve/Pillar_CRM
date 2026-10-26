-- Saves (or with @Delete = 1 removes) one of your parameter sets for a canned report. Saving under an existing name
-- for the same report overwrites it. Canned reports are in every plan, so no feature check. Errors 51620-51621.
CREATE PROCEDURE admin.usp_ReportParameterSet_Save
    @ParameterSetId INT = NULL OUTPUT,
    @ReportCode     VARCHAR(40) = NULL,
    @Name           NVARCHAR(100) = NULL,
    @ParameterJson  NVARCHAR(MAX) = NULL,
    @Delete         BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51620, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;

    IF @Delete = 1
    BEGIN
        DELETE FROM admin.ReportParameterSet WHERE TenantId = @TenantId AND AppUserId = @UserId AND Id = @ParameterSetId;
        IF @@ROWCOUNT = 0 THROW 51621, N'Saved parameters not found.', 1;
        RETURN;
    END;

    IF NULLIF(LTRIM(@Name), N'') IS NULL OR NULLIF(LTRIM(@ReportCode), '') IS NULL OR ISJSON(@ParameterJson) <> 1
        THROW 51621, N'Saved parameters need a report, a name and the parameter values as JSON.', 1;

    BEGIN TRAN;
    IF @ParameterSetId IS NULL
        SELECT @ParameterSetId = Id FROM admin.ReportParameterSet WITH (UPDLOCK, HOLDLOCK)
        WHERE TenantId = @TenantId AND AppUserId = @UserId AND ReportCode = @ReportCode AND Name = @Name;

    IF @ParameterSetId IS NULL
    BEGIN
        INSERT INTO admin.ReportParameterSet (TenantId, AppUserId, ReportCode, Name, ParameterJson)
        VALUES (@TenantId, @UserId, @ReportCode, @Name, @ParameterJson);
        SET @ParameterSetId = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE admin.ReportParameterSet SET Name = @Name, ParameterJson = @ParameterJson, ModifiedAt = SYSUTCDATETIME()
        WHERE TenantId = @TenantId AND AppUserId = @UserId AND Id = @ParameterSetId;
        IF @@ROWCOUNT = 0 THROW 51621, N'Saved parameters not found.', 1;
    END;
    COMMIT;
END;
