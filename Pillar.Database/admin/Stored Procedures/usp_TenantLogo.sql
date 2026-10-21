-- Report dataset "Logo": the tenant's logo as a database image (one row, or no rows when none is uploaded).
-- RDL: Image Source=Database, Value =First(Fields!LogoImage.Value, "Logo"), MIMEType =First(Fields!LogoMimeType.Value, "Logo").
CREATE PROCEDURE admin.usp_TenantLogo
    @TenantId INT
AS
BEGIN
    SET NOCOUNT ON;

    EXEC sec.usp_ReportContext_Set @TenantId = @TenantId;

    SELECT b.LogoImage, b.LogoMimeType
    FROM admin.TenantBranding AS b
    WHERE b.TenantId = @TenantId AND b.LogoImage IS NOT NULL;
END;
