-- One row per record per custom field that has a value; a blank value is no row. Exactly one Value* column (or OptionId)
-- is set, the one matching the field's DataType. RecordId is the Id of the row in the table EntityType names:
--   CLIENT crm.Client   CONTACT crm.Contact   PROJECT crm.ClientProject   TASK crm.ClientTask   VENDOR ap.Vendor   BILL ap.Bill
-- There is no FK to those tables (one column serves six); admin.usp_CustomFieldValues_Save checks the record exists.
-- Records are only ever soft-deleted, so values are never orphaned. The FK to the definition includes EntityType, so a
-- value can't attach a CLIENT field to a task. Filtered indexes per type let list pages and search filter on a value.
CREATE TABLE admin.CustomFieldValue
(
    TenantId        INT             NOT NULL,
    EntityType      VARCHAR(20)     NOT NULL,
    RecordId        INT             NOT NULL,
    FieldId         INT             NOT NULL,
    ValueText       NVARCHAR(400)   NULL,
    ValueInt        BIGINT          NULL,
    ValueDecimal    DECIMAL(19,4)   NULL,
    ValueDate       DATE            NULL,
    ValueBit        BIT             NULL,
    OptionId        INT             NULL,
    ModifiedAt      DATETIME2(0)    NOT NULL CONSTRAINT DF_CustomFieldValue_ModifiedAt DEFAULT (SYSUTCDATETIME()),
    ModifiedBy      INT             NULL CONSTRAINT DF_CustomFieldValue_ModifiedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    CONSTRAINT PK_CustomFieldValue PRIMARY KEY CLUSTERED (TenantId, EntityType, RecordId, FieldId),
    CONSTRAINT CK_CustomFieldValue_OneValue CHECK (
        (CASE WHEN ValueText IS NULL THEN 0 ELSE 1 END) + (CASE WHEN ValueInt IS NULL THEN 0 ELSE 1 END)
      + (CASE WHEN ValueDecimal IS NULL THEN 0 ELSE 1 END) + (CASE WHEN ValueDate IS NULL THEN 0 ELSE 1 END)
      + (CASE WHEN ValueBit IS NULL THEN 0 ELSE 1 END) + (CASE WHEN OptionId IS NULL THEN 0 ELSE 1 END) = 1),
    CONSTRAINT FK_CustomFieldValue_Field FOREIGN KEY (TenantId, EntityType, FieldId)
        REFERENCES admin.CustomFieldDefinition (TenantId, EntityType, Id),
    CONSTRAINT FK_CustomFieldValue_Option FOREIGN KEY (TenantId, FieldId, OptionId)
        REFERENCES admin.CustomFieldOption (TenantId, FieldId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_CustomFieldValue_Text ON admin.CustomFieldValue (TenantId, FieldId, ValueText) INCLUDE (RecordId) WHERE ValueText IS NOT NULL;
GO
CREATE NONCLUSTERED INDEX IX_CustomFieldValue_Int ON admin.CustomFieldValue (TenantId, FieldId, ValueInt) INCLUDE (RecordId) WHERE ValueInt IS NOT NULL;
GO
CREATE NONCLUSTERED INDEX IX_CustomFieldValue_Decimal ON admin.CustomFieldValue (TenantId, FieldId, ValueDecimal) INCLUDE (RecordId) WHERE ValueDecimal IS NOT NULL;
GO
CREATE NONCLUSTERED INDEX IX_CustomFieldValue_Date ON admin.CustomFieldValue (TenantId, FieldId, ValueDate) INCLUDE (RecordId) WHERE ValueDate IS NOT NULL;
GO
CREATE NONCLUSTERED INDEX IX_CustomFieldValue_Option ON admin.CustomFieldValue (TenantId, FieldId, OptionId) INCLUDE (RecordId) WHERE OptionId IS NOT NULL;
