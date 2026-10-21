-- A customer account. Status, plan and branding come in the Tenant walkthrough.
-- TenantTypeId seeds starting settings at sign-up (admin.usp_SeedTenantSettings); changing it later does not reseed.
CREATE TABLE admin.Tenant
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Tenant PRIMARY KEY CLUSTERED,
    PublicId        UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_Tenant_PublicId DEFAULT (NEWSEQUENTIALID()),
    Name            NVARCHAR(200)   NOT NULL,
    TenantTypeId    INT             NOT NULL,
    PlanId          INT             NOT NULL,
    TimeZoneId      NVARCHAR(64)    NOT NULL CONSTRAINT DF_Tenant_TimeZoneId DEFAULT (N'Eastern Standard Time'),
    CurrencyCode    CHAR(3)         NOT NULL CONSTRAINT DF_Tenant_CurrencyCode DEFAULT ('USD'),
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_Tenant_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_Tenant_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_Tenant_PublicId UNIQUE (PublicId),
    CONSTRAINT FK_Tenant_TenantType FOREIGN KEY (TenantTypeId) REFERENCES admin.TenantType (Id),
    CONSTRAINT FK_Tenant_Plan FOREIGN KEY (PlanId) REFERENCES admin.[Plan] (Id)
);
