-- Creates a task and assigns its TaskKey (<project type KeyPrefix>-<next number for that prefix>).
-- Tenant comes from SESSION_CONTEXT; assignee, reporter and CreatedBy default to SESSION_CONTEXT UserId.
-- Status and priority default to the tenant's IsDefault values; IsBillable defaults from the project.
CREATE PROCEDURE crm.usp_ClientTask_Create
    @ProjectId          INT,
    @Title              NVARCHAR(200),
    @Description        NVARCHAR(MAX) = NULL,
    @TaskTypeId         INT = NULL,
    @TaskStatusId       INT = NULL,
    @TaskPriorityId     INT = NULL,
    @AssignedUserId     INT = NULL,
    @EstimatedHours     DECIMAL(9,2) = NULL,
    @StartDate          DATE = NULL,
    @DueDate            DATE = NULL,
    @IsBillable         BIT = NULL,
    @TaskId             INT = NULL OUTPUT,
    @TaskKey            VARCHAR(20) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @UserId   INT = CAST(SESSION_CONTEXT(N'UserId') AS INT),
            @Prefix   VARCHAR(10),
            @SeqKey   VARCHAR(30),
            @Number   INT;

    IF @TenantId IS NULL THROW 50301, N'SESSION_CONTEXT TenantId is not set.', 1;

    SELECT @Prefix     = pt.KeyPrefix,
           @IsBillable = COALESCE(@IsBillable, p.IsBillable)
    FROM crm.ClientProject AS p
    JOIN lkp.ProjectType AS pt ON pt.TenantId = p.TenantId AND pt.Id = p.ProjectTypeId
    WHERE p.TenantId = @TenantId AND p.Id = @ProjectId AND p.DeletedAt IS NULL;

    IF @Prefix IS NULL THROW 50302, N'Project not found.', 1;

    SET @TaskStatusId = COALESCE(@TaskStatusId,
        (SELECT TOP (1) Id FROM lkp.TaskStatus WHERE TenantId = @TenantId AND IsActive = 1 ORDER BY IsDefault DESC, SortOrder, Id));
    SET @TaskPriorityId = COALESCE(@TaskPriorityId,
        (SELECT Id FROM lkp.TaskPriority WHERE TenantId = @TenantId AND IsActive = 1 AND IsDefault = 1));
    SET @AssignedUserId = COALESCE(@AssignedUserId, @UserId);
    SET @SeqKey = 'TASK:' + @Prefix;

    BEGIN TRAN;

    EXEC admin.usp_NextNumber @TenantId = @TenantId, @SequenceKey = @SeqKey, @Count = 1, @FirstValue = @Number OUTPUT;
    SET @TaskKey = @Prefix + '-' + CAST(@Number AS VARCHAR(10));

    INSERT INTO crm.ClientTask
        (TenantId, ProjectId, TaskKey, TaskNumber, Title, Description, TaskTypeId, TaskStatusId, TaskPriorityId,
         AssignedUserId, EstimatedHours, StartDate, DueDate, IsBillable)
    VALUES
        (@TenantId, @ProjectId, @TaskKey, @Number, @Title, @Description, @TaskTypeId, @TaskStatusId, @TaskPriorityId,
         @AssignedUserId, @EstimatedHours, @StartDate, @DueDate, @IsBillable);

    SET @TaskId = SCOPE_IDENTITY();

    COMMIT;
END;
