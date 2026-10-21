-- How and where a client is billed. A client has 1..M profiles (e.g. Amazon: AWS, Retail Ops),
-- each project bills to one profile, and an invoice belongs to exactly one profile.
-- The invoice copies terms, layout, remit, billing contact and address when created.
-- A default profile is created with each client by crm.trg_Client_CreateDefaultBillingProfile.
-- BillingContactId may be NULL until a contact exists; invoice create/issue refuses a profile without one.
CREATE TABLE crm.ClientBillingProfile
(
    Id                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ClientBillingProfile PRIMARY KEY CLUSTERED,
    PublicId            UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_ClientBillingProfile_PublicId DEFAULT (NEWSEQUENTIALID()),
    TenantId            INT             NOT NULL,
    ClientId            INT             NOT NULL,
    ProfileCode         NVARCHAR(20)    NOT NULL,
    Name                NVARCHAR(200)   NOT NULL,
    BillingContactId    INT             NULL,      -- invoice To; CC/BCC in crm.ClientBillingProfileRecipient
    BillingAddressId    INT             NULL,
    PaymentTermId       INT             NOT NULL,
    InvoiceLayoutId     INT             NULL,      -- NULL = tenant default layout
    RemitProfileId      INT             NULL,      -- NULL = tenant default remit-to
    TaxExempt           BIT             NOT NULL CONSTRAINT DF_ClientBillingProfile_TaxExempt DEFAULT (0),
    TaxExemptCertNo     NVARCHAR(50)    NULL,
    InvoiceNotes        NVARCHAR(1000)  NULL,      -- prints on every invoice for this profile
    InvoiceGrouping     VARCHAR(12)     NOT NULL CONSTRAINT DF_ClientBillingProfile_InvoiceGrouping DEFAULT ('COMBINED'),  -- or PER_PROJECT
    IsDefault           BIT             NOT NULL CONSTRAINT DF_ClientBillingProfile_IsDefault DEFAULT (0),
    IsActive            BIT             NOT NULL CONSTRAINT DF_ClientBillingProfile_IsActive DEFAULT (1),
    DeletedAt           DATETIME2(0)    NULL,
    CreatedAt           DATETIME2(0)    NOT NULL CONSTRAINT DF_ClientBillingProfile_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy           INT             NULL CONSTRAINT DF_ClientBillingProfile_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt          DATETIME2(0)    NULL,
    ModifiedBy          INT             NULL,
    RowVer              ROWVERSION      NOT NULL,
    CONSTRAINT UQ_ClientBillingProfile_PublicId UNIQUE (PublicId),
    CONSTRAINT UQ_ClientBillingProfile_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT UQ_ClientBillingProfile_Tenant_Client_Id UNIQUE (TenantId, ClientId, Id),
    CONSTRAINT UQ_ClientBillingProfile_Client_Code UNIQUE (TenantId, ClientId, ProfileCode),
    CONSTRAINT CK_ClientBillingProfile_InvoiceGrouping CHECK (InvoiceGrouping IN ('COMBINED', 'PER_PROJECT')),
    CONSTRAINT FK_ClientBillingProfile_Client FOREIGN KEY (TenantId, ClientId) REFERENCES crm.Client (TenantId, Id),
    -- contact and address must belong to this client
    CONSTRAINT FK_ClientBillingProfile_Contact FOREIGN KEY (TenantId, ClientId, BillingContactId)
        REFERENCES crm.Contact (TenantId, ClientId, Id),
    CONSTRAINT FK_ClientBillingProfile_ClientAddress FOREIGN KEY (TenantId, ClientId, BillingAddressId)
        REFERENCES crm.ClientAddress (TenantId, ClientId, AddressId),
    CONSTRAINT FK_ClientBillingProfile_PaymentTerm FOREIGN KEY (TenantId, PaymentTermId) REFERENCES lkp.PaymentTerm (TenantId, Id),
    CONSTRAINT FK_ClientBillingProfile_InvoiceLayout FOREIGN KEY (TenantId, InvoiceLayoutId) REFERENCES ar.InvoiceLayout (TenantId, Id),
    CONSTRAINT FK_ClientBillingProfile_RemitProfile FOREIGN KEY (TenantId, RemitProfileId) REFERENCES admin.RemitProfile (TenantId, Id)
);
GO
-- At most one default profile per client; the client insert trigger supplies the first.
CREATE UNIQUE NONCLUSTERED INDEX UX_ClientBillingProfile_Default
    ON crm.ClientBillingProfile (TenantId, ClientId) WHERE IsDefault = 1 AND DeletedAt IS NULL;
