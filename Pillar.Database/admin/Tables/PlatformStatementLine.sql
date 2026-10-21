-- Lines on a platform statement. FEE and REVERSAL lines point at their admin.PlatformFee row and snapshot the client invoice
-- (number, client, date) so the statement reads the same forever. MINIMUM tops the month up to the monthly minimum;
-- CREDIT carries a negative balance forward from the prior statement.
CREATE TABLE admin.PlatformStatementLine
(
    Id                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PlatformStatementLine PRIMARY KEY CLUSTERED,
    TenantId            INT             NOT NULL,
    StatementId         INT             NOT NULL,
    LineNumber          INT             NOT NULL,
    LineType            VARCHAR(10)     NOT NULL,
    PlatformFeeId       INT             NULL,
    InvoiceId           INT             NULL,
    InvoiceNumber       NVARCHAR(50)    NULL,
    ClientName          NVARCHAR(200)   NULL,
    InvoiceDate         DATE            NULL,
    Description         NVARCHAR(200)   NOT NULL,
    FeeBaseAmount       DECIMAL(19,2)   NULL,
    FeeRate             DECIMAL(9,6)    NULL,
    Amount              DECIMAL(19,2)   NOT NULL,
    CONSTRAINT UQ_PlatformStatementLine_Statement_Line UNIQUE (TenantId, StatementId, LineNumber),
    CONSTRAINT CK_PlatformStatementLine_LineType CHECK (LineType IN ('FEE', 'REVERSAL', 'MINIMUM', 'CREDIT')),
    CONSTRAINT FK_PlatformStatementLine_Statement FOREIGN KEY (TenantId, StatementId) REFERENCES admin.PlatformStatement (TenantId, Id),
    CONSTRAINT FK_PlatformStatementLine_Fee FOREIGN KEY (PlatformFeeId) REFERENCES admin.PlatformFee (Id)
);
GO
CREATE NONCLUSTERED INDEX IX_PlatformStatementLine_Fee ON admin.PlatformStatementLine (PlatformFeeId) WHERE PlatformFeeId IS NOT NULL;
