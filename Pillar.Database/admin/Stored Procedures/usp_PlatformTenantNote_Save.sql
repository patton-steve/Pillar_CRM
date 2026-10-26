-- Back office > tenant > Notes: adds a note (@NoteId NULL) or deletes one (@Delete = 1). Pillar only.
CREATE PROCEDURE admin.usp_PlatformTenantNote_Save
    @TenantId   INT,
    @Body       NVARCHAR(4000) = NULL,
    @NoteId     INT = NULL OUTPUT,
    @Delete     BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;

    IF @Delete = 1
        UPDATE admin.PlatformTenantNote SET DeletedAt = SYSUTCDATETIME() WHERE Id = @NoteId AND TenantId = @TenantId;
    ELSE
    BEGIN
        IF NULLIF(LTRIM(RTRIM(@Body)), N'') IS NULL THROW 52257, N'The note is empty.', 1;
        INSERT INTO admin.PlatformTenantNote (TenantId, Body) VALUES (@TenantId, @Body);
        SET @NoteId = SCOPE_IDENTITY();
    END;
END;
