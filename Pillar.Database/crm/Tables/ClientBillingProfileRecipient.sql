-- Extra invoice email recipients for a profile. The To is the profile's BillingContactId.
-- Each row is either one of the client's contacts or a free-form address (e.g. ap@amazon.com).
CREATE TABLE crm.ClientBillingProfileRecipient
(
    Id                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ClientBillingProfileRecipient PRIMARY KEY CLUSTERED,
    TenantId            INT             NOT NULL,
    ClientId            INT             NOT NULL,
    BillingProfileId    INT             NOT NULL,
    RecipientType       VARCHAR(3)      NOT NULL,
    ContactId           INT             NULL,
    Email               NVARCHAR(254)   NULL,
    CreatedAt           DATETIME2(0)    NOT NULL CONSTRAINT DF_ClientBillingProfileRecipient_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy           INT             NULL CONSTRAINT DF_ClientBillingProfileRecipient_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt          DATETIME2(0)    NULL,
    ModifiedBy          INT             NULL,
    RowVer              ROWVERSION      NOT NULL,
    CONSTRAINT CK_ClientBillingProfileRecipient_Type CHECK (RecipientType IN ('CC', 'BCC')),
    CONSTRAINT CK_ClientBillingProfileRecipient_ContactOrEmail
        CHECK ((ContactId IS NOT NULL AND Email IS NULL) OR (ContactId IS NULL AND Email IS NOT NULL)),
    CONSTRAINT FK_ClientBillingProfileRecipient_Profile FOREIGN KEY (TenantId, ClientId, BillingProfileId)
        REFERENCES crm.ClientBillingProfile (TenantId, ClientId, Id) ON DELETE CASCADE,
    CONSTRAINT FK_ClientBillingProfileRecipient_Contact FOREIGN KEY (TenantId, ClientId, ContactId)
        REFERENCES crm.Contact (TenantId, ClientId, Id)
);
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_ClientBillingProfileRecipient_Contact
    ON crm.ClientBillingProfileRecipient (BillingProfileId, ContactId) WHERE ContactId IS NOT NULL;
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_ClientBillingProfileRecipient_Email
    ON crm.ClientBillingProfileRecipient (BillingProfileId, Email) WHERE Email IS NOT NULL;
