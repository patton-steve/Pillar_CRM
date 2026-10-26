-- Changes a ticket's status (and, for Pillar, its priority and who it's assigned to). The tenant can only close its own ticket
-- (the opener, or users.manage holders).
CREATE PROCEDURE support.usp_Ticket_SetStatus
    @TicketId           INT,
    @Status             VARCHAR(10) = NULL,
    @Priority           VARCHAR(10) = NULL,
    @AssignedToUserId   INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IsPillar BIT = ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0),
            @UserId INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')), @TenantId INT, @OpenedBy INT, @Now DATETIME2(0) = SYSUTCDATETIME();

    SELECT @TenantId = TenantId, @OpenedBy = OpenedBy FROM support.Ticket WHERE Id = @TicketId;
    IF @TenantId IS NULL THROW 52261, N'Unknown ticket.', 1;
    IF @IsPillar = 0
    BEGIN
        IF @OpenedBy <> @UserId AND NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'users.manage'))
            THROW 52261, N'Unknown ticket.', 1;
        IF ISNULL(@Status, '') <> 'CLOSED' OR @Priority IS NOT NULL OR @AssignedToUserId IS NOT NULL
            THROW 52265, N'You can close your ticket; Pillar handles the rest.', 1;
    END;

    UPDATE support.Ticket
    SET Status = COALESCE(@Status, Status), Priority = COALESCE(@Priority, Priority),
        AssignedToUserId = COALESCE(@AssignedToUserId, AssignedToUserId),
        ResolvedAt = CASE WHEN @Status = 'RESOLVED' THEN @Now WHEN @Status = 'OPEN' OR @Status = 'PENDING' THEN NULL ELSE ResolvedAt END,
        ClosedAt = CASE WHEN @Status = 'CLOSED' THEN @Now WHEN @Status IS NOT NULL THEN NULL ELSE ClosedAt END
    WHERE Id = @TicketId;
END;
