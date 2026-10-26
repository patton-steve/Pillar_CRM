-- Support tickets. In the app: the session user's own tickets, or the whole company's for users.manage holders. In the back
-- office (IsPlatformAdmin): every tenant's, filtered by @Status and @TenantId, waiting-on-Pillar first.
CREATE PROCEDURE support.usp_Ticket_List
    @Status     VARCHAR(10) = NULL,
    @TenantId   INT = NULL,
    @Top        INT = 100
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IsPillar BIT = ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0),
            @UserId INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')), @Session INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @All BIT = 0;
    IF @IsPillar = 0 AND EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@Session, @UserId, 'users.manage')) SET @All = 1;

    SELECT TOP (@Top) k.Id, k.TenantId, t.Name AS TenantName, k.TicketType, k.Subject, k.Status, k.Priority,
           k.OpenedBy, u.DisplayName AS OpenedByName, k.AssignedToUserId, k.CreatedAt, k.LastMessageAt, k.LastMessageFromPillar,
           k.ResolvedAt, k.ClosedAt
    FROM support.Ticket AS k
    JOIN admin.Tenant AS t ON t.Id = k.TenantId
    JOIN sec.AppUser AS u ON u.TenantId = k.TenantId AND u.Id = k.OpenedBy
    WHERE (@Status IS NULL OR k.Status = @Status)
      AND (@IsPillar = 1 OR k.TenantId = @Session)
      AND (@IsPillar = 0 OR @TenantId IS NULL OR k.TenantId = @TenantId)
      AND (@IsPillar = 1 OR @All = 1 OR k.OpenedBy = @UserId)
    ORDER BY CASE WHEN @IsPillar = 1 AND k.Status = 'OPEN' THEN 0 ELSE 1 END, k.LastMessageAt DESC;
END;
