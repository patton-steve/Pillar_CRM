-- Typed notes on a client (call, meeting, email, note), optionally about one of its contacts. Shown on the client's
-- Notes tab and in the Overview activity feed (crm.vw_ClientActivity). Task notes stay in crm.TaskComment.
-- Body is rich text: HTML that the API sanitizes before saving. Write through crm.usp_ClientNote_Save.
CREATE TABLE crm.ClientNote
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ClientNote PRIMARY KEY CLUSTERED,
    PublicId        UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_ClientNote_PublicId DEFAULT (NEWSEQUENTIALID()),
    TenantId        INT             NOT NULL,
    ClientId        INT             NOT NULL,
    ContactId       INT             NULL,
    NoteTypeId      INT             NOT NULL,
    Subject         NVARCHAR(200)   NULL,
    Body            NVARCHAR(MAX)   NOT NULL,
    OccurredAt      DATETIME2(0)    NOT NULL,      -- when the call or meeting happened (UTC); defaults to now
    AuthorUserId    INT             NULL CONSTRAINT DF_ClientNote_AuthorUserId DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    EditedAt        DATETIME2(0)    NULL,
    DeletedAt       DATETIME2(0)    NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_ClientNote_CreatedAt DEFAULT (SYSUTCDATETIME()),
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_ClientNote_PublicId UNIQUE (PublicId),
    CONSTRAINT UQ_ClientNote_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT FK_ClientNote_Client FOREIGN KEY (TenantId, ClientId) REFERENCES crm.Client (TenantId, Id),
    CONSTRAINT FK_ClientNote_Contact FOREIGN KEY (TenantId, ClientId, ContactId) REFERENCES crm.Contact (TenantId, ClientId, Id),
    CONSTRAINT FK_ClientNote_NoteType FOREIGN KEY (TenantId, NoteTypeId) REFERENCES lkp.NoteType (TenantId, Id),
    CONSTRAINT FK_ClientNote_AuthorUser FOREIGN KEY (TenantId, AuthorUserId) REFERENCES sec.AppUser (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_ClientNote_Client ON crm.ClientNote (TenantId, ClientId, OccurredAt DESC) WHERE DeletedAt IS NULL;
GO
CREATE NONCLUSTERED INDEX IX_ClientNote_Contact ON crm.ClientNote (TenantId, ContactId, OccurredAt DESC) WHERE ContactId IS NOT NULL AND DeletedAt IS NULL;
