-- People @mentioned in a client note. Kept in step with the note body by crm.usp_ClientNote_Save, which notifies new mentions.
CREATE TABLE crm.ClientNoteMention
(
    TenantId        INT             NOT NULL,
    NoteId          INT             NOT NULL,
    AppUserId       INT             NOT NULL,
    CONSTRAINT PK_ClientNoteMention PRIMARY KEY CLUSTERED (TenantId, NoteId, AppUserId),
    CONSTRAINT FK_ClientNoteMention_Note FOREIGN KEY (TenantId, NoteId) REFERENCES crm.ClientNote (TenantId, Id),
    CONSTRAINT FK_ClientNoteMention_AppUser FOREIGN KEY (TenantId, AppUserId) REFERENCES sec.AppUser (TenantId, Id)
);
