-- Adds a message to a ticket. From Pillar (IsPlatformAdmin): a reply the tenant sees (status becomes PENDING, waiting on the
-- customer, unless @Status says otherwise; the opener gets a SUPPORT_REPLY notification), or an internal note (@IsInternal = 1).
-- From the tenant: the ticket goes back to OPEN (also when it was RESOLVED) and Pillar's inbox gets it. A CLOSED ticket takes no
-- more messages from the tenant; they open a new one.
CREATE PROCEDURE support.usp_Ticket_Reply
    @TicketId       INT,
    @Body           NVARCHAR(MAX),
    @IsInternal     BIT = 0,
    @Status         VARCHAR(10) = NULL      -- Pillar only: the status after this reply
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @IsPillar BIT = ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0),
            @UserId INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')), @TenantId INT, @OpenedBy INT, @Old VARCHAR(10),
            @Subject NVARCHAR(200), @Name NVARCHAR(200), @Title NVARCHAR(200), @Now DATETIME2(0) = SYSUTCDATETIME(), @To NVARCHAR(50);

    IF NULLIF(LTRIM(RTRIM(@Body)), N'') IS NULL THROW 52260, N'A subject and a message are required.', 1;
    IF @IsInternal = 1 AND @IsPillar = 0 THROW 52264, N'Internal notes are for Pillar only.', 1;

    SELECT @TenantId = TenantId, @OpenedBy = OpenedBy, @Old = Status, @Subject = Subject FROM support.Ticket WHERE Id = @TicketId;
    IF @TenantId IS NULL THROW 52261, N'Unknown ticket.', 1;
    IF @IsPillar = 0 AND @Old = 'CLOSED' THROW 52263, N'This ticket is closed. Please open a new one.', 1;
    IF @IsPillar = 0 AND @OpenedBy <> @UserId
       AND NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'users.manage'))
        THROW 52261, N'Unknown ticket.', 1;
    SELECT @Name = DisplayName FROM sec.AppUser WHERE Id = @UserId;

    BEGIN TRAN;
    INSERT INTO support.TicketMessage (TenantId, TicketId, AuthorUserId, AuthorName, IsFromPillar, IsInternal, Body)
    VALUES (@TenantId, @TicketId, @UserId, IIF(@IsPillar = 1, N'Pillar support', @Name), @IsPillar, @IsInternal, @Body);

    IF @IsInternal = 0
    BEGIN
        UPDATE support.Ticket
        SET Status = CASE WHEN @IsPillar = 1 THEN COALESCE(@Status, 'PENDING') ELSE 'OPEN' END,
            LastMessageAt = @Now, LastMessageFromPillar = @IsPillar,
            ResolvedAt = CASE WHEN @IsPillar = 1 AND @Status = 'RESOLVED' THEN @Now WHEN @IsPillar = 0 THEN NULL ELSE ResolvedAt END,
            ClosedAt = CASE WHEN @IsPillar = 1 AND @Status = 'CLOSED' THEN @Now ELSE ClosedAt END
        WHERE Id = @TicketId;

        IF @IsPillar = 1
        BEGIN
            SET @Title = LEFT(CONCAT(N'Pillar support replied: ', @Subject), 200);
            SET @To = CONCAT(N'[', @OpenedBy, N']');
            EXEC sec.usp_Notification_Raise @NotificationType = 'SUPPORT_REPLY', @EntityType = 'TICKET', @EntityId = @TicketId,
                 @Title = @Title, @RecipientUserIds = @To, @ForTenantId = @TenantId;
        END
        ELSE
        BEGIN
            SET @Title = LEFT(CONCAT((SELECT Name FROM admin.Tenant WHERE Id = @TenantId), N' replied: ', @Subject), 200);
            EXEC admin.usp_PlatformNotification_Raise @Kind = 'SUPPORT_REPLY', @Title = @Title, @Body = @Body, @TenantId = @TenantId,
                 @EntityType = 'TICKET', @EntityId = @TicketId;
        END;
    END
    ELSE IF @Status IS NOT NULL
        UPDATE support.Ticket SET Status = @Status WHERE Id = @TicketId;
    COMMIT;
END;
