-- Tenant-defined extra fields on a record type (Steve 2026-10-21), shown in a "Custom fields" section on that record's page
-- when the tenant has any. Values live in admin.CustomFieldValue, one typed column per DataType:
--   TEXT     ValueText (MaxLength 1-400)     INT   ValueInt (BIGINT)     DECIMAL  ValueDecimal
--   DATE     ValueDate                       BIT   ValueBit (yes/no)     LIST     OptionId (admin.CustomFieldOption)
-- FieldKey is the stable name the API and reports use; Label is what people see and can change. Retire a field with
-- IsActive = 0: it disappears from pages but keeps its values. EntityType, FieldKey and DataType never change once saved.
-- Write only through admin.usp_CustomField_Save / usp_CustomField_Reorder (settings.custom_fields).
CREATE TABLE admin.CustomFieldDefinition
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CustomFieldDefinition PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    EntityType      VARCHAR(20)     NOT NULL,
    FieldKey        VARCHAR(50)     NOT NULL,      -- lower_snake_case, e.g. po_reference
    Label           NVARCHAR(100)   NOT NULL,
    DataType        VARCHAR(10)     NOT NULL,
    MaxLength       INT             NULL,          -- TEXT only
    IsRequired      BIT             NOT NULL CONSTRAINT DF_CustomFieldDefinition_IsRequired DEFAULT (0),
    SortOrder       INT             NOT NULL,
    IsActive        BIT             NOT NULL CONSTRAINT DF_CustomFieldDefinition_IsActive DEFAULT (1),
    HelpText        NVARCHAR(400)   NULL,
    ShowInList      BIT             NOT NULL CONSTRAINT DF_CustomFieldDefinition_ShowInList DEFAULT (0),  -- offered as a list-page column and filter
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_CustomFieldDefinition_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_CustomFieldDefinition_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_CustomFieldDefinition_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT UQ_CustomFieldDefinition_Tenant_Entity_Id UNIQUE (TenantId, EntityType, Id),
    CONSTRAINT UQ_CustomFieldDefinition_Key UNIQUE (TenantId, EntityType, FieldKey),
    CONSTRAINT CK_CustomFieldDefinition_EntityType CHECK (
        EntityType = 'CLIENT' OR EntityType = 'CONTACT' OR EntityType = 'PROJECT'
     OR EntityType = 'TASK' OR EntityType = 'VENDOR' OR EntityType = 'BILL'),
    CONSTRAINT CK_CustomFieldDefinition_FieldKey CHECK (FieldKey LIKE '[a-z]%' AND FieldKey NOT LIKE '%[^a-z0-9_]%'),
    CONSTRAINT CK_CustomFieldDefinition_DataType CHECK (
        (DataType = 'TEXT' AND MaxLength >= 1 AND MaxLength <= 400)
     OR ((DataType = 'INT' OR DataType = 'DECIMAL' OR DataType = 'DATE' OR DataType = 'BIT' OR DataType = 'LIST') AND MaxLength IS NULL))
);
GO
CREATE NONCLUSTERED INDEX IX_CustomFieldDefinition_Entity ON admin.CustomFieldDefinition (TenantId, EntityType, SortOrder)
    INCLUDE (FieldKey, Label, DataType, IsRequired, ShowInList) WHERE IsActive = 1;
