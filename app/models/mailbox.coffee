###
    @file: mailbox.coffee
    @author: Mikolaj Pawlikowski (mikolaj@pawlikowski.pl/seeker89@github)
    @description: 
        The model used to wrap tasks on other servers:
            * fetching mails with node-imap,
            * parsing mail with nodeparser,
            * saving mail to the database,
            * sending mail with nodemailer,
            * flagging mail on remote servers (not yet implemented)
###

nodemailer = require "nodemailer"
imap = require "imap"
mailparser = require "mailparser"


# helpers

getDateSent = (mailParsedObject) ->
    # choose the right date
    if mailParsedObject.headers.date
        if mailParsedObject.headers.date instanceof Array
            # if an array pick the first date
            dateSent = new Date mailParsedObject.headers.date[0]
        else
            # else take the whole thing
            dateSent = new Date mailParsedObject.headers.date
    else
        dateSent = new Date()


# Destroy helpers

Mailbox::destroyMails = (callback) ->
    Mail.requestDestroy "bymailbox", key: @id, callback

Mailbox::destroyMailsToBe = (callback) ->
    params =
        startkey: [@id]
        endkey: [@id + "0"]
    MailToBe.requestDestroy "bymailbox", params, callback

Mailbox::destroyAttachments = (callback) ->
    Attachment.requestDestroy "bymailbox", key: @id, callback

# Just to be able to recognise the mailbox in the console
Mailbox::toString = ->
    "[Mailbox #{@name} #{@id}]"

Mailbox::log = (msg) ->
    console.info "#{@} #{msg}"


Mailbox::fetchFinished = (callback) ->
    @updateAttributes ImapLastFetchedDate: new Date(), (error) =>
        if error
            callback error
        else
            LogMessage.createNewMailInfo @, callback
            
Mailbox::fetchFailed = (callback) ->
    data =
        status: "Mail check failed."

    @updateAttributes data, (error) =>
        if error
            callback error
        else
            LogMessage.createCheckMailError @, callback

Mailbox::importError = (callback) ->
    data =
        imported: false
        status: "Could not prepare the import."

    @updateAttributes data, (error) =>
        if error
            callback error if callback?
        else
            LogMessage.createImportPreparationError @, callback

Mailbox::importSuccessfull = (callback) ->
    data =
        imported: true
        status: "Import successful !"

    @updateAttributes data, (error) =>
        if error
            callback error
        else
            LogMessage.createImportSuccess @, callback

Mailbox::importFailed = (callback) ->
    data =
        imported: false
        importing: false
        activated: false

    @updateAttributes data, (error) =>
        if error
            callback error
        else
            LogMessage.createBoxImportError @

Mailbox::progress = (progress, callback) ->
    data =
        status: "Import #{progress} %"

    @updateAttributes data, (error) =>
        LogMessage.createImportProgressInfo @, progress, callback


Mailbox::markError = (error, callback) ->
    data =
        status: error.toString()

    @updateAttributes data, (err) ->
        if err
            callback err
        else
            LogMessage.createImportError error, callback
    
###
    Generic function to send mails, using nodemailer
###
Mailbox::sendMail = (data, callback) ->
    
    # create the connection - transport object, 
    # and configure it with our mialbox's data
    transport = nodemailer.createTransport "SMTP",
        host: @SmtpServer
        secureConnection: @SmtpSsl
        port: @SmtpPort
        auth:
            user: @login
            pass: @password

    # configure the message object to send
    message =
        from: @SmtpSendAs
        to: data.to
        cc: data.cc if data.cc?
        bcc: data.bcc if data.bcc?
        subject: data.subject
        headers: data.headers if data.headers?
        html: data.html
        generateTextFromHTML: true
        
    @log "Sending Mail"
    transport.sendMail message, (error) ->
        if error
            console.log error
            callback error
        else
            @log "Message sent successfully!"
            callback()

    transport.close()


###
    ## Fetching new mail from server
    
    # @job - kue job
    # @callback - success callback
    # @limit - how many new messages we want to download at max

###

Mailbox::connectImapServer = (callback) ->

    server = new imap.ImapConnection
        username: @login
        password: @password
        host: @ImapServer
        port: @ImapPort
        secure: @ImapSecure

    server.on "alert", (alert) =>
        @log "[SERVER ALERT] #{alert}"

    server.on "error", (err) =>
        @log "[ERROR]: #{err.toString()}"
        @updateAttributes status: err.toString(), (error) ->
            LogMessage.createBoxImportError ->
                callback err

    server.on "close", (err) =>
        if err
            @log "Connection closed (error: #{err.toString()})"
        else
            @log "Server connection closed."
     
    @log "Try to connect..."
    if @ImapServer?
        server.connect (err) =>
            @log "Connection established successfully"
            callback err, server
    else
        @log 'No host defined'
        callback new Error 'No host defined'
             

