-- The session user accepts a terms of service version (the "updated terms" prompt at sign-in). Accepting the same version
-- twice does nothing.
CREATE PROCEDURE sec.usp_Legal_Accept
    @DocumentId     INT,
    @IpAddress      VARCHAR(45) = NULL,
    @UserAgent      NVARCHAR(400) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')), @UserId INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 52216, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM admin.LegalDocument WHERE Id = @DocumentId AND PublishedAt <= SYSUTCDATETIME())
        THROW 52212, N'That document isn''t published.', 1;

    INSERT INTO sec.UserLegalAcceptance (TenantId, AppUserId, DocumentId, IpAddress, UserAgent)
    SELECT @TenantId, @UserId, @DocumentId, COALESCE(@IpAddress, CONVERT(VARCHAR(45), SESSION_CONTEXT(N'ClientIp'))), @UserAgent
    WHERE NOT EXISTS (SELECT 1 FROM sec.UserLegalAcceptance WHERE TenantId = @TenantId AND AppUserId = @UserId AND DocumentId = @DocumentId);
END;
