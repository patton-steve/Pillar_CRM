-- Sign-out: revokes one session family (@FamilyId) or, with @FamilyId NULL, every session of the user ("sign out everywhere").
CREATE PROCEDURE sec.usp_Auth_RevokeRefreshTokens
    @AppUserId      INT,
    @FamilyId       UNIQUEIDENTIFIER = NULL,
    @Reason         VARCHAR(20) = 'LOGOUT'
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE sec.RefreshToken
    SET RevokedAt = SYSUTCDATETIME(), RevokedReason = @Reason
    WHERE AppUserId = @AppUserId AND RevokedAt IS NULL AND (@FamilyId IS NULL OR FamilyId = @FamilyId);

    IF @Reason = 'LOGOUT'
        INSERT INTO sec.LoginAudit (EventType, TenantId, AppUserId)
        SELECT 'LOGOUT', TenantId, AppUserId FROM sec.UserCredential WHERE AppUserId = @AppUserId;
END;