Mailbox::openInbox = (callback) ->
    @connectImapServer (err, server) =>
        if err
            # error is not directly returned because in case of wrong
            # credentials it displays password in logs.
            @log "[Error] #{err.message}"
            callback new Error("Connection failed")
        else
            server.openBox 'INBOX', false, (err, box) =>
                @log "INBOX opened successfully"
                callback err, server

                
Mailbox::closeBox = (server, callback) ->
   server.closeBox (err) =>
        if err
            @log "cant close box"
            callback err
        else
            server.logout =>
                @log "logged out from IMAP server"
                callback()


Mailbox::fetchMessage = (server, mailToBe, callback) ->
    
    if typeof mailToBe is "string"
        remoteId = mailToBe
    else
        remoteId = mailToBe.remoteId

    fetch = server.fetch remoteId,
        request:
            body: 'full'
            headers: false

    messageFlags = []
    fetch.on 'message', (message) =>
 
        parser = new mailparser.MailParser()

        parser.on "end", (mailParsedObject) =>
            dateSent = getDateSent mailParsedObject
            attachments = mailParsedObject.attachments
            mail =
                mailbox: @id
                date: dateSent.toJSON()
                dateValueOf: dateSent.valueOf()
                createdAt: new Date().valueOf()
                from: JSON.stringify mailParsedObject.from
                to: JSON.stringify mailParsedObject.to
                cc: JSON.stringify mailParsedObject.cc
                subject: mailParsedObject.subject
                priority: mailParsedObject.priority
                text: mailParsedObject.text
                html: mailParsedObject.html
                idRemoteMailbox: remoteId
                headersRaw: JSON.stringify mailParsedObject.headers
                references: mailParsedObject.references or ""
                inReplyTo: mailParsedObject.inReplyTo or ""
                flags: JSON.stringify messageFlags
                read: "\\Seen" in messageFlags
                flagged: "\\Flagged" in messageFlags
                hasAttachments: if mailParsedObject.attachments then true else false

            Mail.create mail, (err, mail) =>
                if err
                    callback err
                else
                    msg = "New mail created: #{mail.idRemoteMailbox}"
                    msg += " #{mail.id} [#{mail.subject}] "
                    msg += JSON.stringify mail.from
                    @log msg
                    
                    mail.saveAttachments attachments, (err) ->
                        return callback(err) if err

                        if typeof mailToBe is "string"
                            callback null, mail
                        else
                            mailToBe.destroy (error) ->
                                return callback(err) if err
                                callback null, mail

        message.on "data", (data) ->
            # on data, we feed the parser
            parser.write data.toString()

        message.on "end", ->
            # additional data to store, which is "forgotten" byt the parser
            # well, for now, we will store it on the parser itself
            messageFlags = message.flags
            do parser.end
     
Mailbox::fetchLastChanges = (server, callback) ->
    @log "fetch last modification started."
    @log "1:#{@ImapLastFetchedId}"
    fetch = server.fetch "1:#{@ImapLastFetchedId}"
    flagDict = {}
    fetch.on 'message', (msg) =>
        msg.on 'end', =>
            flagDict[msg.seqno] = msg.flags

    fetch.on 'end', (msg) =>
        @log "fetch modification finished."
        Mail.fromMailbox key: @id, (err, mails) =>
            return callback err if err
            for mail in mails
                flags = flagDict[mail.idRemoteMailbox]
                if flags?
                    mail.updateFlags flags
                else
                    mail.destroy()
            callback()

Mailbox::getNewMail = (job, callback, limit=250) ->
    
    # global vars
    debug = true
    
    # reload
    id = Number(@ImapLastFetchedId) + 1
    console.log "Fetching mail #{@} | UID #{id}:#{id + limit})"
                            
    emitOnErr = (server, err) ->
        if err
            console.log err
            server.emit "error", err if server?
            callback err

    @openInbox (err, server) =>
        return emitOnErr server, err if err
        loadNewMails server, id, =>
            @log "New Mails fetched"
            @fetchLastChanges server, =>
                @closeBox server, callback
            
    loadNewMails = (server, id, localCallback) =>
        range = "#{id}:#{id + limit}"
        server.search [['UID', range]], (err, results) =>
            return emitOnErr(server, err) if err

            unless results.length
                @log "Nothing to download"
                localCallback err
            else
                @log "#{results.length} mails to download"
                LogMessage.createImportInfo results, @, ->
                    fetchOne server, 0, results

    fetchOne = (server, i, results, mailsDone) =>
        @log "fetch new mail: #{i}/#{results.length}"
        mailsDone = 0

        if i < results.length
            remoteId = results[i]

            @fetchMessage server, remoteId, (err, mail) =>
                if err
                    emitOnErr server, err
                else
                    if @ImapLastFetchedId < mail.idRemoteMailbox
                        data = ImapLastFetchedId: mail.idRemoteMailbox
                        @updateAttributes data, (err) ->
                            if err
                                emitOnErr server, err
                            else
                                mailsDone++
                                job.progress mailsDone, results.length

                                if mailsDone is results.length
                                    localCallback()
                                else
                                    fetchOne(server, i + 1, results, mailsDone)

        else
            server.logout ->
                if mailsDone isnt results.length
                    msg = "Could not import all the mail. Retry"
                    server.emit "error", new Error(msg)
            localCallback()


