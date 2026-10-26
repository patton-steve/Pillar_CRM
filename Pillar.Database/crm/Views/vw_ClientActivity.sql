-- The client Overview feed: notes plus events read live from the records themselves, so it can never drift from them.
-- Page it with WHERE TenantId/ClientId ORDER BY OccurredAt DESC. ActivityType:
--   NOTE_CALL / NOTE_MEETING / NOTE_EMAIL / NOTE_NOTE   crm.ClientNote (by its type's SystemCode)
--   PROJECT_CREATED                                     crm.ClientProject
--   INVOICE_ISSUED / INVOICE_VOIDED                     ar.Invoice
--   PAYMENT_RECEIVED / PAYMENT_VOIDED                   ar.InvoicePay
--   INVOICE_EMAILED                                     admin.EmailLog (sent invoice emails)
-- EntityType + EntityId say what a row opens (NOTE, PROJECT, INVOICE, PAYMENT). Client status changes are not tracked yet.
CREATE VIEW crm.vw_ClientActivity
AS
SELECT n.TenantId, n.ClientId, n.OccurredAt, CONVERT(VARCHAR(30), CONCAT('NOTE_', nt.SystemCode)) AS ActivityType,
       CONVERT(NVARCHAR(300), COALESCE(n.Subject, nt.Name)) AS Title, n.ContactId, CONVERT(DECIMAL(19,2), NULL) AS Amount,
       'NOTE' AS EntityType, n.Id AS EntityId, n.AuthorUserId AS ActorUserId
FROM crm.ClientNote AS n
JOIN lkp.NoteType AS nt ON nt.TenantId = n.TenantId AND nt.Id = n.NoteTypeId
WHERE n.DeletedAt IS NULL
UNION ALL
SELECT p.TenantId, p.ClientId, p.CreatedAt, 'PROJECT_CREATED', CONCAT(N'Project ', p.ProjectCode, N' ', p.Name, N' created'),
       NULL, NULL, 'PROJECT', p.Id, p.CreatedBy
FROM crm.ClientProject AS p
WHERE p.DeletedAt IS NULL
UNION ALL
SELECT i.TenantId, i.ClientId, i.IssuedAt, 'INVOICE_ISSUED', CONCAT(N'Invoice ', i.InvoiceNumber, N' issued'),
       NULL, i.Total, 'INVOICE', i.Id, i.IssuedBy
FROM ar.Invoice AS i
WHERE i.IssuedAt IS NOT NULL
UNION ALL
SELECT i.TenantId, i.ClientId, i.VoidedAt, 'INVOICE_VOIDED', CONCAT(N'Invoice ', i.InvoiceNumber, N' voided'),
       NULL, i.Total, 'INVOICE', i.Id, i.VoidedBy
FROM ar.Invoice AS i
WHERE i.VoidedAt IS NOT NULL AND i.IssuedAt IS NOT NULL
UNION ALL
SELECT p.TenantId, p.ClientId, p.CreatedAt, 'PAYMENT_RECEIVED', CONCAT(N'Payment received', N' (' + p.ReferenceNumber + N')'),
       NULL, p.Amount, 'PAYMENT', p.Id, p.CreatedBy
FROM ar.InvoicePay AS p
UNION ALL
SELECT p.TenantId, p.ClientId, p.VoidedAt, 'PAYMENT_VOIDED', CONCAT(N'Payment voided', N' (' + p.ReferenceNumber + N')'),
       NULL, p.Amount, 'PAYMENT', p.Id, p.VoidedBy
FROM ar.InvoicePay AS p
WHERE p.VoidedAt IS NOT NULL
UNION ALL
SELECT l.TenantId, i.ClientId, l.SentAt, 'INVOICE_EMAILED', LEFT(CONCAT(N'Invoice ', i.InvoiceNumber, N' emailed to ', l.ToAddresses), 300),
       NULL, i.Total, 'INVOICE', i.Id, l.QueuedBy
FROM admin.EmailLog AS l
JOIN ar.Invoice AS i ON i.TenantId = l.TenantId AND i.Id = l.EntityId
WHERE l.EntityType = 'INVOICE' AND l.Status = 'SENT';
