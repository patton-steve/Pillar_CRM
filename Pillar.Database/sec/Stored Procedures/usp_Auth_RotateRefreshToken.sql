-- Exchanges a refresh token for a new one in the same family (no session context needed).
-- Returns one row (AppUserId, TenantId, FamilyId) on success; no row = refuse and send the user to sign-in.
-- A token that was already rotated or revoked is treated as stolen: the whole family is revoked and REFRESH_REUSE is logged,
-- with the old token's age, when it was rotated, and the IP and browser it was issued to.
-- Grace (proposed by the API thread, 2026-11-04): a browser whose last refresh reply never landed (sleep, network drop)
-- presents the token just before the live one. That is allowed, once, when all of these hold:
--   the token was ROTATED (not revoked for another reason), and no token in the family was revoked for any other reason;
--   its successor is the family's live token, never used (the API's own same-second second rotation is followed through);
--   it was rotated at most @GraceSeconds ago, or at most @SameDeviceGraceSeconds ago from the same IP and user agent
--   that the live token was issued to.
-- Then the live token is rotated instead (marked GRACE, so it can't be used or taken in a later grace) and REFRESH_GRACE
-- is logged. Presenting the old token again afterwards is reuse: its successor is no longer live.
CREATE PROCEDURE sec.usp_Auth_RotateRefreshToken
    @TokenHash              BINARY(32),
    @NewTokenHash           BINARY(32),
    @NewExpiresAt           DATETIME2(0),
    @IpAddress              VARCHAR(45) = NULL,
    @UserAgent              NVARCHAR(400) = NULL,
    @GraceSeconds           INT = 60,
    @SameDeviceGraceSeconds INT = 900
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME(), @Id INT, @NewId INT, @AppUserId INT, @TenantId INT,
            @FamilyId UNIQUEIDENTIFIER, @RevokedAt DATETIME2(0), @ExpiresAt DATETIME2(0), @Enabled BIT,
            @Reason VARCHAR(20), @NextId INT, @IssuedAt DATETIME2(0), @OldIp VARCHAR(45), @OldUa NVARCHAR(400),
            @HeadId INT, @HeadIssued DATETIME2(0), @HeadRevoked DATETIME2(0), @HeadReason VARCHAR(20), @HeadNext INT,
            @HeadExpires DATETIME2(0), @HeadIp VARCHAR(45), @HeadUa NVARCHAR(400), @Age INT, @Since INT,
            @Live BIT = 0, @Detail NVARCHAR(400);

    BEGIN TRAN;

    SELECT @Id = t.Id, @AppUserId = t.AppUserId, @TenantId = t.TenantId, @FamilyId = t.FamilyId,
           @RevokedAt = t.RevokedAt, @ExpiresAt = t.ExpiresAt, @Enabled = c.IsEnabled, @Reason = t.RevokedReason,
           @NextId = t.ReplacedByTokenId, @IssuedAt = t.IssuedAt, @OldIp = t.IpAddress, @OldUa = t.UserAgent
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
        SET @Age = DATEDIFF(SECOND, @IssuedAt, @Now);
        SET @Since = DATEDIFF(SECOND, @RevokedAt, @Now);
        IF @Reason = 'ROTATED' AND @NextId IS NOT NULL
        BEGIN
            SELECT @HeadId = Id, @HeadIssued = IssuedAt, @HeadRevoked = RevokedAt, @HeadReason = RevokedReason,
                   @HeadNext = ReplacedByTokenId, @HeadExpires = ExpiresAt, @HeadIp = IpAddress, @HeadUa = UserAgent
            FROM sec.RefreshToken WITH (UPDLOCK) WHERE Id = @NextId;
            -- the API rotates twice in one refresh (a placeholder expiry, then the policy's); follow that hop
            IF @HeadRevoked IS NOT NULL AND @HeadReason = 'ROTATED' AND @HeadNext IS NOT NULL
               AND DATEDIFF(SECOND, @HeadIssued, @HeadRevoked) <= 2
                SELECT @HeadId = Id, @HeadIssued = IssuedAt, @HeadRevoked = RevokedAt, @HeadReason = RevokedReason,
                       @HeadNext = ReplacedByTokenId, @HeadExpires = ExpiresAt, @HeadIp = IpAddress, @HeadUa = UserAgent
                FROM sec.RefreshToken WITH (UPDLOCK) WHERE Id = @HeadNext;
            IF @HeadRevoked IS NULL AND @HeadExpires > @Now SET @Live = 1;
        END;

        IF @Live = 1
           AND NOT EXISTS (SELECT 1 FROM sec.RefreshToken WHERE FamilyId = @FamilyId AND RevokedReason NOT IN ('ROTATED', 'GRACE'))
           AND (@Since <= @GraceSeconds
                OR (@Since <= @SameDeviceGraceSeconds AND ISNULL(@IpAddress, '') = ISNULL(@HeadIp, '')
                    AND ISNULL(@UserAgent, N'') = ISNULL(@HeadUa, N'')))
        BEGIN
            INSERT INTO sec.RefreshToken (TenantId, AppUserId, FamilyId, TokenHash, ExpiresAt, IpAddress, UserAgent)
            VALUES (@TenantId, @AppUserId, @FamilyId, @NewTokenHash, @NewExpiresAt, @IpAddress, @UserAgent);
            SET @NewId = SCOPE_IDENTITY();
            -- GRACE, not ROTATED: the token it replaces can't itself be taken in a later grace
            UPDATE sec.RefreshToken SET RevokedAt = @Now, RevokedReason = 'GRACE', ReplacedByTokenId = @NewId WHERE Id = @HeadId;
            SET @Detail = LEFT(CONCAT(N'Previous refresh token accepted in the grace window: rotated ', @Since, N's ago, issued ',
                                      @Age, N's ago to ', ISNULL(@OldIp, N'?'), N' / ', ISNULL(@OldUa, N'?')), 400);
            INSERT INTO sec.LoginAudit (EventType, TenantId, AppUserId, Detail, IpAddress, UserAgent)
            VALUES ('REFRESH_GRACE', @TenantId, @AppUserId, @Detail, @IpAddress, @UserAgent);
            COMMIT;
            SELECT @AppUserId AS AppUserId, @TenantId AS TenantId, @FamilyId AS FamilyId;
            RETURN;
        END;

        UPDATE sec.RefreshToken SET RevokedAt = @Now, RevokedReason = 'REUSE'
        WHERE FamilyId = @FamilyId AND RevokedAt IS NULL;
        SET @Detail = LEFT(CONCAT(N'Rotated refresh token presented again; session family revoked. It was revoked (', ISNULL(@Reason, N'?'),
                                  N') ', @Since, N's ago, issued ', @Age, N's ago to ', ISNULL(@OldIp, N'?'),
                                  N'; live successor: ', IIF(@Live = 1, N'yes', N'no'), N'; browser: ', ISNULL(@OldUa, N'?')), 400);
        INSERT INTO sec.LoginAudit (EventType, TenantId, AppUserId, Detail, IpAddress, UserAgent)
        VALUES ('REFRESH_REUSE', @TenantId, @AppUserId, @Detail, @IpAddress, @UserAgent);
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
