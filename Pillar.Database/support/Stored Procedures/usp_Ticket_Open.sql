-- Help > Contact support: the session user opens a ticket with its first message. CANCELLATION and DATA_DELETION tickets (how a
-- tenant cancels, or asks for its data to be deleted) need billing.manage. Pillar's inbox gets it (emailed); cancellation and
-- deletion requests arrive as CANCEL_REQUEST.
CREATE PROCEDURE support.usp_Ticket_Open
    @TicketType     VARCHAR(15),
    @Subject        NVARCHAR(200),
    @Body           NVARCHAR(MAX),
    @Priority       VARCHAR(10) = 'NORMAL',
    @TicketId       INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')), @UserId INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Name NVARCHAR(200), @Title NVARCHAR(200), @Kind VARCHAR(30);
    IF @TenantId IS NULL OR @UserId IS NULL THROW 52216, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NULLIF(LTRIM(RTRIM(@Subject)), N'') IS NULL OR NULLIF(LTRIM(RTRIM(@Body)), N'') IS NULL
        THROW 52260, N'A subject and a message are required.', 1;
    IF (@TicketType = 'CANCELLATION' OR @TicketType = 'DATA_DELETION')
       AND NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'billing.manage'))
        THROW 52262, N'Only people who manage Pillar billing can ask to cancel or delete the account.', 1;
    SELECT @Name = DisplayName FROM sec.AppUser WHERE TenantId = @TenantId AND Id = @UserId;

    BEGIN TRAN;
    INSERT INTO support.Ticket (TenantId, TicketType, Subject, Priority, OpenedBy)
    VALUES (@TenantId, @TicketType, @Subject, @Priority, @UserId);
    SET @TicketId = SCOPE_IDENTITY();
    INSERT INTO support.TicketMessage (TenantId, TicketId, AuthorUserId, AuthorName, Body)
    VALUES (@TenantId, @TicketId, @UserId, @Name, @Body);

    SET @Kind = IIF(@TicketType = 'CANCELLATION' OR @TicketType = 'DATA_DELETION', 'CANCEL_REQUEST', 'SUPPORT_TICKET');
    SET @Title = LEFT(CONCAT((SELECT Name FROM admin.Tenant WHERE Id = @TenantId), N': ', @Subject), 200);
    EXEC admin.usp_PlatformNotification_Raise @Kind = @Kind, @Title = @Title, @Body = @Body, @TenantId = @TenantId,
         @EntityType = 'TICKET', @EntityId = @TicketId;
    COMMIT;
END;
