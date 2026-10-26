-- My profile > Active sessions: one row per signed-in device (refresh-token family) that is still live, newest activity
-- first. Started = the sign-in; LastUsedAt = the latest rotation; device and IP are from the latest rotation.
-- Pass @CurrentFamilyId (from the caller's token) to flag "This device".
CREATE PROCEDURE sec.usp_Session_List
    @CurrentFamilyId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51720, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;

    SELECT live.FamilyId, f.StartedAt, live.IssuedAt AS LastUsedAt, live.ExpiresAt, live.UserAgent, live.IpAddress,
           CONVERT(BIT, IIF(live.FamilyId = @CurrentFamilyId, 1, 0)) AS IsCurrent
    FROM sec.RefreshToken AS live
    CROSS APPLY (SELECT MIN(t.IssuedAt) AS StartedAt FROM sec.RefreshToken AS t WHERE t.FamilyId = live.FamilyId) AS f
    WHERE live.TenantId = @TenantId AND live.AppUserId = @UserId
      AND live.RevokedAt IS NULL AND live.ExpiresAt > SYSUTCDATETIME()
    ORDER BY live.IssuedAt DESC;
END;
