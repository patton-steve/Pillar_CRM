-- Records a run of a saved Pilo report (your own or a company one). Re-running uses the saved SqlText (or Definition), so it
-- does not count against Pilo usage; only asking Pilo for a new report does.
-- Handoff 24: needs pilo.ask (52405) and logs the run in admin.SavedReportRun with the parameters used, row count, time
-- taken and, for a failed run, the error. LastRunAt and RunCount count every run; a successful run with @ParameterJson
-- also keeps those values on the report for next time.
CREATE PROCEDURE admin.usp_SavedReport_MarkRun
    @SavedReportId  INT,
    @ParameterJson  NVARCHAR(MAX) = NULL,
    @RowCount       INT = NULL,
    @DurationMs     INT = NULL,
    @Succeeded      BIT = 1,
    @ErrorText      NVARCHAR(1000) = NULL,
    @RunId          BIGINT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')), @Now DATETIME2(0) = SYSUTCDATETIME();
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51613, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'pilo.ask'))
        THROW 52405, N'You need permission to ask Pilo to run reports.', 1;
    IF @ParameterJson IS NOT NULL AND ISJSON(@ParameterJson) <> 1 THROW 51617, N'Parameters must be JSON.', 1;

    BEGIN TRAN;

    UPDATE admin.SavedReport
    SET LastRunAt = @Now, RunCount = RunCount + 1,
        ParameterJson = CASE WHEN @Succeeded = 1 AND @ParameterJson IS NOT NULL THEN @ParameterJson ELSE ParameterJson END
    WHERE TenantId = @TenantId AND Id = @SavedReportId AND DeletedAt IS NULL AND (IsShared = 1 OR OwnerUserId = @UserId);
    IF @@ROWCOUNT = 0 THROW 51617, N'Saved report not found.', 1;

    INSERT INTO admin.SavedReportRun (TenantId, SavedReportId, RunBy, RunAt, ParameterJson, [RowCount], DurationMs, Succeeded, ErrorText)
    VALUES (@TenantId, @SavedReportId, @UserId, @Now, @ParameterJson, @RowCount, @DurationMs, ISNULL(@Succeeded, 1),
            IIF(ISNULL(@Succeeded, 1) = 1, NULL, @ErrorText));
    SET @RunId = SCOPE_IDENTITY();

    COMMIT;
END;
