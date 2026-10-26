-- People @mentioned in a task comment. Kept in step with the comment body by crm.usp_TaskComment_Save, which notifies
-- new mentions and adds them as watchers.
CREATE TABLE crm.TaskCommentMention
(
    TenantId        INT             NOT NULL,
    CommentId       INT             NOT NULL,
    AppUserId       INT             NOT NULL,
    CONSTRAINT PK_TaskCommentMention PRIMARY KEY CLUSTERED (TenantId, CommentId, AppUserId),
    CONSTRAINT FK_TaskCommentMention_Comment FOREIGN KEY (TenantId, CommentId) REFERENCES crm.TaskComment (TenantId, Id),
    CONSTRAINT FK_TaskCommentMention_AppUser FOREIGN KEY (TenantId, AppUserId) REFERENCES sec.AppUser (TenantId, Id)
);
