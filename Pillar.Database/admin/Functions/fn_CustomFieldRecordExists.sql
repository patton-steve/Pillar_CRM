-- One row when @RecordId is a live (not deleted) record of @EntityType in @TenantId. Used by the custom field value procs,
-- since admin.CustomFieldValue.RecordId can't carry an FK to six different tables.
CREATE FUNCTION admin.fn_CustomFieldRecordExists (@TenantId INT, @EntityType VARCHAR(20), @RecordId INT)
RETURNS TABLE
AS
RETURN
    SELECT CONVERT(BIT, 1) AS RecordExists
    WHERE (@EntityType = 'CLIENT'  AND EXISTS (SELECT 1 FROM crm.Client        WHERE TenantId = @TenantId AND Id = @RecordId AND DeletedAt IS NULL))
       OR (@EntityType = 'CONTACT' AND EXISTS (SELECT 1 FROM crm.Contact       WHERE TenantId = @TenantId AND Id = @RecordId AND DeletedAt IS NULL))
       OR (@EntityType = 'PROJECT' AND EXISTS (SELECT 1 FROM crm.ClientProject WHERE TenantId = @TenantId AND Id = @RecordId AND DeletedAt IS NULL))
       OR (@EntityType = 'TASK'    AND EXISTS (SELECT 1 FROM crm.ClientTask    WHERE TenantId = @TenantId AND Id = @RecordId AND DeletedAt IS NULL))
       OR (@EntityType = 'VENDOR'  AND EXISTS (SELECT 1 FROM ap.Vendor         WHERE TenantId = @TenantId AND Id = @RecordId AND DeletedAt IS NULL))
       OR (@EntityType = 'BILL'    AND EXISTS (SELECT 1 FROM ap.Bill           WHERE TenantId = @TenantId AND Id = @RecordId));
