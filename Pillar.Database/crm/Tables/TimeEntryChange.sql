-- Log of edits an approver made to approved time (crm.usp_TimeEntry_Update). One row per save, with the required reason
-- and one chip per field that changed, in display values (same shape as TaskComment.ChangeJson):
--   [{"field":"Hours","from":"2 h","to":"1.5 h"}, {"field":"Billable","from":"Yes","to":"No"}]
CREATE TABLE crm.TimeEntryChange
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TimeEntryChange PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    TimeEntryId     INT             NOT NULL,
    ChangedBy       INT             NULL CONSTRAINT DF_TimeEntryChange_ChangedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ChangedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_TimeEntryChange_ChangedAt DEFAULT (SYSUTCDATETIME()),
    Reason          NVARCHAR(500)   NOT NULL,
    ChangeJson      NVARCHAR(MAX)   NOT NULL,
    CONSTRAINT UQ_TimeEntryChange_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT CK_TimeEntryChange_ChangeJson CHECK (ISJSON(ChangeJson) = 1),
    CONSTRAINT FK_TimeEntryChange_TimeEntry FOREIGN KEY (TenantId, TimeEntryId) REFERENCES crm.TimeEntry (TenantId, Id),
    CONSTRAINT FK_TimeEntryChange_ChangedBy FOREIGN KEY (TenantId, ChangedBy) REFERENCES sec.AppUser (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_TimeEntryChange_Entry ON crm.TimeEntryChange (TenantId, TimeEntryId, ChangedAt);
