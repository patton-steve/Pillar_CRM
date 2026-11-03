-- Settings > Billing > AI usage: the tenant's own Pilo log, newest first, for the screen and its CSV export. Needs
-- billing.manage. Model, tokens and cost stay Pillar's (admin.usp_PlatformPiloCost). Filters are optional; page with
-- @BeforeId (the last Id shown). CountsTowardQuota says which rows made up the month's report count.
CREATE PROCEDURE ai.usp_Generation_List
    @From           DATE = NULL,
    @To             DATE = NULL,
    @AppUserId      INT = NULL,
    @Feature        VARCHAR(15) = NULL,
    @Top            INT = 100,
    @BeforeId       BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 52401, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'billing.manage'))
        THROW 52402, N'You need permission to manage Pillar billing to see AI usage.', 1;
    IF @Top IS NULL OR @Top < 1 OR @Top > 5000 SET @Top = 100;

    SELECT TOP (@Top) g.Id, g.CreatedAt, g.AppUserId, u.DisplayName AS PersonName, g.Feature, g.Prompt, g.Outcome, g.Succeeded,
           g.CountsTowardQuota, g.SavedReportId, r.Name AS SavedReportName
    FROM ai.Generation AS g
    LEFT JOIN sec.AppUser AS u ON u.TenantId = g.TenantId AND u.Id = g.AppUserId
    LEFT JOIN admin.SavedReport AS r ON r.TenantId = g.TenantId AND r.Id = g.SavedReportId
    WHERE g.TenantId = @TenantId
      AND (@BeforeId IS NULL OR g.Id < @BeforeId)
      AND (@From IS NULL OR g.CreatedAt >= @From)
      AND (@To IS NULL OR g.CreatedAt < DATEADD(DAY, 1, @To))
      AND (@AppUserId IS NULL OR g.AppUserId = @AppUserId)
      AND (@Feature IS NULL OR g.Feature = @Feature)
    ORDER BY g.Id DESC;
END;
