#!/usr/bin/env coffee

app = module.exports = require('railway').createServer()

if not module.parent
    port = process.env.PORT or 8001
    app.listen port
    console.log "Railway server listening on port %d within %s environment", port, app.settings.env
    
    # setup KUE
    @kue = require 'kue'
    Job = @kue.Job
    @kue.app.listen 3003
    
    @jobs = @kue.createQueue()
    
    # @jobs.on "job complete", (id) ->
    #   Job.get id, (error, job) ->
    #     return if error
    #     createCheckJob job.data.mb, 1000 * 60 * 0.5, (error) ->
    #       return if error
    #       job.remove (err) ->
    #         throw err if err
    #         console.log job.data.title + " #" + job.id + " complete job removed"
    #       
    # @jobs.on "job error", (id) ->
    #   Job.get id, (error, job) ->
    #     return if error
    #     createCheckJob job.data.mb, 1000 * 60 * 1, (error) ->
    #       console.log error if error

# BUILD JOBS

    createCheckJob = (mb, delay=0, callback) =>
      job = @jobs.create("check mailbox",
        mailbox: mb
        num: 250
        title: "Check of " + mb + " at " + new Date().toUTCString()
      ).delay(delay).save(callback)
       
      job.on 'complete', () ->
        console.log job.data.title + " #" + job.id + " complete"
        createCheckJob mb, 1000 * 60 * 0.5
      job.on 'failed', () ->
        console.log job.data.title + " #" + job.id + " failed"
        createCheckJob mb, 1000 * 60 * 1
      job.on 'progress', (progress) ->
        console.log job.data.title + ' #' + job.id + ' ' + progress + '% complete'
        
    createCheckJobs = =>
      Mailbox.all (err, mbs) =>
        for mb in mbs
          createCheckJob mb, 1000 * 0.5
          
          
    # set-up CRON
    createCheckJobs()
    
    @jobs.promote()

    # KUE jobs
    @jobs.process "check mailbox", 1, (job, done) ->
      console.log job.data.title + " #" + job.id + " job started"
      (Mailbox job.data.mailbox).getNewMail job.data.num, done

