-- Rendered copies of an invoice (PDF from SSRS). The file lives in blob storage under StorageKey, like task attachments.
-- The API renders on issue and on resend; the newest row is the copy of record. Never edited, only added.
CREATE TABLE ar.InvoiceDocument
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_InvoiceDocument PRIMARY KEY CLUSTERED,
    PublicId        UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_InvoiceDocument_PublicId DEFAULT (NEWSEQUENTIALID()),
    TenantId        INT             NOT NULL,
    InvoiceId       INT             NOT NULL,
    InvoiceLayoutId INT             NULL,
    ReportId        INT             NOT NULL,
    FileName        NVARCHAR(260)   NOT NULL,      -- e.g. INV-2026-00042.pdf
    ContentType     NVARCHAR(100)   NOT NULL CONSTRAINT DF_InvoiceDocument_ContentType DEFAULT (N'application/pdf'),
    SizeBytes       BIGINT          NOT NULL,
    StorageKey      NVARCHAR(400)   NOT NULL,      -- e.g. tenants/{TenantId}/invoices/{InvoicePublicId}/{DocumentPublicId}.pdf
    Sha256          BINARY(32)      NULL,
    RenderedAt      DATETIME2(0)    NOT NULL CONSTRAINT DF_InvoiceDocument_RenderedAt DEFAULT (SYSUTCDATETIME()),
    RenderedBy      INT             NULL CONSTRAINT DF_InvoiceDocument_RenderedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    SentAt          DATETIME2(0)    NULL,
    SentTo          NVARCHAR(1000)  NULL,          -- addresses it was emailed to (To; CC; BCC)
    CONSTRAINT UQ_InvoiceDocument_PublicId UNIQUE (PublicId),
    CONSTRAINT UQ_InvoiceDocument_StorageKey UNIQUE (StorageKey),
    CONSTRAINT CK_InvoiceDocument_SizeBytes CHECK (SizeBytes >= 0),
    CONSTRAINT FK_InvoiceDocument_Invoice FOREIGN KEY (TenantId, InvoiceId) REFERENCES ar.Invoice (TenantId, Id),
    CONSTRAINT FK_InvoiceDocument_Layout FOREIGN KEY (TenantId, InvoiceLayoutId) REFERENCES ar.InvoiceLayout (TenantId, Id),
    CONSTRAINT FK_InvoiceDocument_Report FOREIGN KEY (ReportId) REFERENCES admin.Report (Id)
);
GO
CREATE NONCLUSTERED INDEX IX_InvoiceDocument_Invoice ON ar.InvoiceDocument (TenantId, InvoiceId, RenderedAt DESC);
