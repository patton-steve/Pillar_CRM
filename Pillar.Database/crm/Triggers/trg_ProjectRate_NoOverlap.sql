-- One effective rate per (project, user, task type) on any date.
CREATE TRIGGER crm.trg_ProjectRate_NoOverlap
ON crm.ProjectRate
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        JOIN crm.ProjectRate AS r
          ON  r.TenantId  = i.TenantId
          AND r.ProjectId = i.ProjectId
          AND r.Id       <> i.Id
          AND ((r.AppUserId  = i.AppUserId)  OR (r.AppUserId  IS NULL AND i.AppUserId  IS NULL))
          AND ((r.TaskTypeId = i.TaskTypeId) OR (r.TaskTypeId IS NULL AND i.TaskTypeId IS NULL))
          AND r.EffectiveFrom <= ISNULL(i.EffectiveTo, '9999-12-31')
          AND i.EffectiveFrom <= ISNULL(r.EffectiveTo, '9999-12-31')
    )
        THROW 50202, N'Rate dates overlap an existing rate for the same project, user and task type. End the old rate first.', 1;
END;
