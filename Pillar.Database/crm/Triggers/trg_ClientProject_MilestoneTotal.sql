-- A project with a milestone schedule stays FIXED and keeps FixedFeeAmount equal to the schedule's total.
-- Change both together with crm.usp_ProjectMilestone_Save @FixedFeeAmount.
CREATE TRIGGER crm.trg_ClientProject_MilestoneTotal
ON crm.ClientProject
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(FixedFeeAmount) AND NOT UPDATE(BillingTypeId) RETURN;

    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        JOIN lkp.BillingType AS bt ON bt.TenantId = i.TenantId AND bt.Id = i.BillingTypeId
        WHERE bt.SystemCode <> 'FIXED'
          AND EXISTS (SELECT 1 FROM crm.ProjectBillingMilestone AS m WHERE m.TenantId = i.TenantId AND m.ProjectId = i.Id))
        THROW 51123, N'Remove the milestone schedule before changing this project away from fixed fee.', 1;

    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        JOIN (SELECT TenantId, ProjectId, SUM(Amount) AS Total
              FROM crm.ProjectBillingMilestone GROUP BY TenantId, ProjectId) AS m
          ON m.TenantId = i.TenantId AND m.ProjectId = i.Id
        WHERE ROUND(ISNULL(i.FixedFeeAmount, 0), 2) <> m.Total)
        THROW 51122, N'The fixed fee must equal the milestone schedule. Save both with crm.usp_ProjectMilestone_Save.', 1;
END;
