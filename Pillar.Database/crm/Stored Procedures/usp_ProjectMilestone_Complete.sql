-- Marks a MANUAL milestone complete (ready for the next invoice run), or undoes that with @Undo = 1 while it is unbilled.
-- Who may do this (project.edit) is checked by the API.
CREATE PROCEDURE crm.usp_ProjectMilestone_Complete
    @MilestoneId    INT,
    @Undo           BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @UserId   INT = CAST(SESSION_CONTEXT(N'UserId') AS INT),
            @Now DATETIME2(0) = SYSUTCDATETIME();

    UPDATE crm.ProjectBillingMilestone
    SET CompletedAt = CASE WHEN @Undo = 1 THEN NULL ELSE COALESCE(CompletedAt, @Now) END,
        CompletedBy = CASE WHEN @Undo = 1 THEN NULL ELSE COALESCE(CompletedBy, @UserId) END,
        ModifiedAt = @Now, ModifiedBy = @UserId
    WHERE TenantId = @TenantId AND Id = @MilestoneId AND TriggerType = 'MANUAL' AND InvoiceEntryId IS NULL;

    IF @@ROWCOUNT = 0 THROW 51121, N'Only unbilled MANUAL milestones can be marked complete or reopened.', 1;
END;
