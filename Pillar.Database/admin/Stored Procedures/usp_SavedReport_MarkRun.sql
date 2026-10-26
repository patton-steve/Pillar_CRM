-- Records a run of a saved Pilo report (your own or a company one). Re-running uses the saved Definition, so it does
-- not count against Pilo usage; only asking Pilo for a new report does.
CREATE PROCEDURE admin.usp_SavedReport_MarkRun
    @SavedReportId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51613, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;

    UPDATE admin.SavedReport SET LastRunAt = SYSUTCDATETIME(), RunCount = RunCount + 1
    WHERE TenantId = @TenantId AND Id = @SavedReportId AND DeletedAt IS NULL AND (IsShared = 1 OR OwnerUserId = @UserId);
    IF @@ROWCOUNT = 0 THROW 51617, N'Saved report not found.', 1;
END;
