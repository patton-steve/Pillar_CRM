-- Accepts an invite or completes a password reset (no sign-in needed; the token proves who it is).
-- Sets the bcrypt hash from the API, clears lockout, marks the token used. INVITE also makes the user ACTIVE;
-- RESET signs the user out everywhere. Returns one row (AppUserId, TenantId) on success; no row = invalid or expired link.
CREATE PROCEDURE sec.usp_Auth_RedeemToken
    @TokenHash      BINARY(32),
    @Purpose        VARCHAR(10),
    @PasswordHash   VARCHAR(255),
    @IpAddress      VARCHAR(45) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME(), @TokenId INT, @AppUserId INT, @TenantId INT;

    BEGIN TRAN;

    SELECT @TokenId = t.Id, @AppUserId = t.AppUserId, @TenantId = t.TenantId
    FROM sec.UserToken AS t WITH (UPDLOCK)
    JOIN sec.UserCredential AS c ON c.AppUserId = t.AppUserId AND c.IsEnabled = 1
    WHERE t.TokenHash = @TokenHash AND t.Purpose = @Purpose
      AND t.UsedAt IS NULL AND t.RevokedAt IS NULL AND t.ExpiresAt > @Now;

    IF @TokenId IS NULL
    BEGIN
        COMMIT;
        RETURN;
    END;

    UPDATE sec.UserToken SET UsedAt = @Now WHERE Id = @TokenId;
    UPDATE sec.UserCredential
    SET PasswordHash = @PasswordHash, PasswordChangedAt = @Now, MustChangePassword = 0,
        FailedAttempts = 0, LockedUntil = NULL, ModifiedAt = @Now
    WHERE AppUserId = @AppUserId;

    IF @Purpose = 'INVITE'
    BEGIN
        -- sec.AppUser is under RLS: act as the token's tenant
        EXEC sec.usp_ReportContext_Set @TenantId = @TenantId;
        UPDATE sec.AppUser SET Status = 'ACTIVE', ModifiedAt = @Now
        WHERE TenantId = @TenantId AND Id = @AppUserId AND Status = 'INVITED';
    END
    ELSE
        EXEC sec.usp_Auth_RevokeRefreshTokens @AppUserId = @AppUserId, @Reason = 'PASSWORD_RESET';

    INSERT INTO sec.LoginAudit (EventType, TenantId, AppUserId, IpAddress)
    VALUES (CASE WHEN @Purpose = 'INVITE' THEN 'INVITE_ACCEPTED' ELSE 'PASSWORD_RESET' END, @TenantId, @AppUserId, @IpAddress);

    COMMIT;

    SELECT @AppUserId AS AppUserId, @TenantId AS TenantId;
END;
