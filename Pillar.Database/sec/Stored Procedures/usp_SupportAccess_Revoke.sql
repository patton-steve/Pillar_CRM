-- Settings > Security: ends Pillar support's access now. Any support sign-in still open is ended too (EndReason REVOKED; the
-- API checks sec.usp_Impersonation_Check on each request). Needs settings.security. Audited.
CREATE PROCEDURE sec.usp_SupportAccess_Revoke
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')), @UserId INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Now DATETIME2(0) = SYSUTCDATETIME();
    IF @TenantId IS NULL OR @UserId IS NULL THROW 52216, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'settings.security'))
        THROW 52250, N'You don''t have permission to change support access.', 1;

    BEGIN TRAN;
    UPDATE sec.SupportAccessGrant SET RevokedAt = @Now, RevokedBy = @UserId
    WHERE TenantId = @TenantId AND RevokedAt IS NULL AND ExpiresAt > @Now;
    UPDATE sec.ImpersonationSession SET EndedAt = @Now, EndReason = 'REVOKED' WHERE TenantId = @TenantId AND EndedAt IS NULL;
    EXEC admin.usp_Audit_Write @Area = 'security', @EntityType = 'SUPPORT_ACCESS', @Action = 'REVOKE', @Summary = N'Ended Pillar support access';
    COMMIT;
END;
