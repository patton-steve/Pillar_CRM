-- An admin changes someone's email (Steve 2026-10-21: people can't change their own). Needs users.manage.
-- The login email stays unique across Pillar. For a person with a login, every session is signed out and EMAIL_CHANGED is
-- logged; @OldEmail is returned so the API can tell the old address. Audited. Errors 51717-51719.
CREATE PROCEDURE sec.usp_User_ChangeEmail
    @AppUserId      INT,
    @NewEmail       NVARCHAR(254),
    @OldEmail       NVARCHAR(254) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Normalized NVARCHAR(254) = LOWER(LTRIM(RTRIM(@NewEmail))), @CanLogin BIT,
            @AuditKey NVARCHAR(100) = CONVERT(NVARCHAR(100), @AppUserId), @AuditChange NVARCHAR(MAX);

    IF @TenantId IS NULL OR @UserId IS NULL THROW 51717, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'users.manage'))
        THROW 51718, N'Only an admin can change someone''s email.', 1;
    IF @Normalized IS NULL OR @Normalized NOT LIKE N'_%@_%._%' THROW 50942, N'A valid email is required.', 1;

    BEGIN TRAN;

    SELECT @OldEmail = Email, @CanLogin = CanLogin FROM sec.AppUser WITH (UPDLOCK)
    WHERE TenantId = @TenantId AND Id = @AppUserId;
    IF @CanLogin IS NULL THROW 51719, N'Person not found.', 1;
    IF @CanLogin = 1 AND EXISTS (SELECT 1 FROM sec.UserCredential WHERE LoginEmail = @Normalized AND AppUserId <> @AppUserId)
        THROW 50943, N'That email is already used by another login.', 1;

    UPDATE sec.AppUser SET Email = LTRIM(RTRIM(@NewEmail)), ModifiedAt = SYSUTCDATETIME(), ModifiedBy = @UserId
    WHERE TenantId = @TenantId AND Id = @AppUserId;      -- sec.trg_AppUser_Rules moves the login email

    IF @CanLogin = 1
    BEGIN
        UPDATE sec.RefreshToken SET RevokedAt = SYSUTCDATETIME(), RevokedReason = 'EMAIL_CHANGED'
        WHERE AppUserId = @AppUserId AND RevokedAt IS NULL;
        INSERT INTO sec.LoginAudit (EventType, Email, TenantId, AppUserId, Detail)
        VALUES ('EMAIL_CHANGED', @Normalized, @TenantId, @AppUserId, CONCAT(N'Changed from ', @OldEmail, N' by user ', @UserId));
    END;

    SET @AuditChange = (SELECT N'Email' AS field, @OldEmail AS [from], @NewEmail AS [to] FOR JSON PATH, INCLUDE_NULL_VALUES);
    EXEC admin.usp_Audit_Write @Area = 'users', @EntityType = 'USER', @EntityKey = @AuditKey, @Action = 'UPDATE',
         @Summary = N'Changed a person''s email', @ChangeJson = @AuditChange;

    COMMIT;
END;
