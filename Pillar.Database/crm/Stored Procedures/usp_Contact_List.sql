-- Contacts page: every contact across clients (new in handoff 23; before this, contacts were read per client). Needs
-- client.view. Filters are optional: @IsActive defaults to active only (NULL = all); @Search matches name, email, phone
-- or the client's name. @Sort NAME (default), CLIENT or RECENT. Pages with @Page (from 1) and @PageSize; TotalCount is
-- the count before paging.
CREATE PROCEDURE crm.usp_Contact_List
    @ClientId       INT = NULL,
    @ContactRoleId  INT = NULL,
    @IsPrimary      BIT = NULL,
    @IsActive       BIT = 1,
    @Search         NVARCHAR(100) = NULL,
    @Sort           VARCHAR(10) = 'NAME',
    @Page           INT = 1,
    @PageSize       INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')), @Like NVARCHAR(210);
    IF @TenantId IS NULL OR @UserId IS NULL THROW 52301, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'client.view'))
        THROW 52350, N'You need permission to view clients to see contacts.', 1;
    IF @Page IS NULL OR @Page < 1 SET @Page = 1;
    IF @PageSize IS NULL OR @PageSize < 1 OR @PageSize > 500 SET @PageSize = 50;
    IF NULLIF(LTRIM(RTRIM(@Search)), N'') IS NOT NULL
        SET @Like = N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%';

    SELECT n.Id AS ContactId, n.PublicId, n.FirstName, n.LastName, n.DisplayName, n.Title, n.Email, n.Phone, n.Mobile,
           n.ContactRoleId, r.Name AS ContactRoleName, n.IsPrimary, n.IsActive,
           c.Id AS ClientId, c.PublicId AS ClientPublicId, c.ClientCode, c.Name AS ClientName,
           n.CreatedAt, n.ModifiedAt, COUNT(*) OVER () AS TotalCount
    FROM crm.Contact AS n
    JOIN crm.Client AS c ON c.TenantId = n.TenantId AND c.Id = n.ClientId AND c.DeletedAt IS NULL
    LEFT JOIN lkp.ContactRole AS r ON r.TenantId = n.TenantId AND r.Id = n.ContactRoleId
    WHERE n.TenantId = @TenantId AND n.DeletedAt IS NULL
      AND (@ClientId IS NULL OR n.ClientId = @ClientId)
      AND (@ContactRoleId IS NULL OR n.ContactRoleId = @ContactRoleId)
      AND (@IsPrimary IS NULL OR n.IsPrimary = @IsPrimary)
      AND (@IsActive IS NULL OR n.IsActive = @IsActive)
      AND (@Like IS NULL OR n.FirstName LIKE @Like OR n.LastName LIKE @Like OR n.Email LIKE @Like OR n.Phone LIKE @Like
           OR n.Mobile LIKE @Like OR c.Name LIKE @Like)
    ORDER BY
        CASE WHEN @Sort = 'CLIENT' THEN c.Name END,
        CASE WHEN @Sort = 'RECENT' THEN COALESCE(n.ModifiedAt, n.CreatedAt) END DESC,
        n.LastName, n.FirstName, n.Id
    OFFSET (@Page - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
