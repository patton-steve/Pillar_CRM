-- Removes a saved Pilo report: your own, or a company report if you have report.share.
CREATE PROCEDURE admin.usp_SavedReport_Delete
    @SavedReportId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Now DATETIME2(0) = SYSUTCDATETIME(), @CanShare BIT = 0;
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51613, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'report.share')) SET @CanShare = 1;

    UPDATE admin.SavedReport SET DeletedAt = @Now, ModifiedAt = @Now, ModifiedBy = @UserId
    WHERE TenantId = @TenantId AND Id = @SavedReportId AND DeletedAt IS NULL
      AND (OwnerUserId = @UserId OR (IsShared = 1 AND @CanShare = 1));
    IF @@ROWCOUNT = 0 THROW 51619, N'The report was not found, or is not yours to remove.', 1;
END;
