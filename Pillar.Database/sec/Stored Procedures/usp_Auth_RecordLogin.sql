-- Records a sign-in event (no session context needed) and applies lockout:
-- 5 failed password or MFA attempts in a row lock the login for 15 minutes (a LOCKED event is added); LOGIN_OK clears the count.
-- @Email is enough when the login is unknown; @AppUserId wins when given.
CREATE PROCEDURE sec.usp_Auth_RecordLogin
    @EventType      VARCHAR(20),
    @Email          NVARCHAR(254) = NULL,
    @AppUserId      INT = NULL,
    @Detail         NVARCHAR(400) = NULL,
    @IpAddress      VARCHAR(45) = NULL,
    @UserAgent      NVARCHAR(400) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME(), @TenantId INT, @Failed INT,
            @Normalized NVARCHAR(254) = LOWER(LTRIM(RTRIM(@Email)));

    BEGIN TRAN;

    SELECT @AppUserId = c.AppUserId, @TenantId = c.TenantId, @Normalized = COALESCE(@Normalized, c.LoginEmail)
    FROM sec.UserCredential AS c WITH (UPDLOCK)
    WHERE (@AppUserId IS NOT NULL AND c.AppUserId = @AppUserId)
       OR (@AppUserId IS NULL AND c.LoginEmail = @Normalized);

    INSERT INTO sec.LoginAudit (EventType, Email, TenantId, AppUserId, Detail, IpAddress, UserAgent)
    VALUES (@EventType, @Normalized, @TenantId, @AppUserId, @Detail, @IpAddress, @UserAgent);

    IF @TenantId IS NOT NULL AND @EventType IN ('LOGIN_FAIL', 'MFA_FAIL')
    BEGIN
        UPDATE sec.UserCredential
        SET @Failed = FailedAttempts = FailedAttempts + 1, ModifiedAt = @Now
        WHERE AppUserId = @AppUserId;

        IF @Failed >= 5
        BEGIN
            UPDATE sec.UserCredential SET LockedUntil = DATEADD(MINUTE, 15, @Now), FailedAttempts = 0 WHERE AppUserId = @AppUserId;
            INSERT INTO sec.LoginAudit (EventType, Email, TenantId, AppUserId, Detail, IpAddress, UserAgent)
            VALUES ('LOCKED', @Normalized, @TenantId, @AppUserId, N'5 failed attempts; locked 15 minutes', @IpAddress, @UserAgent);
        END;
    END
    ELSE IF @TenantId IS NOT NULL AND @EventType = 'LOGIN_OK'
        UPDATE sec.UserCredential
        SET FailedAttempts = 0, LockedUntil = NULL, LastLoginAt = @Now, ModifiedAt = @Now
        WHERE AppUserId = @AppUserId;

    COMMIT;
END;
