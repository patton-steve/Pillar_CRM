-- Who accepted which terms of service version, when and from where (sec.usp_Legal_Accept, and sign-up).
CREATE TABLE sec.UserLegalAcceptance
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_UserLegalAcceptance PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    AppUserId       INT             NOT NULL,
    DocumentId      INT             NOT NULL,
    AcceptedAt      DATETIME2(0)    NOT NULL CONSTRAINT DF_UserLegalAcceptance_AcceptedAt DEFAULT (SYSUTCDATETIME()),
    IpAddress       VARCHAR(45)     NULL,
    UserAgent       NVARCHAR(400)   NULL,
    CONSTRAINT UQ_UserLegalAcceptance_User_Document UNIQUE (TenantId, AppUserId, DocumentId),
    CONSTRAINT FK_UserLegalAcceptance_AppUser FOREIGN KEY (TenantId, AppUserId) REFERENCES sec.AppUser (TenantId, Id),
    CONSTRAINT FK_UserLegalAcceptance_Document FOREIGN KEY (DocumentId) REFERENCES admin.LegalDocument (Id)
);
