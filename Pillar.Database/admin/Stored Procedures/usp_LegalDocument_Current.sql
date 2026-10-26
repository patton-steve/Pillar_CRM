-- The current terms of service and privacy policy, for the sign-up page and the "updated terms" prompt (no session needed).
CREATE PROCEDURE admin.usp_LegalDocument_Current
AS
BEGIN
    SET NOCOUNT ON;

    SELECT d.Id, d.Code, d.Version, d.Title, d.Body, d.Url, d.PublishedAt, d.RequiresAcceptance
    FROM admin.LegalDocument AS d
    WHERE d.Id IN (SELECT TOP (1) x.Id FROM admin.LegalDocument AS x
                   WHERE x.Code = 'TOS' AND x.PublishedAt <= SYSUTCDATETIME() ORDER BY x.PublishedAt DESC, x.Id DESC)
       OR d.Id IN (SELECT TOP (1) x.Id FROM admin.LegalDocument AS x
                   WHERE x.Code = 'PRIVACY' AND x.PublishedAt <= SYSUTCDATETIME() ORDER BY x.PublishedAt DESC, x.Id DESC);
END;
