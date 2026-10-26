-- Support tickets (phase 1, simple). Tenants open them from Help (support.usp_Ticket_Open) and Pillar answers in the back office.
--   TicketType  QUESTION, PROBLEM, BILLING, CANCELLATION, DATA_DELETION (cancellation and data deletion are how a tenant
--               cancels or asks for its data to be deleted; only billing.manage holders may open those two)
--   Status      OPEN (waiting on Pillar), PENDING (waiting on the customer), RESOLVED, CLOSED
-- AssignedToUserId is a Pillar admin's login (in Pillar's tenant), so it has no FK.
CREATE TABLE support.Ticket
(
    Id                      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Ticket PRIMARY KEY CLUSTERED,
    TenantId                INT             NOT NULL,
    TicketType              VARCHAR(15)     NOT NULL,
    Subject                 NVARCHAR(200)   NOT NULL,
    Status                  VARCHAR(10)     NOT NULL CONSTRAINT DF_Ticket_Status DEFAULT ('OPEN'),
    Priority                VARCHAR(10)     NOT NULL CONSTRAINT DF_Ticket_Priority DEFAULT ('NORMAL'),
    OpenedBy                INT             NOT NULL,
    AssignedToUserId        INT             NULL,
    CreatedAt               DATETIME2(0)    NOT NULL CONSTRAINT DF_Ticket_CreatedAt DEFAULT (SYSUTCDATETIME()),
    LastMessageAt           DATETIME2(0)    NOT NULL CONSTRAINT DF_Ticket_LastMessageAt DEFAULT (SYSUTCDATETIME()),
    LastMessageFromPillar   BIT             NOT NULL CONSTRAINT DF_Ticket_LastMessageFromPillar DEFAULT (0),
    ResolvedAt              DATETIME2(0)    NULL,
    ClosedAt                DATETIME2(0)    NULL,
    CONSTRAINT UQ_Ticket_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT CK_Ticket_Type CHECK (TicketType = 'QUESTION' OR TicketType = 'PROBLEM' OR TicketType = 'BILLING'
        OR TicketType = 'CANCELLATION' OR TicketType = 'DATA_DELETION'),
    CONSTRAINT CK_Ticket_Status CHECK (Status = 'OPEN' OR Status = 'PENDING' OR Status = 'RESOLVED' OR Status = 'CLOSED'),
    CONSTRAINT CK_Ticket_Priority CHECK (Priority = 'LOW' OR Priority = 'NORMAL' OR Priority = 'HIGH' OR Priority = 'URGENT'),
    CONSTRAINT FK_Ticket_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id),
    CONSTRAINT FK_Ticket_OpenedBy FOREIGN KEY (TenantId, OpenedBy) REFERENCES sec.AppUser (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_Ticket_Status ON support.Ticket (Status, LastMessageAt DESC) INCLUDE (TenantId, Priority);
GO
CREATE NONCLUSTERED INDEX IX_Ticket_Tenant ON support.Ticket (TenantId, Id DESC);
