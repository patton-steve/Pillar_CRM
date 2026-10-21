-- Exchanges a refresh token for a new one in the same family (no session context needed).
-- Returns one row (AppUserId, TenantId, FamilyId) on success; no row = refuse and send the user to sign-in.
-- A token that was already rotated or revoked is treated as stolen: the whole family is revoked and REFRESH_REUSE is logged.
CREATE PROCEDURE sec.usp_Auth_RotateRefreshToken
    @TokenHash      BINARY(32),
    @NewTokenHash   BINARY(32),
    @NewExpiresAt   DATETIME2(0),
    @IpAddress      VARCHAR(45) = NULL,
    @UserAgent      NVARCHAR(400) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME(), @Id INT, @NewId INT, @AppUserId INT, @TenantId INT,
            @FamilyId UNIQUEIDENTIFIER, @RevokedAt DATETIME2(0), @ExpiresAt DATETIME2(0), @Enabled BIT;

    BEGIN TRAN;

    SELECT @Id = t.Id, @AppUserId = t.AppUserId, @TenantId = t.TenantId, @FamilyId = t.FamilyId,
           @RevokedAt = t.RevokedAt, @ExpiresAt = t.ExpiresAt, @Enabled = c.IsEnabled
    FROM sec.RefreshToken AS t WITH (UPDLOCK)
    JOIN sec.UserCredential AS c ON c.AppUserId = t.AppUserId
    WHERE t.TokenHash = @TokenHash;

    IF @Id IS NULL OR @ExpiresAt <= @Now OR @Enabled = 0
    BEGIN
        COMMIT;
        RETURN;
    END;

    IF @RevokedAt IS NOT NULL
    BEGIN
        UPDATE sec.RefreshToken SET RevokedAt = @Now, RevokedReason = 'REUSE'
        WHERE FamilyId = @FamilyId AND RevokedAt IS NULL;
        INSERT INTO sec.LoginAudit (EventType, TenantId, AppUserId, Detail, IpAddress, UserAgent)
        VALUES ('REFRESH_REUSE', @TenantId, @AppUserId, N'Rotated refresh token presented again; session family revoked', @IpAddress, @UserAgent);
        COMMIT;
        RETURN;
    END;

    INSERT INTO sec.RefreshToken (TenantId, AppUserId, FamilyId, TokenHash, ExpiresAt, IpAddress, UserAgent)
    VALUES (@TenantId, @AppUserId, @FamilyId, @NewTokenHash, @NewExpiresAt, @IpAddress, @UserAgent);
    SET @NewId = SCOPE_IDENTITY();

    UPDATE sec.RefreshToken SET RevokedAt = @Now, RevokedReason = 'ROTATED', ReplacedByTokenId = @NewId WHERE Id = @Id;

    COMMIT;

    SELECT @AppUserId AS AppUserId, @TenantId AS TenantId, @FamilyId AS FamilyId;
END;
