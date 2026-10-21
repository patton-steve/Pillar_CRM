-- Invites someone to log in to the session tenant. Creates the user (Status INVITED), or gives an existing
-- no-login person a login on the same row (their time and history stay attached), or re-sends a pending invite.
-- The API generates the random token, emails the link, and passes only its SHA-256 hash. Earlier unused invites are revoked.
-- Who may invite (users.manage) is checked by the API.
CREATE PROCEDURE sec.usp_User_Invite
    @Email          NVARCHAR(254),
    @TokenHash      BINARY(32),
    @FirstName      NVARCHAR(100) = NULL,   -- required for a new user
    @LastName       NVARCHAR(100) = NULL,
    @RoleId         INT = NULL,             -- NULL = the tenant's default role (new users only)
    @UserType       VARCHAR(12) = 'EMPLOYEE',
    @ExpiresAt      DATETIME2(0) = NULL,    -- default 7 days
    @AppUserId      INT = NULL OUTPUT       -- existing user to give a login / re-invite
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @UserId   INT = CAST(SESSION_CONTEXT(N'UserId') AS INT),
            @Now DATETIME2(0) = SYSUTCDATETIME(),
            @Normalized NVARCHAR(254) = LOWER(LTRIM(RTRIM(@Email)));

    IF @TenantId IS NULL THROW 50941, N'No tenant in session.', 1;
    IF @Normalized IS NULL OR @Normalized NOT LIKE N'_%@_%._%' THROW 50942, N'A valid email is required.', 1;
    IF EXISTS (SELECT 1 FROM sec.UserCredential WHERE LoginEmail = @Normalized AND AppUserId <> ISNULL(@AppUserId, 0))
        THROW 50943, N'That email is already used by another login.', 1;

    BEGIN TRAN;

    IF @AppUserId IS NULL
    BEGIN
        IF @FirstName IS NULL THROW 50944, N'First name is required.', 1;
        INSERT INTO sec.AppUser (TenantId, Email, FirstName, LastName, UserType, RoleId, CanLogin, Status)
        SELECT @TenantId, @Email, @FirstName, @LastName, @UserType,
               COALESCE(@RoleId, (SELECT r.Id FROM sec.Role AS r WHERE r.TenantId = @TenantId AND r.IsDefault = 1)),
               1, 'INVITED';
        SET @AppUserId = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM sec.AppUser WITH (UPDLOCK)
                       WHERE TenantId = @TenantId AND Id = @AppUserId AND (CanLogin = 0 OR Status = 'INVITED'))
            THROW 50945, N'This person already has a login.', 1;
        UPDATE sec.AppUser
        SET Email = @Email, CanLogin = 1, Status = 'INVITED', ModifiedAt = @Now, ModifiedBy = @UserId
        WHERE TenantId = @TenantId AND Id = @AppUserId;
    END;

    IF NOT EXISTS (SELECT 1 FROM sec.UserCredential WHERE AppUserId = @AppUserId)
        INSERT INTO sec.UserCredential (AppUserId, TenantId, LoginEmail, IsEnabled)
        VALUES (@AppUserId, @TenantId, @Normalized, 1);

    UPDATE sec.UserToken SET RevokedAt = @Now
    WHERE AppUserId = @AppUserId AND Purpose = 'INVITE' AND UsedAt IS NULL AND RevokedAt IS NULL;

    INSERT INTO sec.UserToken (TenantId, AppUserId, Purpose, TokenHash, ExpiresAt)
    VALUES (@TenantId, @AppUserId, 'INVITE', @TokenHash, COALESCE(@ExpiresAt, DATEADD(DAY, 7, @Now)));

    COMMIT;
END;
