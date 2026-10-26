-- Ends a support sign-in: from the back office (Pillar), or from the support connection itself (its SESSION_CONTEXT
-- ImpersonationSessionId). Logs SUPPORT_SIGNOUT and a row in the tenant's audit log. Ending one already ended does nothing.
CREATE PROCEDURE sec.usp_Impersonation_End
    @ImpersonationSessionId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0
       AND ISNULL(CONVERT(INT, SESSION_CONTEXT(N'ImpersonationSessionId')), 0) <> @ImpersonationSessionId
        THROW 52254, N'That support session isn''t yours to end.', 1;

    DECLARE @TenantId INT, @AsUserId INT, @AdminName NVARCHAR(200), @Summary NVARCHAR(400), @Key NVARCHAR(100) = CONVERT(NVARCHAR(100), @ImpersonationSessionId);

    BEGIN TRAN;
    UPDATE sec.ImpersonationSession
    SET EndedAt = SYSUTCDATETIME(), EndReason = 'SIGNOUT', @TenantId = TenantId, @AsUserId = AsUserId, @AdminName = PlatformAdminName
    WHERE Id = @ImpersonationSessionId AND EndedAt IS NULL;

    IF @TenantId IS NOT NULL
    BEGIN
        INSERT INTO sec.LoginAudit (EventType, TenantId, AppUserId, Detail) VALUES ('SUPPORT_SIGNOUT', @TenantId, @AsUserId, @AdminName);
        SET @Summary = CONCAT(N'Pillar support (', @AdminName, N') signed out');
        EXEC admin.usp_Audit_Write @Area = 'support', @EntityType = 'SUPPORT_SESSION', @EntityKey = @Key, @Action = 'UPDATE',
             @Summary = @Summary, @TenantId = @TenantId;
    END;
    COMMIT;
END;
