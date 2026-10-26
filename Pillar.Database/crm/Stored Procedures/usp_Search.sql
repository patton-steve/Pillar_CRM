-- Global search (Ctrl K) and the nav search icons (@Types = one type). Up to @Top hits per type, best first, as rows:
--   ResultType  CLIENT, CONTACT, PROJECT, TASK, INVOICE, BILL, VENDOR, TASK_COMMENT, CLIENT_NOTE
--   EntityId / PublicId   the record; ParentPublicId the page to open for a contact, comment or note (client or task)
--   Title, Subtitle, Snippet (matched text from a description, comment or note; HTML for rich text, which the API strips)
--   Rank        100 exact key or number, 80 starts with, 60 in the name, 40 elsewhere, 30 in comment or note text
-- RLS limits it to the tenant; permissions limit the types: clients, contacts and notes need client.view; projects, tasks
-- and comments need project.view; invoices need invoice.view; bills and vendors need ap.view (a person always finds their
-- own expense reports). Types the person can't see are skipped, not refused.
-- Matching is LIKE, not full-text (handoff 23): SQL Server 2019 Express has full-text only with Advanced Services, and a
-- FULLTEXT index in the dacpac would fail to publish there. Revisit on Azure SQL. Recent items come from sec.UserRecentItem.
CREATE PROCEDURE crm.usp_Search
    @Query      NVARCHAR(200),
    @Types      VARCHAR(200) = NULL,
    @Top        INT = 5
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Q NVARCHAR(200) = LTRIM(RTRIM(@Query)), @Esc NVARCHAR(400), @Like NVARCHAR(402), @Prefix NVARCHAR(401),
            @Client BIT = 0, @Project BIT = 0, @Invoice BIT = 0, @Ap BIT = 0;
    IF @TenantId IS NULL OR @UserId IS NULL THROW 52301, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF @Q IS NULL OR LEN(@Q) < 2 THROW 52340, N'Type at least two characters to search.', 1;
    IF @Top IS NULL OR @Top < 1 OR @Top > 50 SET @Top = 5;

    DECLARE @Type TABLE (Code VARCHAR(20) PRIMARY KEY);
    IF @Types IS NULL
        INSERT INTO @Type (Code) VALUES ('CLIENT'), ('CONTACT'), ('PROJECT'), ('TASK'), ('INVOICE'), ('BILL'), ('VENDOR'),
                                        ('TASK_COMMENT'), ('CLIENT_NOTE');
    ELSE
        INSERT INTO @Type (Code)
        SELECT DISTINCT UPPER(LTRIM(RTRIM(value))) FROM STRING_SPLIT(@Types, ',') WHERE LTRIM(RTRIM(value)) <> '';
    IF EXISTS (SELECT 1 FROM @Type WHERE NOT (Code = 'CLIENT' OR Code = 'CONTACT' OR Code = 'PROJECT' OR Code = 'TASK'
               OR Code = 'INVOICE' OR Code = 'BILL' OR Code = 'VENDOR' OR Code = 'TASK_COMMENT' OR Code = 'CLIENT_NOTE'))
        THROW 52341, N'Types are CLIENT, CONTACT, PROJECT, TASK, INVOICE, BILL, VENDOR, TASK_COMMENT and CLIENT_NOTE.', 1;

    SELECT @Client  = MAX(IIF(PermissionCode = 'client.view', 1, 0)),
           @Project = MAX(IIF(PermissionCode = 'project.view', 1, 0)),
           @Invoice = MAX(IIF(PermissionCode = 'invoice.view', 1, 0)),
           @Ap      = MAX(IIF(PermissionCode = 'ap.view', 1, 0))
    FROM sec.fn_UserPermissions(@TenantId, @UserId);

    -- LIKE wildcards in the query are literal
    SET @Esc = REPLACE(REPLACE(REPLACE(@Q, N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]');
    SELECT @Like = N'%' + @Esc + N'%', @Prefix = @Esc + N'%';

    DECLARE @Hit TABLE (ResultType VARCHAR(20), SortGroup INT, EntityId INT, PublicId UNIQUEIDENTIFIER, ParentPublicId UNIQUEIDENTIFIER,
                        Title NVARCHAR(400), Subtitle NVARCHAR(400), Snippet NVARCHAR(400), Rank INT, ItemDate DATETIME2(0));

    IF @Client = 1 AND EXISTS (SELECT 1 FROM @Type WHERE Code = 'CLIENT')
        INSERT INTO @Hit
        SELECT TOP (@Top) 'CLIENT', 1, c.Id, c.PublicId, NULL, c.Name, c.ClientCode, NULL,
               CASE WHEN c.ClientCode = @Q THEN 100 WHEN c.Name LIKE @Prefix OR c.ClientCode LIKE @Prefix THEN 80 ELSE 60 END, c.CreatedAt
        FROM crm.Client AS c
        WHERE c.TenantId = @TenantId AND c.DeletedAt IS NULL AND (c.Name LIKE @Like OR c.ClientCode LIKE @Like)
        ORDER BY 9 DESC, c.Name;

    IF @Client = 1 AND EXISTS (SELECT 1 FROM @Type WHERE Code = 'CONTACT')
        INSERT INTO @Hit
        SELECT TOP (@Top) 'CONTACT', 2, n.Id, n.PublicId, c.PublicId, n.DisplayName, CONCAT_WS(N' - ', c.Name, n.Email), NULL,
               CASE WHEN n.Email = @Q THEN 100 WHEN n.FirstName LIKE @Prefix OR n.LastName LIKE @Prefix THEN 80
                    WHEN n.DisplayName LIKE @Like THEN 60 ELSE 40 END, n.CreatedAt
        FROM crm.Contact AS n
        JOIN crm.Client AS c ON c.TenantId = n.TenantId AND c.Id = n.ClientId AND c.DeletedAt IS NULL
        WHERE n.TenantId = @TenantId AND n.DeletedAt IS NULL
          AND (n.DisplayName LIKE @Like OR n.Email LIKE @Like OR n.Phone LIKE @Like OR n.Mobile LIKE @Like)
        ORDER BY 9 DESC, n.LastName, n.FirstName;

    IF @Project = 1 AND EXISTS (SELECT 1 FROM @Type WHERE Code = 'PROJECT')
        INSERT INTO @Hit
        SELECT TOP (@Top) 'PROJECT', 3, p.Id, p.PublicId, c.PublicId, p.Name, CONCAT_WS(N' - ', p.ProjectCode, c.Name),
               IIF(p.Name LIKE @Like OR p.ProjectCode LIKE @Like, NULL,
                   SUBSTRING(p.Description, IIF(CHARINDEX(@Q, p.Description) > 60, CHARINDEX(@Q, p.Description) - 60, 1), 200)),
               CASE WHEN p.ProjectCode = @Q THEN 100 WHEN p.Name LIKE @Prefix OR p.ProjectCode LIKE @Prefix THEN 80
                    WHEN p.Name LIKE @Like OR p.ProjectCode LIKE @Like THEN 60 ELSE 40 END, p.CreatedAt
        FROM crm.ClientProject AS p
        JOIN crm.Client AS c ON c.TenantId = p.TenantId AND c.Id = p.ClientId
        WHERE p.TenantId = @TenantId AND p.DeletedAt IS NULL
          AND (p.Name LIKE @Like OR p.ProjectCode LIKE @Like OR p.Description LIKE @Like)
        ORDER BY 9 DESC, p.Name;

    IF @Project = 1 AND EXISTS (SELECT 1 FROM @Type WHERE Code = 'TASK')
        INSERT INTO @Hit
        SELECT TOP (@Top) 'TASK', 4, t.Id, t.PublicId, p.PublicId, CONCAT(t.TaskKey, N' ', t.Title), p.Name,
               IIF(t.Title LIKE @Like OR t.TaskKey LIKE @Like, NULL,
                   SUBSTRING(t.Description, IIF(CHARINDEX(@Q, t.Description) > 60, CHARINDEX(@Q, t.Description) - 60, 1), 200)),
               CASE WHEN t.TaskKey = @Q THEN 100 WHEN t.Title LIKE @Prefix OR t.TaskKey LIKE @Prefix THEN 80
                    WHEN t.Title LIKE @Like THEN 60 ELSE 40 END, t.CreatedAt
        FROM crm.ClientTask AS t
        JOIN crm.ClientProject AS p ON p.TenantId = t.TenantId AND p.Id = t.ProjectId AND p.DeletedAt IS NULL
        WHERE t.TenantId = @TenantId AND t.DeletedAt IS NULL
          AND (t.TaskKey = @Q OR t.TaskKey LIKE @Prefix OR t.Title LIKE @Like OR t.Description LIKE @Like)
        ORDER BY 9 DESC, t.TaskNumber DESC;

    IF @Invoice = 1 AND EXISTS (SELECT 1 FROM @Type WHERE Code = 'INVOICE')
        INSERT INTO @Hit
        SELECT TOP (@Top) 'INVOICE', 5, i.Id, i.PublicId, c.PublicId, COALESCE(i.InvoiceNumber, N'Draft invoice'),
               CONCAT_WS(N' - ', COALESCE(i.ClientName, c.Name), s.Name, FORMAT(i.Total, 'N2', 'en-US')), NULL,
               CASE WHEN i.InvoiceNumber = @Q THEN 100 WHEN i.InvoiceNumber LIKE @Prefix THEN 80 WHEN i.PoNumber LIKE @Like THEN 60 ELSE 40 END,
               i.CreatedAt
        FROM ar.Invoice AS i
        JOIN crm.Client AS c ON c.TenantId = i.TenantId AND c.Id = i.ClientId
        JOIN lkp.InvoiceStatus AS s ON s.TenantId = i.TenantId AND s.Id = i.InvoiceStatusId
        WHERE i.TenantId = @TenantId
          AND (i.InvoiceNumber LIKE @Like OR i.PoNumber LIKE @Like OR i.ClientName LIKE @Like OR c.Name LIKE @Like)
        ORDER BY 9 DESC, i.Id DESC;

    IF EXISTS (SELECT 1 FROM @Type WHERE Code = 'BILL')
        INSERT INTO @Hit
        SELECT TOP (@Top) 'BILL', 6, b.Id, b.PublicId, NULL, b.BillNumber,
               CONCAT_WS(N' - ', COALESCE(v.Name, u.DisplayName), b.VendorInvoiceNumber, s.Name, FORMAT(b.Total, 'N2', 'en-US')), NULL,
               CASE WHEN b.BillNumber = @Q OR b.VendorInvoiceNumber = @Q THEN 100
                    WHEN b.BillNumber LIKE @Prefix OR b.VendorInvoiceNumber LIKE @Prefix THEN 80 ELSE 40 END, b.CreatedAt
        FROM ap.Bill AS b
        JOIN lkp.BillStatus AS s ON s.TenantId = b.TenantId AND s.Id = b.BillStatusId
        LEFT JOIN ap.Vendor AS v ON v.TenantId = b.TenantId AND v.Id = b.VendorId
        LEFT JOIN sec.AppUser AS u ON u.TenantId = b.TenantId AND u.Id = b.PayeeUserId
        WHERE b.TenantId = @TenantId AND (@Ap = 1 OR b.PayeeUserId = @UserId)
          AND (b.BillNumber LIKE @Like OR b.VendorInvoiceNumber LIKE @Like OR b.Description LIKE @Like OR v.Name LIKE @Like OR u.DisplayName LIKE @Like)
        ORDER BY 9 DESC, b.Id DESC;

    IF @Ap = 1 AND EXISTS (SELECT 1 FROM @Type WHERE Code = 'VENDOR')
        INSERT INTO @Hit
        SELECT TOP (@Top) 'VENDOR', 7, v.Id, v.PublicId, NULL, v.Name, CONCAT_WS(N' - ', v.VendorCode, v.ContactName), NULL,
               CASE WHEN v.VendorCode = @Q THEN 100 WHEN v.Name LIKE @Prefix OR v.VendorCode LIKE @Prefix THEN 80
                    WHEN v.Name LIKE @Like THEN 60 ELSE 40 END, v.CreatedAt
        FROM ap.Vendor AS v
        WHERE v.TenantId = @TenantId AND v.DeletedAt IS NULL
          AND (v.Name LIKE @Like OR v.VendorCode LIKE @Like OR v.ContactName LIKE @Like)
        ORDER BY 9 DESC, v.Name;

    IF @Project = 1 AND EXISTS (SELECT 1 FROM @Type WHERE Code = 'TASK_COMMENT')
        INSERT INTO @Hit
        SELECT TOP (@Top) 'TASK_COMMENT', 8, m.Id, NULL, t.PublicId, CONCAT(t.TaskKey, N' ', t.Title), a.DisplayName,
               SUBSTRING(m.Body, IIF(CHARINDEX(@Q, m.Body) > 60, CHARINDEX(@Q, m.Body) - 60, 1), 200), 30, m.CreatedAt
        FROM crm.TaskComment AS m
        JOIN crm.ClientTask AS t ON t.TenantId = m.TenantId AND t.Id = m.TaskId AND t.DeletedAt IS NULL
        LEFT JOIN sec.AppUser AS a ON a.TenantId = m.TenantId AND a.Id = m.AuthorUserId
        WHERE m.TenantId = @TenantId AND m.DeletedAt IS NULL AND m.Body LIKE @Like
        ORDER BY m.CreatedAt DESC;

    IF @Client = 1 AND EXISTS (SELECT 1 FROM @Type WHERE Code = 'CLIENT_NOTE')
        INSERT INTO @Hit
        SELECT TOP (@Top) 'CLIENT_NOTE', 9, n.Id, n.PublicId, c.PublicId, COALESCE(n.Subject, nt.Name), CONCAT_WS(N' - ', c.Name, a.DisplayName),
               IIF(n.Body LIKE @Like, SUBSTRING(n.Body, IIF(CHARINDEX(@Q, n.Body) > 60, CHARINDEX(@Q, n.Body) - 60, 1), 200), NULL),
               IIF(n.Subject LIKE @Like, 60, 30), n.OccurredAt
        FROM crm.ClientNote AS n
        JOIN crm.Client AS c ON c.TenantId = n.TenantId AND c.Id = n.ClientId AND c.DeletedAt IS NULL
        JOIN lkp.NoteType AS nt ON nt.TenantId = n.TenantId AND nt.Id = n.NoteTypeId
        LEFT JOIN sec.AppUser AS a ON a.TenantId = n.TenantId AND a.Id = n.AuthorUserId
        WHERE n.TenantId = @TenantId AND n.DeletedAt IS NULL AND (n.Subject LIKE @Like OR n.Body LIKE @Like)
        ORDER BY 9 DESC, n.OccurredAt DESC;

    SELECT ResultType, EntityId, PublicId, ParentPublicId, Title, Subtitle, Snippet, Rank, ItemDate
    FROM @Hit
    ORDER BY SortGroup, Rank DESC, ItemDate DESC;
END;
