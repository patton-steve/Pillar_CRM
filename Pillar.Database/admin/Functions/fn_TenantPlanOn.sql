-- The plan a tenant was on, or will be on, on @AsOf (handoff 26), from its APPLIED plan changes (admin.TenantPlanChange): the
-- latest change on or before @AsOf, else the plan the first later change moved it from, else admin.Tenant.PlanId. The monthly
-- statement splits the month the same way.
CREATE FUNCTION admin.fn_TenantPlanOn (@TenantId INT, @AsOf DATE)
RETURNS TABLE
AS
RETURN
    SELECT COALESCE(
               (SELECT TOP (1) c.ToPlanId FROM admin.TenantPlanChange AS c
                WHERE c.TenantId = t.Id AND c.Status = 'APPLIED' AND c.EffectiveDate <= @AsOf
                ORDER BY c.EffectiveDate DESC, c.Id DESC),
               (SELECT TOP (1) c.FromPlanId FROM admin.TenantPlanChange AS c
                WHERE c.TenantId = t.Id AND c.Status = 'APPLIED' AND c.EffectiveDate > @AsOf
                ORDER BY c.EffectiveDate, c.Id),
               t.PlanId) AS PlanId
    FROM admin.Tenant AS t
    WHERE t.Id = @TenantId;
