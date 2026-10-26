-- Back office > tenant > Log in as (Steve 2026-10-22: full access, only with the tenant's permission). Pillar only, and only
-- under a live sec.SupportAccessGrant. @AsUserId NULL = the first active owner. Records the session, a SUPPORT_SIGNIN login
-- event, a row in the tenant's audit log and one in Pillar's audit trail, and returns the session id.
-- The API then opens a tenant connection with SESSION_CONTEXT TenantId = @TenantId, UserId = @AsUserId and
-- ImpersonationSessionId = the id (all read-only, and no IsPlatformAdmin), calls sec.usp_Impersonation_Check on each request,
-- and shows a "Signed in as ... (Pillar support)" bar with an End button (sec.usp_Impersonation_End).
CREATE PROCEDURE sec.usp_Impersonation_Start
    @TenantId                   INT,
    @Reason                     NVARCHAR(500),
    @AsUserId                   INT = NULL OUTPUT,
    @IpAddress                  VARCHAR(45) = NULL,
    @ImpersonationSessionId     INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;
    IF NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL THROW 52205, N'A reason is required.', 1;

    DECLARE @AdminId INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')), @AdminTenant INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @AdminName NVARCHAR(200), @GrantId INT, @AsName NVARCHAR(200), @Summary NVARCHAR(400), @Key NVARCHAR(100);
    IF @AdminId IS NULL THROW 52216, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;

    SELECT TOP (1) @GrantId = Id FROM sec.SupportAccessGrant
    WHERE TenantId = @TenantId AND RevokedAt IS NULL AND ExpiresAt > SYSUTCDATETIME() ORDER BY ExpiresAt DESC;
    IF @GrantId IS NULL THROW 52252, N'This tenant hasn''t allowed Pillar support to sign in.', 1;

    IF @AsUserId IS NULL
        SELECT TOP (1) @AsUserId = u.Id FROM sec.AppUser AS u
        JOIN sec.Role AS r ON r.TenantId = u.TenantId AND r.Id = u.RoleId AND r.IsOwner = 1
        WHERE u.TenantId = @TenantId AND u.Status = 'ACTIVE' AND u.CanLogin = 1 ORDER BY u.Id;
    SELECT @AsName = DisplayName FROM sec.AppUser WHERE TenantId = @TenantId AND Id = @AsUserId AND Status = 'ACTIVE';
    IF @AsName IS NULL THROW 52253, N'That person isn''t an active user in this tenant.', 1;
    SELECT @AdminName = DisplayName FROM sec.AppUser WHERE Id = @AdminId;

    BEGIN TRAN;
    INSERT INTO sec.ImpersonationSession (TenantId, AsUserId, GrantId, PlatformAdminUserId, PlatformAdminTenantId, PlatformAdminName, Reason, IpAddress)
    VALUES (@TenantId, @AsUserId, @GrantId, @AdminId, @AdminTenant, @AdminName, @Reason,
            COALESCE(@IpAddress, CONVERT(VARCHAR(45), SESSION_CONTEXT(N'ClientIp'))));
    SET @ImpersonationSessionId = SCOPE_IDENTITY();
    SET @Key = CONVERT(NVARCHAR(100), @ImpersonationSessionId);

    INSERT INTO sec.LoginAudit (EventType, TenantId, AppUserId, Detail, IpAddress)
    VALUES ('SUPPORT_SIGNIN', @TenantId, @AsUserId, LEFT(CONCAT(N'Pillar support (', @AdminName, N'): ', @Reason), 400),
            COALESCE(@IpAddress, CONVERT(VARCHAR(45), SESSION_CONTEXT(N'ClientIp'))));

    SET @Summary = LEFT(CONCAT(N'Pillar support (', @AdminName, N') signed in as ', @AsName, N': ', @Reason), 400);
    EXEC admin.usp_Audit_Write @Area = 'support', @EntityType = 'SUPPORT_SESSION', @EntityKey = @Key, @Action = 'CREATE',
         @Summary = @Summary, @TenantId = @TenantId;
    EXEC admin.usp_PlatformAudit_Write @Action = 'SUPPORT_SIGNIN', @TenantId = @TenantId, @EntityType = 'SUPPORT_SESSION', @EntityKey = @Key,
         @Summary = @Summary, @Reason = @Reason;
    COMMIT;
END;
