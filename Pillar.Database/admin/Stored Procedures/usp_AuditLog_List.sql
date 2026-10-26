-- Settings > Audit log, newest first. Needs settings.audit. Filters are optional; page with @BeforeId (last Id shown).
-- @Search matches the summary or entity key.
CREATE PROCEDURE admin.usp_AuditLog_List
    @From           DATE = NULL,
    @To             DATE = NULL,
    @ActorUserId    INT = NULL,
    @Area           VARCHAR(30) = NULL,
    @EntityType     VARCHAR(30) = NULL,
    @Search         NVARCHAR(100) = NULL,
    @Top            INT = 50,
    @BeforeId       BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51702, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'settings.audit'))
        THROW 51703, N'You need permission to view the audit log.', 1;

    SELECT TOP (@Top) a.Id, a.OccurredAt, a.ActorUserId, u.DisplayName AS ActorName, a.Area, a.EntityType, a.EntityKey,
           a.Action, a.Summary, a.ChangeJson, a.IpAddress
    FROM admin.AuditLog AS a
    LEFT JOIN sec.AppUser AS u ON u.TenantId = a.TenantId AND u.Id = a.ActorUserId
    WHERE a.TenantId = @TenantId
      AND (@BeforeId IS NULL OR a.Id < @BeforeId)
      AND (@From IS NULL OR a.OccurredAt >= @From)
      AND (@To IS NULL OR a.OccurredAt < DATEADD(DAY, 1, @To))
      AND (@ActorUserId IS NULL OR a.ActorUserId = @ActorUserId)
      AND (@Area IS NULL OR a.Area = @Area)
      AND (@EntityType IS NULL OR a.EntityType = @EntityType)
      AND (@Search IS NULL OR a.Summary LIKE CONCAT(N'%', @Search, N'%') OR a.EntityKey LIKE CONCAT(N'%', @Search, N'%'))
    ORDER BY a.Id DESC;
END;
