-- Why billable work was left out of a run (no billing contact, client not active), shown on the run review screen.
CREATE TABLE ar.InvoiceRunException
(
    Id                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_InvoiceRunException PRIMARY KEY CLUSTERED,
    TenantId            INT             NOT NULL,
    InvoiceRunId        INT             NOT NULL,
    ClientId            INT             NOT NULL,
    BillingProfileId    INT             NULL,
    ProjectId           INT             NULL,
    Reason              VARCHAR(30)     NOT NULL,
    Message             NVARCHAR(400)   NOT NULL,
    CONSTRAINT CK_InvoiceRunException_Reason CHECK (Reason IN ('NO_BILLING_CONTACT', 'CLIENT_NOT_ACTIVE')),
    CONSTRAINT FK_InvoiceRunException_Run FOREIGN KEY (TenantId, InvoiceRunId) REFERENCES ar.InvoiceRun (TenantId, Id) ON DELETE CASCADE
);
