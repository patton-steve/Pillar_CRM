-- Signs the signed-in person out of one device (@FamilyId) or of every device except this one (@AllExceptFamilyId).
-- Logged as SESSION_REVOKED. Returns how many sessions ended.
CREATE PROCEDURE sec.usp_Session_Revoke
    @FamilyId           UNIQUEIDENTIFIER = NULL,
    @AllExceptFamilyId  UNIQUEIDENTIFIER = NULL,
    @Count              INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51720, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF (@FamilyId IS NULL AND @AllExceptFamilyId IS NULL) OR (@FamilyId IS NOT NULL AND @AllExceptFamilyId IS NOT NULL)
        THROW 51721, N'Pass either one session or the session to keep.', 1;

    UPDATE sec.RefreshToken SET RevokedAt = SYSUTCDATETIME(), RevokedReason = 'LOGOUT'
    WHERE TenantId = @TenantId AND AppUserId = @UserId AND RevokedAt IS NULL
      AND ((@FamilyId IS NOT NULL AND FamilyId = @FamilyId) OR (@AllExceptFamilyId IS NOT NULL AND FamilyId <> @AllExceptFamilyId));
    SET @Count = @@ROWCOUNT;     -- a family has one live token at a time (rotation revokes the previous one)

    IF @Count > 0
        INSERT INTO sec.LoginAudit (EventType, TenantId, AppUserId, Detail)
        VALUES ('SESSION_REVOKED', @TenantId, @UserId, IIF(@FamilyId IS NOT NULL, N'Signed out one device', N'Signed out all other devices'));
END;