###
    ## Specialised function to prepare a new mailbox for import and fetching new mail
###

Mailbox::setupImport = (callback) ->
    
    # global vars
    mailbox = @
 
    @openInbox (err, server) ->
        return emitOnErr server, err if err
        loadInboxMails server
              
    emitOnErr = (server, err) ->
        if err
            console.log err
            server.emit "error", err if server?
            callback err

    loadInboxMails = (server) =>
        server.search ['ALL'], (err, results) =>
            if err
                emitOnErr server, err
            else
                @log "Search query succeeded"

                unless results.length
                    @log "No message to fetch"
                    server.logout()
                    callback()
                else
                    @log "#{results.length} mails to download"
                    @log "Start grabing mail ids"
                    fetchOne server, results, 0, 0, results.length, 0

            
    # for every ID, fetch the message
    fetchOne = (server, results, i, mailsDone, mailsToGo, maxId) =>
        
        if i < results.length
            
            id = results[i]
        
            # find the biggest ID
            idInt = parseInt id
            maxId = idInt if idInt > maxId
    
            mailbox.mailsToBe.create remoteId: idInt, (error, mailToBe) =>
                if error
                    server.logout -> server.emit "error", error
                else
                    mailsDone++
        
                    if mailsDone is mailsToGo
                        @log "Finished saving ids to database"
                        @log "max id = #{maxId}"
                        data =
                            mailsToImport: results.length
                            ImapLastFetchedId: maxId
                            activated: true
                            importing: true

                        @updateAttributes data, (err) =>
                            server.logout () =>
                                @log "All mail ids collected"
                                callback err
                    else
                        fetchOne server, results, i + 1, mailsDone, mailsToGo, maxId
        else
            # synchronise - all ids saved to the db
            if mailsDone isnt mailsToGo
                server.logout ->
                    msg =  "Error occured - not all ids could be stored to the database"
                    server.emit "error", new Error msg
                    callback()
    

###
    ## Specialised function to get as much mails as possible from ids stored 
    # previously in the database
###

Mailbox::doImport = (job, callback) ->

    emitOnErr = (server, err) ->
        if err and server?
            server.logout () ->
                console.log err
                server.emit "error", err
  
    @openInbox (err, server)  =>
        MailToBe.fromMailbox @, (err, mailsToBe) =>
            if err
                emitOnErr server, err
            else if mailsToBe.length is 0
                @log "Import: Nothing to download"
                server.logout()
                callback()
            else
                fetchMails server, mailsToBe, 0, mailsToBe.length, 0
                    
    fetchMails = (server, mailsToBe, i, mailsToGo, mailsDone) =>
        @log "Import progress:  #{i}/#{mailsToBe.length}"
        
        if i < mailsToBe.length
            mailToBe = mailsToBe[i]

            @fetchMessage server, mailToBe, (err) =>
                if err
                    @log 'Mail creation error, skip this message'
                    console.log err
                    fetchMails server, mailsToBe, i + 1, mailsToGo, mailsDone
                else
                    mailsDone++
                    diff = mailsToGo - mailsDone
                    importProgress = @mailsToImport - diff
                    job.progress importProgress, @mailsToImport
                    
                    if mailsToGo is mailsDone
                        callback()
                    else
                        fetchMails server, mailsToBe, i + 1, mailsToGo, mailsDone
                                       
        else
            server.logout =>
                if mailsToGo isnt mailsDone
                    msg = "The box was not fully imported."
                    server.emit 'error', new Error msg
                callback()

Mailbox::markMailAsRead = (mail, callback) ->
    @log "Add read flag to mail #{mail.idRemoteMailbox}"
    @openInbox (err, server) =>
        if err
            console.log err if err
            @closeBox ->
                callback err
        else
            server.addFlags mail.idRemoteMailbox, 'Seen', (err) =>
                if err
                    @log "mail #{mail.idRemoteMailbox} not marked as seen"
                    console.log err
                else
                    @log "mail #{mail.idRemoteMailbox} marked as seen"
                @closeBox server, callback
