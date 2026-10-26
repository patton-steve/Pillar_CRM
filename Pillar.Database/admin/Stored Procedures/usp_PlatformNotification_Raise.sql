-- Puts an item in Pillar's back-office inbox (admin.PlatformNotification), emailed to the platform admins when @SendEmail = 1.
-- Called by Pillar's procs and by tenant procs (application submitted, support ticket opened or answered); needs no session.
CREATE PROCEDURE admin.usp_PlatformNotification_Raise
    @Kind           VARCHAR(30),
    @Title          NVARCHAR(200),
    @Body           NVARCHAR(2000) = NULL,
    @TenantId       INT = NULL,
    @EntityType     VARCHAR(20) = NULL,
    @EntityId       INT = NULL,
    @DataJson       NVARCHAR(MAX) = NULL,
    @SendEmail      BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO admin.PlatformNotification (Kind, TenantId, EntityType, EntityId, Title, Body, DataJson, SendEmail)
    VALUES (@Kind, @TenantId, @EntityType, @EntityId, @Title, @Body, @DataJson, @SendEmail);
END;
