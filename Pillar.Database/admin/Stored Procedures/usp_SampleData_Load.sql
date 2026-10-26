-- Setup wizard > "Try it with a sample company" (Steve 2026-10-22: no trial; a removable sample company instead). For the session
-- tenant and user: two sample clients (crm.Client.IsSample = 1) with a contact each, an hourly project per client with the session
-- user on the team at @Rate, two tasks per project, and a few draft time entries for the session user last week (skipped when
-- the tenant enters start and end times). Nothing is submitted or invoiced. admin.usp_SampleData_Remove takes it all out again.
-- Needs client.edit and project.edit (the owner has both).
CREATE PROCEDURE admin.usp_SampleData_Load
    @Rate DECIMAL(19,4) = 125
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')), @UserId INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Today DATE = CAST(SYSUTCDATETIME() AS DATE), @Monday DATE, @i INT = 1,
            @ClientId INT, @ProfileId INT, @ProjectId INT, @TaskId INT, @TaskKey VARCHAR(20), @EntryId INT, @WorkDate DATE,
            @Mode NVARCHAR(400), @ClientName NVARCHAR(200), @Contact NVARCHAR(100), @ContactLast NVARCHAR(100), @Email NVARCHAR(254),
            @ProjectName NVARCHAR(200), @Task1 NVARCHAR(200), @Task2 NVARCHAR(200), @Code NVARCHAR(20), @Budget DECIMAL(9,2),
            @Minutes INT, @Note NVARCHAR(200);

    IF @TenantId IS NULL OR @UserId IS NULL THROW 52216, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'client.edit'))
       OR NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'project.edit'))
        THROW 52283, N'You need to be able to edit clients and projects to load the sample company.', 1;
    IF EXISTS (SELECT 1 FROM crm.Client WHERE TenantId = @TenantId AND IsSample = 1 AND DeletedAt IS NULL)
        THROW 52280, N'The sample company is already loaded.', 1;

    SELECT @Mode = Value FROM admin.fn_Setting(@TenantId, @UserId, 'TimeEntry.EntryMode');
    -- Monday of last week
    SET @Monday = DATEADD(DAY, -7 - ((DATEPART(WEEKDAY, @Today) + @@DATEFIRST - 2) % 7), @Today);

    BEGIN TRAN;

    WHILE @i <= 2
    BEGIN
        SELECT @ClientName = CASE @i WHEN 1 THEN N'Northwind Dental (sample)' ELSE N'Harbor & Pine Architects (sample)' END,
               @Code = CASE @i WHEN 1 THEN N'SAMPLE-A' ELSE N'SAMPLE-B' END,
               @Contact = CASE @i WHEN 1 THEN N'Maria' ELSE N'Dev' END,
               @ContactLast = CASE @i WHEN 1 THEN N'Lopez' ELSE N'Patel' END,
               @Email = CASE @i WHEN 1 THEN N'maria.lopez@example.com' ELSE N'dev.patel@example.com' END,
               @ProjectName = CASE @i WHEN 1 THEN N'Patient portal refresh' ELSE N'Office network upgrade' END,
               @Task1 = CASE @i WHEN 1 THEN N'Review current portal' ELSE N'Site survey' END,
               @Task2 = CASE @i WHEN 1 THEN N'Design new sign-in page' ELSE N'Install new switches' END,
               @Budget = CASE @i WHEN 1 THEN 40 ELSE 80 END;

        INSERT INTO crm.Client (TenantId, ClientCode, Name, ClientTypeId, ClientStatusId, IsSample)
        SELECT @TenantId, @Code, @ClientName, ct.Id, cs.Id, 1
        FROM lkp.ClientType AS ct
        JOIN lkp.ClientStatus AS cs ON cs.TenantId = ct.TenantId AND cs.SystemCode = 'ACTIVE'
        WHERE ct.TenantId = @TenantId AND ct.SystemCode = 'BUSINESS';
        SET @ClientId = SCOPE_IDENTITY();
        IF @ClientId IS NULL THROW 52284, N'The sample company needs the BUSINESS client type and ACTIVE client status.', 1;

        INSERT INTO crm.Contact (TenantId, ClientId, FirstName, LastName, Email, IsPrimary)
        VALUES (@TenantId, @ClientId, @Contact, @ContactLast, @Email, 1);

        SELECT @ProfileId = Id FROM crm.ClientBillingProfile WHERE TenantId = @TenantId AND ClientId = @ClientId AND IsDefault = 1;

        INSERT INTO crm.ClientProject (TenantId, ClientId, BillingProfileId, ProjectCode, Name, ProjectTypeId, BillingTypeId, ProjectStatusId, BudgetHours)
        SELECT TOP (1) @TenantId, @ClientId, @ProfileId, CONCAT(@Code, N'1'), @ProjectName, pt.Id, bt.Id, ps.Id, @Budget
        FROM lkp.ProjectType AS pt
        JOIN lkp.BillingType AS bt ON bt.TenantId = pt.TenantId AND bt.SystemCode = 'HOURLY'
        JOIN lkp.ProjectStatus AS ps ON ps.TenantId = pt.TenantId AND ps.SystemCode = 'OPEN'
        WHERE pt.TenantId = @TenantId AND pt.IsActive = 1
        ORDER BY IIF(pt.Code = N'PM', 0, 1), pt.IsDefault DESC, pt.SortOrder;
        SET @ProjectId = SCOPE_IDENTITY();
        IF @ProjectId IS NULL THROW 52284, N'The sample company needs an active project type and the HOURLY and OPEN statuses.', 1;

        INSERT INTO crm.ProjectUser (TenantId, ProjectId, AppUserId) VALUES (@TenantId, @ProjectId, @UserId);
        INSERT INTO crm.ProjectRate (TenantId, ProjectId, AppUserId, Rate, EffectiveFrom)
        VALUES (@TenantId, @ProjectId, @UserId, @Rate, DATEADD(MONTH, -1, @Monday));

        SET @TaskId = NULL;
        EXEC crm.usp_ClientTask_Create @ProjectId = @ProjectId, @Title = @Task1, @AssignedUserId = @UserId, @TaskId = @TaskId OUTPUT, @TaskKey = @TaskKey OUTPUT;
        IF @Mode IS NULL OR @Mode <> N'START_END'
        BEGIN
            SELECT @WorkDate = DATEADD(DAY, @i - 1, @Monday), @Minutes = 90 + 30 * @i, @Note = CONCAT(N'Worked on: ', @Task1), @EntryId = NULL;
            EXEC crm.usp_TimeEntry_Save @TimeEntryId = @EntryId OUTPUT, @TaskId = @TaskId, @WorkDate = @WorkDate, @Minutes = @Minutes, @Description = @Note;
        END;

        SET @TaskId = NULL;
        EXEC crm.usp_ClientTask_Create @ProjectId = @ProjectId, @Title = @Task2, @AssignedUserId = @UserId, @TaskId = @TaskId OUTPUT, @TaskKey = @TaskKey OUTPUT;
        IF @Mode IS NULL OR @Mode <> N'START_END'
        BEGIN
            SELECT @WorkDate = DATEADD(DAY, @i + 1, @Monday), @Minutes = 60 * @i, @Note = CONCAT(N'Worked on: ', @Task2), @EntryId = NULL;
            EXEC crm.usp_TimeEntry_Save @TimeEntryId = @EntryId OUTPUT, @TaskId = @TaskId, @WorkDate = @WorkDate, @Minutes = @Minutes, @Description = @Note;
        END;

        SET @i += 1;
    END;

    EXEC admin.usp_Audit_Write @Area = 'company', @EntityType = 'SAMPLE_DATA', @Action = 'CREATE', @Summary = N'Loaded the sample company';
    COMMIT;

    SELECT COUNT(*) AS SampleClients FROM crm.Client WHERE TenantId = @TenantId AND IsSample = 1;
END;
