-- The conversation on a support ticket. IsFromPillar = 1 for Pillar's replies (AuthorUserId is then a Pillar admin's login, so
-- AuthorUserId has no FK and AuthorName is a snapshot). IsInternal = 1 is a Pillar-only note the tenant never sees.
CREATE TABLE support.TicketMessage
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TicketMessage PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    TicketId        INT             NOT NULL,
    AuthorUserId    INT             NULL,
    AuthorName      NVARCHAR(200)   NULL,
    IsFromPillar    BIT             NOT NULL CONSTRAINT DF_TicketMessage_IsFromPillar DEFAULT (0),
    IsInternal      BIT             NOT NULL CONSTRAINT DF_TicketMessage_IsInternal DEFAULT (0),
    Body            NVARCHAR(MAX)   NOT NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_TicketMessage_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT CK_TicketMessage_Internal CHECK (IsInternal = 0 OR IsFromPillar = 1),
    CONSTRAINT FK_TicketMessage_Ticket FOREIGN KEY (TenantId, TicketId) REFERENCES support.Ticket (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_TicketMessage_Ticket ON support.TicketMessage (TenantId, TicketId, Id);
