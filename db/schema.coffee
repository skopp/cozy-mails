Mail = define 'Mail', ->
    property 'mailbox', String, index: true
    property 'id_remote_mailbox', index: true
    property 'createdAt', Number, default: 0, index: true
    property 'dateValueOf', Number, default: 0, index: true
    property 'date', Date, default: 0, index: true
    property 'headers_raw', Text
    property 'raw', Text
    property 'priority',
    property 'subject',
    property 'from',
    property 'to',
    property 'cc',
    property 'text', Text
    property 'html', Text
    property 'flags',
    property 'read', Boolean, default: false
    property 'flagged', Boolean, default: false
    
Attachement = define 'Attachements', ->
    property 'mail_id', Number
    property 'content_raw', Text
    
Mail.hasMany(Attachement, {as: 'attachements',  foreignKey: 'mail_id'});
    
Mailbox = define 'Mailbox', ->
    property 'new_messages', default: 0
    property 'checked', Boolean, default: true
    property 'config', Number, default: 0
    property 'name'
    property 'login'
    property 'pass'
    property 'createdAt', Date, default: Date
    property 'SMTP_server'
    property 'SMTP_send_as'
    property 'SMTP_ssl'
    property 'IMAP_server'
    property 'IMAP_port'
    property 'IMAP_secure', Boolean, default: true
    property 'IMAP_last_sync', Date, default: 0
    property 'IMAP_last_fetched_id', Number, default: 1
    property 'IMAP_last_fetched_date', Date, default: 0
    property 'status'
    property 'color', default: "#0099FF"
    property 'activated', Boolean, default: false
    
Mailbox.hasMany(Mail, {as: 'mails',  foreignKey: 'mailbox'});