-- Receipts and vendor invoice scans, for a bill or one of its lines. Files live in blob storage under StorageKey.
CREATE TABLE ap.BillAttachment
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_BillAttachment PRIMARY KEY CLUSTERED,
    PublicId        UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_BillAttachment_PublicId DEFAULT (NEWSEQUENTIALID()),
    TenantId        INT             NOT NULL,
    BillId          INT             NOT NULL,
    BillLineId      INT             NULL,
    FileName        NVARCHAR(260)   NOT NULL,
    ContentType     NVARCHAR(100)   NOT NULL,
    SizeBytes       BIGINT          NOT NULL,
    StorageKey      NVARCHAR(400)   NOT NULL,
    Sha256          BINARY(32)      NULL,
    UploadedBy      INT             NULL CONSTRAINT DF_BillAttachment_UploadedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    UploadedAt      DATETIME2(0)    NOT NULL CONSTRAINT DF_BillAttachment_UploadedAt DEFAULT (SYSUTCDATETIME()),
    DeletedAt       DATETIME2(0)    NULL,
    CONSTRAINT UQ_BillAttachment_PublicId UNIQUE (PublicId),
    CONSTRAINT UQ_BillAttachment_StorageKey UNIQUE (StorageKey),
    CONSTRAINT CK_BillAttachment_SizeBytes CHECK (SizeBytes >= 0),
    CONSTRAINT FK_BillAttachment_Bill FOREIGN KEY (TenantId, BillId) REFERENCES ap.Bill (TenantId, Id),
    CONSTRAINT FK_BillAttachment_Line FOREIGN KEY (TenantId, BillLineId) REFERENCES ap.BillLine (TenantId, Id)
);
