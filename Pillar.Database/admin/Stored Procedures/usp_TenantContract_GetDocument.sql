-- The signed contract file stored on one contract row, for download (Pillar staff, handoff 26).
CREATE PROCEDURE admin.usp_TenantContract_GetDocument
    @ContractId INT
AS
BEGIN
    SET NOCOUNT ON;
    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;
    SELECT Id AS ContractId, TenantId, DocumentName, DocumentContentType, DocumentContent, DocumentUrl
    FROM admin.TenantContract WHERE Id = @ContractId;
END;
