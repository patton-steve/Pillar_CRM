-- What a project still needs, per the tenant's setup checks (admin.ProjectSetupCheck, levels in
-- admin.TenantProjectSetupCheck). One row per failing check that is WARN or BLOCK for this tenant and applies to the
-- project's billing type. No BLOCK rows = ready: tasks can be added (crm.usp_ClientTask_Create) and the project can
-- leave PLANNED (crm.trg_ClientProject_SetupGate). Conditions:
--   TEAM                    no active crm.ProjectUser
--   RATE                    no DefaultRate and no crm.ProjectRate
--   BUDGET                  neither BudgetHours nor BudgetAmount
--   FEE                     no FixedFeeAmount
--   MILESTONES              no billing schedule (crm.ProjectBillingMilestone; the save proc keeps it equal to the fee)
--   PROJECT_MANAGER         no ProjectManagerUserId
--   START_DATE / END_DATE   no StartDate / EndDate
--   PO_NUMBER               no PoNumber
--   BILLING_CONTACT         the project's billing profile has no billing contact
--   REQUIRED_CUSTOM_FIELDS  an active required PROJECT custom field has no value
CREATE FUNCTION crm.fn_ProjectSetupIssues (@TenantId INT, @ProjectId INT)
RETURNS TABLE
AS
RETURN
    SELECT c.Code, c.Name, lv.Level AS Severity, c.Message, c.SortOrder
    FROM crm.ClientProject AS p
    JOIN lkp.BillingType AS bt ON bt.TenantId = p.TenantId AND bt.Id = p.BillingTypeId
    CROSS JOIN admin.ProjectSetupCheck AS c
    LEFT JOIN admin.TenantProjectSetupCheck AS t ON t.TenantId = p.TenantId AND t.CheckCode = c.Code
    CROSS APPLY (SELECT COALESCE(t.Level, c.DefaultLevel) AS Level) AS lv
    WHERE p.TenantId = @TenantId AND p.Id = @ProjectId
      AND lv.Level <> 'OFF'
      AND (c.AppliesTo = 'ALL' OR CONCAT(',', c.AppliesTo, ',') LIKE CONCAT('%,', bt.SystemCode, ',%'))
      AND 1 = CASE c.Code
          WHEN 'TEAM' THEN IIF(EXISTS (SELECT 1 FROM crm.ProjectUser AS u WHERE u.TenantId = p.TenantId AND u.ProjectId = p.Id AND u.IsActive = 1), 0, 1)
          WHEN 'RATE' THEN IIF(p.DefaultRate IS NULL
                               AND NOT EXISTS (SELECT 1 FROM crm.ProjectRate AS r WHERE r.TenantId = p.TenantId AND r.ProjectId = p.Id), 1, 0)
          WHEN 'BUDGET' THEN IIF(p.BudgetHours IS NULL AND p.BudgetAmount IS NULL, 1, 0)
          WHEN 'FEE' THEN IIF(p.FixedFeeAmount IS NULL, 1, 0)
          WHEN 'MILESTONES' THEN IIF(EXISTS (SELECT 1 FROM crm.ProjectBillingMilestone AS m WHERE m.TenantId = p.TenantId AND m.ProjectId = p.Id), 0, 1)
          WHEN 'PROJECT_MANAGER' THEN IIF(p.ProjectManagerUserId IS NULL, 1, 0)
          WHEN 'START_DATE' THEN IIF(p.StartDate IS NULL, 1, 0)
          WHEN 'END_DATE' THEN IIF(p.EndDate IS NULL, 1, 0)
          WHEN 'PO_NUMBER' THEN IIF(NULLIF(LTRIM(RTRIM(p.PoNumber)), N'') IS NULL, 1, 0)
          WHEN 'BILLING_CONTACT' THEN IIF(EXISTS (SELECT 1 FROM crm.ClientBillingProfile AS b
                                                  WHERE b.TenantId = p.TenantId AND b.Id = p.BillingProfileId AND b.BillingContactId IS NOT NULL), 0, 1)
          WHEN 'REQUIRED_CUSTOM_FIELDS' THEN IIF(EXISTS (
                  SELECT 1 FROM admin.CustomFieldDefinition AS d
                  WHERE d.TenantId = p.TenantId AND d.EntityType = 'PROJECT' AND d.IsActive = 1 AND d.IsRequired = 1
                    AND NOT EXISTS (SELECT 1 FROM admin.CustomFieldValue AS v
                                    WHERE v.TenantId = d.TenantId AND v.EntityType = 'PROJECT' AND v.RecordId = p.Id AND v.FieldId = d.Id)), 1, 0)
          ELSE 0 END;
