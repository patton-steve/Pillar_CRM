-- Settings > Security > "Let Pillar support sign in": the tenant allows Pillar support to sign in as its people for @Days
-- (1 to 30, default 7). Replaces a live grant. Needs settings.security (Owner and Admin by default). Audited.
CREATE PROCEDURE sec.usp_SupportAccess_Grant
    @Days       INT = 7,
    @Note       NVARCHAR(500) = NULL,
    @GrantId    INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')), @UserId INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Now DATETIME2(0) = SYSUTCDATETIME(), @Summary NVARCHAR(400), @Key NVARCHAR(100);
    IF @TenantId IS NULL OR @UserId IS NULL THROW 52216, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'settings.security'))
        THROW 52250, N'You don''t have permission to change support access.', 1;
    IF @Days IS NULL OR @Days < 1 OR @Days > 30 THROW 52251, N'Support access lasts 1 to 30 days.', 1;

    BEGIN TRAN;
    UPDATE sec.SupportAccessGrant SET RevokedAt = @Now, RevokedBy = @UserId
    WHERE TenantId = @TenantId AND RevokedAt IS NULL AND ExpiresAt > @Now;
    INSERT INTO sec.SupportAccessGrant (TenantId, GrantedBy, GrantedAt, ExpiresAt, Note)
    VALUES (@TenantId, @UserId, @Now, DATEADD(DAY, @Days, @Now), @Note);
    SET @GrantId = SCOPE_IDENTITY();
    SET @Key = CONVERT(NVARCHAR(100), @GrantId);
    SET @Summary = CONCAT(N'Allowed Pillar support to sign in for ', @Days, N' day', IIF(@Days = 1, N'', N's'));
    EXEC admin.usp_Audit_Write @Area = 'security', @EntityType = 'SUPPORT_ACCESS', @EntityKey = @Key, @Action = 'GRANT', @Summary = @Summary;
    COMMIT;
END;
