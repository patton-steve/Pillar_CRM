-- A new project notifies the client's account manager (PROJECT_CREATED_ON_MY_CLIENT), unless they created it.
CREATE TRIGGER crm.trg_ClientProject_Notify
ON crm.ClientProject
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    IF SESSION_CONTEXT(N'TenantId') IS NULL RETURN;   -- platform-admin maintenance: no notifications

    DECLARE @ev TABLE (Seq INT IDENTITY(1,1) PRIMARY KEY, ProjectId INT, Title NVARCHAR(200));
    INSERT INTO @ev (ProjectId, Title)
    SELECT i.Id, LEFT(CONCAT(N'New project for ', c.Name, N': ', i.ProjectCode, N' ', i.Name), 200)
    FROM inserted AS i
    JOIN crm.Client AS c ON c.TenantId = i.TenantId AND c.Id = i.ClientId
    WHERE c.AccountManagerUserId IS NOT NULL;

    DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM @ev), @ProjectId INT, @Title NVARCHAR(200);
    WHILE @i <= @n
    BEGIN
        SELECT @ProjectId = ProjectId, @Title = Title FROM @ev WHERE Seq = @i;
        EXEC sec.usp_Notification_Raise @NotificationType = 'PROJECT_CREATED_ON_MY_CLIENT', @EntityType = 'PROJECT',
             @EntityId = @ProjectId, @Title = @Title;
        SET @i += 1;
    END;
END;
