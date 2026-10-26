-- Sign-in and account security events. Outside RLS: failed sign-ins may not match any tenant.
-- Written by the sec.usp_Auth_* procs; the API shows a tenant its own rows (TenantId filter) on the user admin screen.
CREATE TABLE sec.LoginAudit
(
    Id              BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_LoginAudit PRIMARY KEY CLUSTERED,
    OccurredAt      DATETIME2(0)    NOT NULL CONSTRAINT DF_LoginAudit_OccurredAt DEFAULT (SYSUTCDATETIME()),
    EventType       VARCHAR(20)     NOT NULL,
    Email           NVARCHAR(254)   NULL,
    TenantId        INT             NULL,
    AppUserId       INT             NULL,
    Detail          NVARCHAR(400)   NULL,
    IpAddress       VARCHAR(45)     NULL,
    UserAgent       NVARCHAR(400)   NULL,
    CONSTRAINT CK_LoginAudit_EventType CHECK (EventType IN ('LOGIN_OK', 'LOGIN_FAIL', 'MFA_FAIL', 'LOCKED', 'LOGOUT',
        'REFRESH_REUSE', 'INVITE_ACCEPTED', 'RESET_REQUESTED', 'PASSWORD_RESET', 'MFA_ENABLED', 'MFA_DISABLED', 'MFA_RECOVERY_USED',
        'EMAIL_CHANGED', 'SESSION_REVOKED', 'EMAIL_VERIFIED', 'SUPPORT_SIGNIN', 'SUPPORT_SIGNOUT'))
);
GO
CREATE NONCLUSTERED INDEX IX_LoginAudit_Tenant ON sec.LoginAudit (TenantId, OccurredAt DESC) WHERE TenantId IS NOT NULL;
GO
CREATE NONCLUSTERED INDEX IX_LoginAudit_Email ON sec.LoginAudit (Email, OccurredAt DESC);
