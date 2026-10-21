-- Stores a new refresh token (its SHA-256 hash) after a successful sign-in. @FamilyId NULL starts a new family (one per sign-in).
CREATE PROCEDURE sec.usp_Auth_IssueRefreshToken
    @AppUserId      INT,
    @TokenHash      BINARY(32),
    @ExpiresAt      DATETIME2(0),
    @FamilyId       UNIQUEIDENTIFIER = NULL OUTPUT,
    @IpAddress      VARCHAR(45) = NULL,
    @UserAgent      NVARCHAR(400) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT;
    SELECT @TenantId = TenantId FROM sec.UserCredential WHERE AppUserId = @AppUserId AND IsEnabled = 1;
    IF @TenantId IS NULL THROW 50951, N'This login is disabled.', 1;

    SET @FamilyId = COALESCE(@FamilyId, NEWID());
    INSERT INTO sec.RefreshToken (TenantId, AppUserId, FamilyId, TokenHash, ExpiresAt, IpAddress, UserAgent)
    VALUES (@TenantId, @AppUserId, @FamilyId, @TokenHash, @ExpiresAt, @IpAddress, @UserAgent);
END;
