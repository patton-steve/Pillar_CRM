-- One ticket and its messages, oldest first. The tenant never sees internal notes, and sees only its own tickets (the opener's,
-- or all for users.manage holders).
CREATE PROCEDURE support.usp_Ticket_Get
    @TicketId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IsPillar BIT = ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0),
            @UserId INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')), @TenantId INT, @OpenedBy INT;

    SELECT @TenantId = TenantId, @OpenedBy = OpenedBy FROM support.Ticket WHERE Id = @TicketId;
    IF @TenantId IS NULL
       OR (@IsPillar = 0 AND @OpenedBy <> @UserId AND NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'users.manage')))
        THROW 52261, N'Unknown ticket.', 1;

    SELECT k.Id, k.TenantId, t.Name AS TenantName, k.TicketType, k.Subject, k.Status, k.Priority, k.OpenedBy,
           u.DisplayName AS OpenedByName, u.Email AS OpenedByEmail, k.AssignedToUserId, k.CreatedAt, k.LastMessageAt, k.ResolvedAt, k.ClosedAt
    FROM support.Ticket AS k
    JOIN admin.Tenant AS t ON t.Id = k.TenantId
    JOIN sec.AppUser AS u ON u.TenantId = k.TenantId AND u.Id = k.OpenedBy
    WHERE k.Id = @TicketId;

    SELECT m.Id, m.AuthorUserId, m.AuthorName, m.IsFromPillar, m.IsInternal, m.Body, m.CreatedAt
    FROM support.TicketMessage AS m
    WHERE m.TenantId = @TenantId AND m.TicketId = @TicketId AND (@IsPillar = 1 OR m.IsInternal = 0)
    ORDER BY m.Id;
END;
