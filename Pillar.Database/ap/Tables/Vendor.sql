-- Businesses the tenant pays.
CREATE TABLE ap.Vendor
(
    Id                          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Vendor PRIMARY KEY CLUSTERED,
    PublicId                    UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_Vendor_PublicId DEFAULT (NEWSEQUENTIALID()),
    TenantId                    INT             NOT NULL,
    VendorCode                  NVARCHAR(20)    NOT NULL,
    Name                        NVARCHAR(200)   NOT NULL,
    ContactName                 NVARCHAR(200)   NULL,
    Email                       NVARCHAR(254)   NULL,
    Phone                       NVARCHAR(30)    NULL,
    AddressId                   INT             NULL,
    PaymentTermId               INT             NULL,      -- default for new bills
    DefaultExpenseCategoryId    INT             NULL,
    DefaultPaymentMethodId      INT             NULL,
    TaxId                       NVARCHAR(30)    NULL,
    Is1099                      BIT             NOT NULL CONSTRAINT DF_Vendor_Is1099 DEFAULT (0),
    IsActive                    BIT             NOT NULL CONSTRAINT DF_Vendor_IsActive DEFAULT (1),
    Notes                       NVARCHAR(MAX)   NULL,
    DeletedAt                   DATETIME2(0)    NULL,
    CreatedAt                   DATETIME2(0)    NOT NULL CONSTRAINT DF_Vendor_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy                   INT             NULL CONSTRAINT DF_Vendor_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt                  DATETIME2(0)    NULL,
    ModifiedBy                  INT             NULL,
    RowVer                      ROWVERSION      NOT NULL,
    CONSTRAINT UQ_Vendor_PublicId UNIQUE (PublicId),
    CONSTRAINT UQ_Vendor_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT UQ_Vendor_Tenant_Code UNIQUE (TenantId, VendorCode),
    CONSTRAINT FK_Vendor_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id),
    CONSTRAINT FK_Vendor_Address FOREIGN KEY (TenantId, AddressId) REFERENCES crm.Address (TenantId, Id),
    CONSTRAINT FK_Vendor_PaymentTerm FOREIGN KEY (TenantId, PaymentTermId) REFERENCES lkp.PaymentTerm (TenantId, Id),
    CONSTRAINT FK_Vendor_ExpenseCategory FOREIGN KEY (TenantId, DefaultExpenseCategoryId) REFERENCES lkp.ExpenseCategory (TenantId, Id),
    CONSTRAINT FK_Vendor_PaymentMethod FOREIGN KEY (TenantId, DefaultPaymentMethodId) REFERENCES lkp.PaymentMethod (TenantId, Id)
);
