-- The API's per-request check on a support connection: one row, IsActive = 1 while the session is open and the tenant's grant is
-- still live. An expired grant ends the session here (EndReason EXPIRED).
CREATE PROCEDURE sec.usp_Impersonation_Check
    @ImpersonationSessionId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME(), @Live BIT = 0, @Open BIT = 0;

    SELECT @Open = IIF(s.EndedAt IS NULL, 1, 0),
           @Live = IIF(s.EndedAt IS NULL AND g.RevokedAt IS NULL AND g.ExpiresAt > @Now, 1, 0)
    FROM sec.ImpersonationSession AS s
    JOIN sec.SupportAccessGrant AS g ON g.TenantId = s.TenantId AND g.Id = s.GrantId
    WHERE s.Id = @ImpersonationSessionId;

    IF @Open = 1 AND @Live = 0
        UPDATE sec.ImpersonationSession SET EndedAt = @Now, EndReason = 'EXPIRED' WHERE Id = @ImpersonationSessionId AND EndedAt IS NULL;

    SELECT @Live AS IsActive;
END;
