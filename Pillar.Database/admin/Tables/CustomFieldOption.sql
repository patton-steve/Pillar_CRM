-- Choices for a LIST custom field, in SortOrder. Options that have been used are retired (IsActive = 0), never deleted,
-- so old records keep showing their value. Written by admin.usp_CustomField_Save.
CREATE TABLE admin.CustomFieldOption
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CustomFieldOption PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    FieldId         INT             NOT NULL,
    Label           NVARCHAR(100)   NOT NULL,
    SortOrder       INT             NOT NULL,
    IsActive        BIT             NOT NULL CONSTRAINT DF_CustomFieldOption_IsActive DEFAULT (1),
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_CustomFieldOption_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_CustomFieldOption_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    CONSTRAINT UQ_CustomFieldOption_Tenant_Field_Id UNIQUE (TenantId, FieldId, Id),
    CONSTRAINT FK_CustomFieldOption_Field FOREIGN KEY (TenantId, FieldId) REFERENCES admin.CustomFieldDefinition (TenantId, Id)
);
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_CustomFieldOption_ActiveLabel ON admin.CustomFieldOption (TenantId, FieldId, Label) WHERE IsActive = 1;
