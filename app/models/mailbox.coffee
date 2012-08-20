Mailbox.prototype.sendMail = (data, callback) ->
  nodemailer = require "nodemailer"

  transport = nodemailer.createTransport("SMTP",
    host: @SMTP_server
    secureConnection: @SMTP_ssl
    port: 465 # port for secure SMTP
    
    auth:
      user: @login
      pass: @pass
  )

  message =
    from: @SMTP_send_as
    to: data.to
    cc: data.cc if data.cc?
    bcc: data.bcc if data.bcc?
    subject: data.subject
    headers: data.headers if data.headers?
    html: data.html
    generateTextFromHTML: true
    
    # attachments: [
    #   # String attachment
    #   fileName: "notes.txt"
    #   contents: "Some notes about this e-mail"
    #   contentType: "text/plain" # optional, would be detected from the filename
    # ,
    #   # Binary Buffer attachment
    #   fileName: "image.png"
    #   contents: new Buffer("iVBORw0KGgoAAAANSUhEUgAAABAAAAAQAQMAAAAlPW0iAAAABlBMVEUAAAD/" + "//+l2Z/dAAAAM0lEQVR4nGP4/5/h/1+G/58ZDrAz3D/McH8yw83NDDeNGe4U" + "g9C9zwz3gVLMDA/A6P9/AFGGFyjOXZtQAAAAAElFTkSuQmCC", "base64")
    #   cid: "note@node" # should be as unique as possible
    # ]

  console.log "Sending Mail"
  transport.sendMail message, (error) ->
    if error
      console.log "Error occured"
      console.log error.message
      callback error
    else
      console.log "Message sent successfully!"
      callback()

  transport.close()


      
Mailbox.prototype.toString = () ->
  "[Mailbox " + @name + " #" + @id + "]"

Mailbox.prototype.getNewMail = (limit=250, callback)->
  id = @IMAP_last_fetched_id + 1
  console.log "# Fetching mail " + @ + " | UID " + id + ':' + (id + limit)
  
  @getMail "INBOX", [['UID', id + ':' + (id + limit)]], callback

Mailbox.prototype.getAllMail = (callback) ->
  console.log "# Fetching all mail"
  @getMail "INBOX", ['ALL'], callback




Mailbox.prototype.getMail = (boxname, constraints, callback) ->

  ## dependences
  imap = require "imap"
  mailparser = require "mailparser"

  mailbox = @

  # so it looks coool, let's create a connection
  server = new imap.ImapConnection
    username: mailbox.login
    password: mailbox.pass
    host:     mailbox.IMAP_server
    port:     mailbox.IMAP_port
    secure:   mailbox.IMAP_secure
    
  server.on "alert", (alert) ->
    console.log "[SERVER ALERT]" + alert
      
  server.on "error", (error) ->
    console.log "[SERVER ERROR]" + error.toString()
    mailbox.status = error.toString()
    mailbox.save (err) ->
      callback error

  server.on "close", (error) ->
    # console.log "event close: " + error
    if error
      server.emit "error", error
    else
      mailbox.save()
  
  process.on 'uncaughtException', (err) ->
    console.error "uncaughtException"
    callback err

  emitOnErr = (err) ->
    if err
      server.emit "error", err

  # TODO - socket errors on no-internet kind of situation produces an uncatched error
  # Admittedly, it would be nice to find out why this is not being caught, wouldn't it ?
  server.connect (err) =>
  
    emitOnErr err 
    unless err
    
      server.openBox boxname, false, (err, box) ->
    
        emitOnErr err
        unless err
        
          # update number of new mails
          mailbox.new_messages = box.messages.new
      
          server.search constraints, (err, results) =>
        
            emitOnErr err
            unless err

              # nothing to download
              unless results.length
                console.log "nothing to download"
                mailbox.IMAP_last_sync = new Date().toJSON()
                mailbox.status = ""
                server.logout()
                callback()
        
              # mails to fetch
              else
                console.log "downloading mails"
          
                fetch = server.fetch results,
                  request:
                    body: "full"
                    headers: false

                fetch.on "message", (message) ->
                  parser = new mailparser.MailParser { streamAttachments: true }
        
                  parser.on "end", (m) =>
                    mail =
                      date:         new Date(m.headers.date).toJSON()
                      createdAt:    new Date().valueOf()
            
                      from:         JSON.stringify m.from
                      to:           JSON.stringify m.to
                      cc:           JSON.stringify m.cc
                      subject:      m.subject
                      priority:     m.priority
            
                      text:         m.text
                      html:         m.html
            
                      id_remote_mailbox: parser.message_id
                      flags:        JSON.stringify parser.message_flags
            
                      headers_raw:  JSON.stringify m.headers
                      raw:          JSON.stringify m
              
                      read:         "\\Seen" in parser.message_flags
                      flagged:      "\\Flagged" in parser.message_flags
              
          
                    mailbox.mails.create mail, (err, mail) ->
            
                      # ERROR
                      emitOnErr err
                      unless err
            
                        console.log "New mail created : #" + mail.id_remote_mailbox + " " + mail.id + " [" + mail.subject + "] from " + JSON.stringify mail.from
            
                        # update last fetched element
                        if mail.id_remote_mailbox > mailbox.IMAP_last_fetched_id
                          console.log "Updating the id"
                          mailbox.IMAP_last_fetched_id = mail.id_remote_mailbox
                          mailbox.IMAP_last_fetched_date = new Date().toJSON()
                          mailbox.IMAP_last_sync = new Date().toJSON()
                          mailbox.status = ""
                        
                        mailbox.save (error) ->
                          callback error

                  message.on "data", (data) ->
                    parser.write data.toString()

                  message.on "end", ->
                    parser.message_id = message.id
                    parser.message_flags = message.flags
                    do parser.end

                fetch.on "end", ->
                  do server.logout